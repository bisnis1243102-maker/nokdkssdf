import UIKit
import SceneKit

/// Builds and drives the custom post-process chain in `Shaders.metal`.
///
/// The technique is assembled per quality tier: `balanced` runs bloom and the
/// grade only, `high` adds screen-space reflections and light shafts, `ultra`
/// adds FXAA on top. If SceneKit refuses the dictionary — a bad pass or a
/// missing shader function fails at *runtime*, not build time — `make` returns
/// nil and the camera's built-in HDR pipeline carries the frame instead.
final class RenderPipeline {

    private(set) var technique: SCNTechnique?
    private let quality: GraphicsQuality

    init(quality: GraphicsQuality) {
        self.quality = quality
        self.technique = RenderPipeline.make(quality: quality)
    }

    // MARK: Construction

    private static func make(quality: GraphicsQuality) -> SCNTechnique? {
        var passes: [String: Any] = [:]
        var sequence: [String] = []
        var targets: [String: Any] = [:]
        var symbols: [String: Any] = [:]

        func float(_ name: String) { symbols[name] = ["type": "float"] }

        // --- Bloom: bright pass then two half-res blurs -------------------
        targets["nrBright"] = ["type": "color", "scaleFactor": 0.5]
        targets["nrBlurA"]  = ["type": "color", "scaleFactor": 0.5]
        targets["nrBlurB"]  = ["type": "color", "scaleFactor": 0.5]

        passes["nrBrightPass"] = [
            "draw": "DRAW_QUAD",
            "metalVertexShader": "nr_quad_vertex",
            "metalFragmentShader": "nr_bright_fragment",
            "inputs": ["colorSampler": "COLOR"],
            "outputs": ["color": "nrBright"],
        ]
        passes["nrBlurHPass"] = [
            "draw": "DRAW_QUAD",
            "metalVertexShader": "nr_quad_vertex",
            "metalFragmentShader": "nr_blur_fragment",
            "inputs": ["colorSampler": "nrBright",
                       "uDirX": "$uBlurHX", "uDirY": "$uBlurHY"],
            "outputs": ["color": "nrBlurA"],
        ]
        passes["nrBlurVPass"] = [
            "draw": "DRAW_QUAD",
            "metalVertexShader": "nr_quad_vertex",
            "metalFragmentShader": "nr_blur_fragment",
            "inputs": ["colorSampler": "nrBlurA",
                       "uDirX": "$uBlurVX", "uDirY": "$uBlurVY"],
            "outputs": ["color": "nrBlurB"],
        ]
        // Second, wider tier: blur the already-blurred buffer again at quarter
        // resolution for the broad haze that spreads a city's glow.
        targets["nrWideA"] = ["type": "color", "scaleFactor": 0.25]
        targets["nrWideB"] = ["type": "color", "scaleFactor": 0.25]
        passes["nrWideHPass"] = [
            "draw": "DRAW_QUAD",
            "metalVertexShader": "nr_quad_vertex",
            "metalFragmentShader": "nr_blur_fragment",
            "inputs": ["colorSampler": "nrBlurB",
                       "uDirX": "$uWideHX", "uDirY": "$uWideHY"],
            "outputs": ["color": "nrWideA"],
        ]
        passes["nrWideVPass"] = [
            "draw": "DRAW_QUAD",
            "metalVertexShader": "nr_quad_vertex",
            "metalFragmentShader": "nr_blur_fragment",
            "inputs": ["colorSampler": "nrWideA",
                       "uDirX": "$uWideVX", "uDirY": "$uWideVY"],
            "outputs": ["color": "nrWideB"],
        ]

        sequence += ["nrBrightPass", "nrBlurHPass", "nrBlurVPass",
                     "nrWideHPass", "nrWideVPass"]
        float("uThreshold")
        float("uBlurHX"); float("uBlurHY"); float("uBlurVX"); float("uBlurVY")
        float("uWideHX"); float("uWideHY"); float("uWideVX"); float("uWideVY")
        // The bright pass reads its threshold as a symbol too.
        passes["nrBrightPass"] = mergeInputs(passes["nrBrightPass"], ["uThreshold": "$uThreshold"])

        // --- Screen-space reflections -------------------------------------
        if quality.wantsReflections {
            targets["nrReflect"] = ["type": "color", "scaleFactor": 0.5]
            passes["nrSSRPass"] = [
                "draw": "DRAW_QUAD",
                "metalVertexShader": "nr_quad_vertex",
                "metalFragmentShader": "nr_ssr_fragment",
                "inputs": ["colorSampler": "COLOR",
                           "depthSampler": "DEPTH",
                           "uWetness": "$uWetness",
                           "uTime": "$uTime"],
                "outputs": ["color": "nrReflect"],
            ]
            sequence.append("nrSSRPass")
            float("uWetness")
        }

        // --- Light shafts --------------------------------------------------
        if quality.wantsGodRays {
            targets["nrRays"] = ["type": "color", "scaleFactor": 0.5]
            passes["nrRayPass"] = [
                "draw": "DRAW_QUAD",
                "metalVertexShader": "nr_quad_vertex",
                "metalFragmentShader": "nr_godray_fragment",
                "inputs": ["colorSampler": "COLOR",
                           "uSunX": "$uSunX", "uSunY": "$uSunY",
                           "uStrength": "$uRayStrength"],
                "outputs": ["color": "nrRays"],
            ]
            sequence.append("nrRayPass")
            float("uSunX"); float("uSunY"); float("uRayStrength")
        }

        // --- Composite ------------------------------------------------------
        // Passes that were skipped fall back to the bloom buffer's slot being
        // reused; the shader multiplies those contributions by zero-filled
        // targets, so a missing target would be a hard error. Instead we point
        // the unused samplers at an always-present target and zero the symbol.
        let reflectSource = quality.wantsReflections ? "nrReflect" : "nrZero"
        let raySource = quality.wantsGodRays ? "nrRays" : "nrZero"
        if !quality.wantsReflections || !quality.wantsGodRays {
            // A tiny cleared target standing in for the passes we skipped.
            targets["nrZero"] = ["type": "color", "scaleFactor": 0.05]
            passes["nrZeroPass"] = [
                "draw": "DRAW_QUAD",
                "metalVertexShader": "nr_quad_vertex",
                "metalFragmentShader": "nr_zero_fragment",
                "outputs": ["color": "nrZero"],
            ]
            sequence.insert("nrZeroPass", at: 0)
        }

        let compositeOutput = quality.wantsTAA ? "nrGraded" : "COLOR"
        if quality.wantsTAA {
            targets["nrGraded"] = ["type": "color"]
        }

        passes["nrCompositePass"] = [
            "draw": "DRAW_QUAD",
            "metalVertexShader": "nr_quad_vertex",
            "metalFragmentShader": "nr_composite_fragment",
            "inputs": ["colorSampler": "COLOR",
                       "bloomSampler": "nrBlurB",
                       "reflectSampler": reflectSource,
                       "raySampler": raySource,
                       "wideSampler": "nrWideB",
                       "uBloom": "$uBloom",
                       "uExposure": "$uExposure",
                       "uGrain": "$uGrain",
                       "uTime": "$uTime",
                       "uAberration": "$uAberration",
                       "uRainOnLens": "$uRainOnLens"],
            "outputs": ["color": compositeOutput],
        ]
        sequence.append("nrCompositePass")
        float("uBloom"); float("uExposure"); float("uGrain")
        float("uTime"); float("uAberration"); float("uRainOnLens")

        // --- FXAA (ultra only) ---------------------------------------------
        if quality.wantsTAA {
            passes["nrFXAAPass"] = [
                "draw": "DRAW_QUAD",
                "metalVertexShader": "nr_quad_vertex",
                "metalFragmentShader": "nr_fxaa_fragment",
                "inputs": ["colorSampler": "nrGraded",
                           "uTexelX": "$uTexelX", "uTexelY": "$uTexelY"],
                "outputs": ["color": "COLOR"],
            ]
            sequence.append("nrFXAAPass")
            float("uTexelX"); float("uTexelY")
        }

        let dict: [String: Any] = [
            "passes": passes,
            "sequence": sequence,
            "targets": targets,
            "symbols": symbols,
        ]

        guard let t = SCNTechnique(dictionary: dict) else { return nil }

        // Static defaults; the per-frame values are pushed by `update`.
        t.setValue(NSNumber(value: 0.62), forKey: "uThreshold")
        t.setValue(NSNumber(value: 0.0), forKey: "uBlurHY")
        t.setValue(NSNumber(value: 0.0), forKey: "uBlurVX")
        t.setValue(NSNumber(value: 0.0), forKey: "uWideHY")
        t.setValue(NSNumber(value: 0.0), forKey: "uWideVX")
        return t
    }

    private static func mergeInputs(_ pass: Any?, _ extra: [String: String]) -> [String: Any] {
        guard var p = pass as? [String: Any] else { return [:] }
        var inputs = (p["inputs"] as? [String: String]) ?? [:]
        for (k, v) in extra { inputs[k] = v }
        p["inputs"] = inputs
        return p
    }

    // MARK: Per-frame symbols

    /// Pushes the frame's grade and effect parameters into the technique.
    ///
    /// - Parameters:
    ///   - sky: drives exposure, the sun's screen position and shaft strength.
    ///   - wetness: 0...1 from the weather system; scales the road reflections.
    ///   - viewSize: used to convert blur and FXAA offsets into texel units.
    func update(sky: SkyState, wetness: Float, rain: Float,
                viewSize: CGSize, time: Double) {
        guard let t = technique, viewSize.width > 0, viewSize.height > 0 else { return }

        let texelX = Float(1 / viewSize.width)
        let texelY = Float(1 / viewSize.height)

        // Blur runs at half resolution, so the step is two texels wide.
        t.setValue(NSNumber(value: texelX * 2), forKey: "uBlurHX")
        t.setValue(NSNumber(value: texelY * 2), forKey: "uBlurVY")
        // The wide tier runs at quarter res, so each tap reaches four texels.
        t.setValue(NSNumber(value: texelX * 8), forKey: "uWideHX")
        t.setValue(NSNumber(value: texelY * 8), forKey: "uWideVY")
        t.setValue(NSNumber(value: rain), forKey: "uRainOnLens")

        // Night wants a lower bloom threshold and more of it: neon is the point.
        let night = 1 - sky.daylight
        t.setValue(NSNumber(value: 0.75 - night * 0.30), forKey: "uThreshold")
        t.setValue(NSNumber(value: 0.55 + night * 0.85), forKey: "uBloom")

        // Exposure follows the sky, with a lift at night so the city stays legible.
        t.setValue(NSNumber(value: 0.85 + night * 0.55), forKey: "uExposure")
        t.setValue(NSNumber(value: 0.035 + night * 0.045), forKey: "uGrain")
        t.setValue(NSNumber(value: Float(time.truncatingRemainder(dividingBy: 100))), forKey: "uTime")
        t.setValue(NSNumber(value: 0.0035 + night * 0.0030), forKey: "uAberration")

        if quality.wantsReflections {
            t.setValue(NSNumber(value: max(0.18, wetness)), forKey: "uWetness")
        }

        if quality.wantsGodRays {
            // Approximate the sun's screen position from its elevation: high sun
            // sits above the frame (shafts fade), low sun sits on the horizon.
            let sunY = 0.52 - sky.sunElevation * 0.42
            t.setValue(NSNumber(value: Float(0.5)), forKey: "uSunX")
            t.setValue(NSNumber(value: sunY), forKey: "uSunY")
            // Shafts only while the sun is actually up and low in the sky.
            let strength = max(0, sky.duskFactor * 0.75) * (sky.sunElevation > -0.05 ? 1 : 0)
            t.setValue(NSNumber(value: strength), forKey: "uRayStrength")
        }

        if quality.wantsTAA {
            t.setValue(NSNumber(value: texelX), forKey: "uTexelX")
            t.setValue(NSNumber(value: texelY), forKey: "uTexelY")
        }
    }
}
