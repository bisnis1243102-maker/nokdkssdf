import UIKit
import SceneKit

/// Per-material shader modifiers — the effects fixed-function SceneKit can't
/// express. Each snippet is injected into SceneKit's own shader at the named
/// entry point, so they compose with normal PBR lighting and shadows.
///
/// Every modifier reads uniforms declared with `#pragma arguments`; those are
/// set through KVC on the material (`material.setValue(_:forKey:)`).
enum ShaderModifiers {

    // MARK: Wet road
    //
    // Blends a puddle mask into roughness and reflectivity. `wetness` is driven
    // by the weather system, so rain visibly changes how the whole city reads:
    // dry asphalt is matte, wet asphalt mirrors the neon above it.

    static let wetRoad = """
    #pragma arguments
    float wetness;
    #pragma body
    float2 wp = _surface.diffuseTexcoord * 6.0;
    // Two-scale value noise for puddle shapes.
    float2 i0 = floor(wp);
    float2 f0 = fract(wp);
    f0 = f0 * f0 * (3.0 - 2.0 * f0);
    float a = fract(sin(dot(i0, float2(12.9898, 78.233))) * 43758.5453);
    float b = fract(sin(dot(i0 + float2(1.0, 0.0), float2(12.9898, 78.233))) * 43758.5453);
    float c = fract(sin(dot(i0 + float2(0.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);
    float d = fract(sin(dot(i0 + float2(1.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);
    float n = mix(mix(a, b, f0.x), mix(c, d, f0.x), f0.y);

    float puddle = smoothstep(0.45, 0.85, n) * wetness;
    // Water darkens what it sits on and polishes it.
    _surface.diffuse.rgb *= mix(1.0, 0.45, puddle);
    _surface.roughness = mix(_surface.roughness, 0.04, puddle);
    _surface.metalness = mix(_surface.metalness, 0.25, puddle);
    // Flatten the normal where there is standing water.
    _surface.normal = normalize(mix(_surface.normal, float3(0.0, 0.0, 1.0), puddle * 0.85));
    """

    // MARK: Neon sign
    //
    // Animated flicker plus a slow scroll, so signs read as running hardware
    // rather than glowing decals. Emission is pushed above 1.0 on purpose —
    // that is what feeds the bloom bright pass.

    static let neonSign = """
    #pragma arguments
    float flickerSeed;
    float nightMix;
    #pragma body
    float t = u_time;
    float slow = sin(t * 1.7 + flickerSeed * 6.28) * 0.5 + 0.5;
    // Occasional hard dropout, like a failing tube.
    float glitch = step(0.985, fract(sin(floor(t * 9.0) + flickerSeed) * 43758.5453));
    float level = mix(0.75, 1.25, slow) * (1.0 - glitch * 0.85);
    _surface.emission.rgb *= level * nightMix * 2.6;
    """

    // MARK: Car paint
    //
    // A clearcoat approximation: fresnel rim brightening plus a tighter
    // specular than the base metalness alone would give.

    static let carPaint = """
    #pragma arguments
    float flake;
    #pragma body
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float f = pow(1.0 - saturate(dot(n, v)), 4.0);
    _surface.roughness = mix(_surface.roughness, 0.06, 0.65);
    _surface.metalness = mix(_surface.metalness, 0.85, f);
    _surface.diffuse.rgb += _surface.diffuse.rgb * f * 0.55;
    // Metallic flake sparkle, scaled by the paint's flake amount.
    float sparkle = fract(sin(dot(floor(_surface.diffuseTexcoord * 220.0),
                                  float2(12.9898, 78.233))) * 43758.5453);
    _surface.diffuse.rgb += step(0.992, sparkle) * flake * f;
    """

    // MARK: Glass
    //
    // Windows and windscreens: fresnel-driven reflectivity with a dark faked
    // interior, so cars don't look like they're made of solid colour.

    static let glass = """
    #pragma body
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float f = pow(1.0 - saturate(dot(n, v)), 3.0);
    _surface.diffuse.rgb = mix(float3(0.02, 0.03, 0.05), _surface.diffuse.rgb, f);
    _surface.roughness = 0.03;
    _surface.metalness = mix(0.15, 0.95, f);
    """

    // MARK: Foliage
    //
    // Cheap wind: sway the vertices more the further they are from the trunk.

    static let foliageWind = """
    #pragma body
    float sway = sin(u_time * 1.4 + _geometry.position.y * 0.6 + _geometry.position.x) * 0.05;
    _geometry.position.x += sway * max(0.0, _geometry.position.y);
    _geometry.position.z += sway * 0.6 * max(0.0, _geometry.position.y);
    """

    // MARK: Application helpers

    static func applyWetRoad(to m: SCNMaterial) {
        m.shaderModifiers = [.surface: wetRoad]
        m.setValue(NSNumber(value: 0.0), forKey: "wetness")
    }

    static func applyNeon(to m: SCNMaterial, seed: Float) {
        m.shaderModifiers = [.surface: neonSign]
        m.setValue(NSNumber(value: seed), forKey: "flickerSeed")
        m.setValue(NSNumber(value: 1.0), forKey: "nightMix")
    }

    static func applyCarPaint(to m: SCNMaterial, flake: Float = 0.7) {
        m.shaderModifiers = [.surface: carPaint]
        m.setValue(NSNumber(value: flake), forKey: "flake")
    }

    static func applyGlass(to m: SCNMaterial) {
        m.lightingModel = .physicallyBased
        m.shaderModifiers = [.surface: glass]
    }

    static func applyFoliage(to m: SCNMaterial) {
        m.shaderModifiers = [.geometry: foliageWind]
    }
}
