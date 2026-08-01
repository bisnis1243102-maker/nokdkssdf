//
//  Shaders.metal
//  Neon Reign
//
//  Full-screen post-process chain driven by RenderPipeline's SCNTechnique.
//  Passes, in order: bright pass -> separable blur -> screen-space
//  reflections -> light shafts -> composite (ACES tonemap, grain, chromatic
//  aberration, vignette) -> FXAA.
//
//  Every fragment entry point here is referenced by name from the technique
//  dictionary in RenderPipeline.swift; renaming one without the other silently
//  drops the pass at runtime.
//

#include <metal_stdlib>

using namespace metal;

// scn_metal declares its uniform structs with unqualified `float4x4`, so it
// only compiles once `metal` is in scope — this include must stay below the
// using-directive.
#include <SceneKit/scn_metal>

// MARK: - Shared quad plumbing

struct QuadIn {
    float4 position [[attribute(SCNVertexSemanticPosition)]];
};

struct QuadOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadOut nr_quad_vertex(QuadIn in [[stage_in]])
{
    QuadOut out;
    out.position = in.position;
    // Clip space (-1..1) to texture space (0..1), y flipped.
    out.uv = float2((in.position.x + 1.0) * 0.5,
                    1.0 - (in.position.y + 1.0) * 0.5);
    return out;
}

constexpr sampler nr_sampler(coord::normalized,
                             address::clamp_to_edge,
                             filter::linear);

static inline float nr_luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Hardware depth is heavily non-linear; this is enough to compare relative
// depths inside a screen-space march without needing the projection matrix.
static inline float nr_linear_depth(float d)
{
    const float near = 0.1;
    const float far  = 900.0;
    return (2.0 * near) / (far + near - d * (far - near));
}

// MARK: - Zero fill
//
// Stands in for passes the current quality tier skipped: the composite always
// samples four buffers, so the skipped ones point at this cleared target.

fragment half4 nr_zero_fragment(QuadOut v [[stage_in]])
{
    return half4(0.0h, 0.0h, 0.0h, 1.0h);
}

// MARK: - Bright pass
//
// Anything above the threshold is bloom fuel. Neon signs and headlights are
// authored well above 1.0 in emission, so they dominate this buffer.

fragment half4 nr_bright_fragment(QuadOut v [[stage_in]],
                                  texture2d<float, access::sample> colorSampler [[texture(0)]],
                                  constant float &uThreshold [[buffer(0)]])
{
    float3 c = colorSampler.sample(nr_sampler, v.uv).rgb;
    float l = nr_luma(c);
    float k = max(0.0, l - uThreshold);
    // Soft knee so the bloom doesn't pop as things cross the threshold.
    float w = k / (k + 0.6);
    return half4(half3(c * w), 1.0h);
}

// MARK: - Separable gaussian
//
// Nine taps with linear-sampling pairs, run once horizontally and once
// vertically. uDirection is (1,0) or (0,1) scaled by texel size.

fragment half4 nr_blur_fragment(QuadOut v [[stage_in]],
                                texture2d<float, access::sample> colorSampler [[texture(0)]],
                                constant float &uDirX [[buffer(0)]],
                                constant float &uDirY [[buffer(1)]])
{
    float2 uDirection = float2(uDirX, uDirY);

    const float w0 = 0.227027;
    const float w1 = 0.316216;
    const float w2 = 0.070270;
    const float o1 = 1.384615;
    const float o2 = 3.230769;

    float3 acc = colorSampler.sample(nr_sampler, v.uv).rgb * w0;
    acc += colorSampler.sample(nr_sampler, v.uv + uDirection * o1).rgb * w1;
    acc += colorSampler.sample(nr_sampler, v.uv - uDirection * o1).rgb * w1;
    acc += colorSampler.sample(nr_sampler, v.uv + uDirection * o2).rgb * w2;
    acc += colorSampler.sample(nr_sampler, v.uv - uDirection * o2).rgb * w2;

    return half4(half3(acc), 1.0h);
}

// MARK: - Screen-space reflections
//
// Raymarches the depth buffer for the mirrored ray. Only the lower half of the
// screen is marched, because the reflective surface that matters is the road:
// this keeps the cost bounded and stops facades smearing into the sky.

fragment half4 nr_ssr_fragment(QuadOut v [[stage_in]],
                               texture2d<float, access::sample> colorSampler [[texture(0)]],
                               texture2d<float, access::sample> depthSampler [[texture(1)]],
                               constant float &uWetness [[buffer(0)]])
{
    // Ground occupies roughly the bottom of the frame with a chase camera.
    float groundMask = smoothstep(0.52, 0.78, v.uv.y);
    if (groundMask <= 0.001 || uWetness <= 0.001) {
        return half4(0.0h);
    }

    float d = nr_linear_depth(depthSampler.sample(nr_sampler, v.uv).r);

    // Mirror upwards from the horizon: sample what is above this pixel,
    // stepping further the closer the pixel is to the camera.
    float3 hit = float3(0.0);
    float found = 0.0;
    float stepSize = mix(0.006, 0.030, saturate(d * 4.0));

    for (int i = 1; i <= 12; ++i) {
        float2 uv = float2(v.uv.x, v.uv.y - stepSize * float(i));
        if (uv.y < 0.0) { break; }
        float sd = nr_linear_depth(depthSampler.sample(nr_sampler, uv).r);
        float3 sc = colorSampler.sample(nr_sampler, uv).rgb;
        // Accept the sample when it is geometry in front of the road plane,
        // or when it is bright enough to be a light source worth reflecting.
        if (sd < d - 0.0005 || nr_luma(sc) > 0.55) {
            hit = sc;
            found = 1.0 - float(i) / 13.0;   // fade with march distance
            break;
        }
    }

    float3 refl = hit * found * groundMask * uWetness;
    // Reflections are dimmer and slightly cooler than the source.
    refl *= float3(0.78, 0.84, 1.0);
    return half4(half3(refl), 1.0h);
}

// MARK: - Light shafts
//
// Radial blur toward the sun's screen position, masked to bright pixels.

fragment half4 nr_godray_fragment(QuadOut v [[stage_in]],
                                  texture2d<float, access::sample> colorSampler [[texture(0)]],
                                  constant float &uSunX [[buffer(0)]],
                                  constant float &uSunY [[buffer(1)]],
                                  constant float &uStrength [[buffer(2)]])
{
    if (uStrength <= 0.001) { return half4(0.0h); }
    float2 uSunUV = float2(uSunX, uSunY);

    float2 delta = (v.uv - uSunUV) / 24.0;
    float2 uv = v.uv;
    float3 acc = float3(0.0);
    float decay = 1.0;

    for (int i = 0; i < 24; ++i) {
        uv -= delta;
        float3 c = colorSampler.sample(nr_sampler, saturate(uv)).rgb;
        // Only very bright pixels seed a shaft.
        float m = smoothstep(0.62, 1.05, nr_luma(c));
        acc += c * m * decay;
        decay *= 0.92;
    }

    acc /= 24.0;
    // Shafts fade out away from the sun.
    float falloff = 1.0 - saturate(length(v.uv - uSunUV) * 1.1);
    return half4(half3(acc * uStrength * falloff), 1.0h);
}

// MARK: - Composite
//
// Scene + bloom + reflections + shafts, then the grade: ACES tonemap, chromatic
// aberration toward the edges, film grain, vignette.

static inline float3 nr_aces(float3 x)
{
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

static inline float nr_hash(float2 p)
{
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

fragment half4 nr_composite_fragment(QuadOut v [[stage_in]],
                                     texture2d<float, access::sample> colorSampler [[texture(0)]],
                                     texture2d<float, access::sample> bloomSampler [[texture(1)]],
                                     texture2d<float, access::sample> reflectSampler [[texture(2)]],
                                     texture2d<float, access::sample> raySampler [[texture(3)]],
                                     constant float &uBloom [[buffer(0)]],
                                     constant float &uExposure [[buffer(1)]],
                                     constant float &uGrain [[buffer(2)]],
                                     constant float &uTime [[buffer(3)]],
                                     constant float &uAberration [[buffer(4)]])
{
    float2 uv = v.uv;
    float2 fromCentre = uv - 0.5;
    float r2 = dot(fromCentre, fromCentre);

    // Chromatic aberration: split the channels radially, stronger at the edges.
    float ca = uAberration * r2;
    float3 scene;
    scene.r = colorSampler.sample(nr_sampler, uv + fromCentre * ca).r;
    scene.g = colorSampler.sample(nr_sampler, uv).g;
    scene.b = colorSampler.sample(nr_sampler, uv - fromCentre * ca).b;

    float3 bloom = bloomSampler.sample(nr_sampler, uv).rgb;
    float3 refl  = reflectSampler.sample(nr_sampler, uv).rgb;
    float3 rays  = raySampler.sample(nr_sampler, uv).rgb;

    float3 c = scene + refl;
    c += bloom * uBloom;
    c += rays;

    c *= uExposure;
    c = nr_aces(c);

    // Grain, animated so it does not look like a static overlay.
    float g = nr_hash(uv * float2(1024.0, 768.0) + uTime) - 0.5;
    c += g * uGrain;

    // Vignette.
    c *= 1.0 - saturate(r2 * 1.25) * 0.55;

    return half4(half3(saturate(c)), 1.0h);
}

// MARK: - FXAA
//
// Ultra only. A cheap edge-directed blend that takes the stair-stepping off
// long diagonal roof and road edges after the grade.

fragment half4 nr_fxaa_fragment(QuadOut v [[stage_in]],
                                texture2d<float, access::sample> colorSampler [[texture(0)]],
                                constant float &uTexelX [[buffer(0)]],
                                constant float &uTexelY [[buffer(1)]])
{
    float2 uTexel = float2(uTexelX, uTexelY);
    float3 rgbM = colorSampler.sample(nr_sampler, v.uv).rgb;
    float3 rgbNW = colorSampler.sample(nr_sampler, v.uv + float2(-uTexel.x, -uTexel.y)).rgb;
    float3 rgbNE = colorSampler.sample(nr_sampler, v.uv + float2( uTexel.x, -uTexel.y)).rgb;
    float3 rgbSW = colorSampler.sample(nr_sampler, v.uv + float2(-uTexel.x,  uTexel.y)).rgb;
    float3 rgbSE = colorSampler.sample(nr_sampler, v.uv + float2( uTexel.x,  uTexel.y)).rgb;

    float lM  = nr_luma(rgbM);
    float lNW = nr_luma(rgbNW), lNE = nr_luma(rgbNE);
    float lSW = nr_luma(rgbSW), lSE = nr_luma(rgbSE);

    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));

    // Flat area: leave it alone.
    if (lMax - lMin < max(0.03, lMax * 0.125)) {
        return half4(half3(rgbM), 1.0h);
    }

    float2 dir = float2(-((lNW + lNE) - (lSW + lSE)),
                         ((lNW + lSW) - (lNE + lSE)));
    float scale = 1.0 / (min(abs(dir.x), abs(dir.y)) + 0.03125);
    dir = clamp(dir * scale, -8.0, 8.0) * uTexel;

    float3 a = 0.5 * (colorSampler.sample(nr_sampler, v.uv + dir * (1.0 / 3.0 - 0.5)).rgb +
                      colorSampler.sample(nr_sampler, v.uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    float3 b = a * 0.5 + 0.25 * (colorSampler.sample(nr_sampler, v.uv + dir * -0.5).rgb +
                                 colorSampler.sample(nr_sampler, v.uv + dir *  0.5).rgb);

    float lB = nr_luma(b);
    float3 outC = (lB < lMin || lB > lMax) ? a : b;
    return half4(half3(outC), 1.0h);
}
