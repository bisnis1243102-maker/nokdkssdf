import UIKit
import SceneKit

/// Per-material shader modifiers — the effects fixed-function SceneKit can't
/// express. Each snippet is injected into SceneKit's own shader at the named
/// entry point, so they compose with normal PBR lighting and shadows.
///
/// **Every local here is prefixed `nr`.** A modifier body is spliced directly
/// into SceneKit's generated function, sharing its scope, so a bare `n`, `d`,
/// `t` or `f` can collide with a declaration SceneKit already made. When that
/// happens the shader fails to compile and the material renders solid magenta —
/// which is exactly what the first device build did to every road, sidewalk and
/// neon sign in the city. Prefixing is not style; it is the fix.
///
/// Uniforms declared under `#pragma arguments` are set through KVC on the
/// material (`material.setValue(_:forKey:)`).
enum ShaderModifiers {

    /// Master switch. When false, no modifier is attached at all and every
    /// surface falls back to plain PBR — a guaranteed-correct look, and the way
    /// to confirm from the outside whether a magenta surface is a modifier
    /// failure or something else.
    static var enabled = true

    // MARK: Wet road
    //
    // Blends a puddle mask into roughness and reflectivity. `wetness` is driven
    // by the weather system, so rain visibly changes how the whole city reads:
    // dry asphalt is matte, wet asphalt mirrors the neon above it.

    static let wetRoad = """
    #pragma arguments
    float wetness;
    float rain;
    #pragma body
    float2 nrUV = _surface.diffuseTexcoord * 6.0;
    float2 nrCell = floor(nrUV);
    float2 nrFrac = fract(nrUV);
    nrFrac = nrFrac * nrFrac * (3.0 - 2.0 * nrFrac);

    float nrH00 = fract(sin(dot(nrCell, float2(12.9898, 78.233))) * 43758.5453);
    float nrH10 = fract(sin(dot(nrCell + float2(1.0, 0.0), float2(12.9898, 78.233))) * 43758.5453);
    float nrH01 = fract(sin(dot(nrCell + float2(0.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);
    float nrH11 = fract(sin(dot(nrCell + float2(1.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);
    float nrNoise = mix(mix(nrH00, nrH10, nrFrac.x), mix(nrH01, nrH11, nrFrac.x), nrFrac.y);

    float nrPuddle = smoothstep(0.45, 0.85, nrNoise) * wetness;

    // Rain ripples: rings expanding out of an impact point per cell, so
    // standing water visibly reacts to a downpour.
    float nrRipple = 0.0;
    if (rain > 0.01) {
        float2 nrRCell = floor(nrUV * 2.0);
        float2 nrRFrac = fract(nrUV * 2.0) - 0.5;
        float nrSeed = fract(sin(dot(nrRCell, float2(41.7, 17.3))) * 9127.31);
        float nrPhase = fract(u_time * 1.6 + nrSeed);
        float nrDist = length(nrRFrac);
        nrRipple = sin((nrDist - nrPhase) * 34.0) * exp(-nrDist * 6.0) * (1.0 - nrPhase);
        nrRipple *= rain * nrPuddle;
    }

    // Water darkens what it sits on and polishes it.
    _surface.diffuse.rgb *= mix(1.0, 0.45, nrPuddle);
    _surface.roughness = mix(_surface.roughness, 0.04, nrPuddle);
    _surface.metalness = mix(_surface.metalness, 0.25, nrPuddle);
    // Flatten the normal where there is standing water, then disturb it with
    // the ripple rings.
    _surface.normal = normalize(mix(_surface.normal, float3(0.0, 0.0, 1.0), nrPuddle * 0.85));
    _surface.normal = normalize(_surface.normal + float3(nrRipple * 0.35, nrRipple * 0.35, 0.0));
    """

    // MARK: Neon sign
    //
    // Animated flicker, so signs read as running hardware rather than glowing
    // decals. Emission is pushed above 1.0 on purpose — that is what feeds the
    // bloom bright pass.

    static let neonSign = """
    #pragma arguments
    float flickerSeed;
    float nightMix;
    #pragma body
    float nrTime = u_time;
    float nrSlow = sin(nrTime * 1.7 + flickerSeed * 6.28) * 0.5 + 0.5;
    // Occasional hard dropout, like a failing tube.
    float nrGlitch = step(0.985, fract(sin(floor(nrTime * 9.0) + flickerSeed) * 43758.5453));
    float nrLevel = mix(0.75, 1.25, nrSlow) * (1.0 - nrGlitch * 0.85);
    _surface.emission.rgb *= nrLevel * nightMix * 2.6;
    """

    // MARK: Car paint
    //
    // A clearcoat approximation: fresnel rim brightening plus a tighter
    // specular than the base metalness alone would give.

    static let carPaint = """
    #pragma arguments
    float flake;
    #pragma body
    float3 nrN = normalize(_surface.normal);
    float3 nrV = normalize(_surface.view);
    float nrFresnel = pow(1.0 - saturate(dot(nrN, nrV)), 4.0);
    _surface.roughness = mix(_surface.roughness, 0.06, 0.65);
    _surface.metalness = mix(_surface.metalness, 0.85, nrFresnel);
    _surface.diffuse.rgb += _surface.diffuse.rgb * nrFresnel * 0.55;
    // Metallic flake sparkle, scaled by the paint's flake amount.
    float nrSparkle = fract(sin(dot(floor(_surface.diffuseTexcoord * 220.0),
                                    float2(12.9898, 78.233))) * 43758.5453);
    _surface.diffuse.rgb += step(0.992, nrSparkle) * flake * nrFresnel;
    """

    // MARK: Glass
    //
    // Windows and windscreens: fresnel-driven reflectivity with a dark faked
    // interior, so cars don't look like they're made of solid colour.

    static let glass = """
    #pragma body
    float3 nrN = normalize(_surface.normal);
    float3 nrV = normalize(_surface.view);
    float nrFresnel = pow(1.0 - saturate(dot(nrN, nrV)), 3.0);
    _surface.diffuse.rgb = mix(float3(0.02, 0.03, 0.05), _surface.diffuse.rgb, nrFresnel);
    _surface.roughness = 0.03;
    _surface.metalness = mix(0.15, 0.95, nrFresnel);
    """

    // MARK: Foliage
    //
    // Cheap wind: sway the vertices more the further they are from the trunk.

    static let foliageWind = """
    #pragma body
    float nrSway = sin(u_time * 1.4 + _geometry.position.y * 0.6 + _geometry.position.x) * 0.05;
    _geometry.position.x += nrSway * max(0.0, _geometry.position.y);
    _geometry.position.z += nrSway * 0.6 * max(0.0, _geometry.position.y);
    """

    // MARK: Application helpers
    //
    // Each of these is a no-op when `enabled` is false, leaving the material as
    // plain PBR. The uniforms are still set either way, so the weather system
    // can keep writing to them without caring which path is live.

    static func applyWetRoad(to m: SCNMaterial) {
        guard enabled else { return }
        m.shaderModifiers = [.surface: wetRoad]
        m.setValue(NSNumber(value: 0.0), forKey: "wetness")
        m.setValue(NSNumber(value: 0.0), forKey: "rain")
    }

    static func applyNeon(to m: SCNMaterial, seed: Float) {
        guard enabled else { return }
        m.shaderModifiers = [.surface: neonSign]
        m.setValue(NSNumber(value: seed), forKey: "flickerSeed")
        m.setValue(NSNumber(value: 1.0), forKey: "nightMix")
    }

    static func applyCarPaint(to m: SCNMaterial, flake: Float = 0.7) {
        guard enabled else { return }
        m.shaderModifiers = [.surface: carPaint]
        m.setValue(NSNumber(value: flake), forKey: "flake")
    }

    static func applyGlass(to m: SCNMaterial) {
        m.lightingModel = .physicallyBased
        guard enabled else { return }
        m.shaderModifiers = [.surface: glass]
    }

    static func applyFoliage(to m: SCNMaterial) {
        guard enabled else { return }
        m.shaderModifiers = [.geometry: foliageWind]
    }
}
