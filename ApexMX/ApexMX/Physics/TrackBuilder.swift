import Foundation

/// Turns a `TrackDefinition` into a sampled `Terrain`.
///
/// Generation is fully deterministic: the same definition produces bit-identical
/// terrain on every device and every run. That is a hard requirement — ghosts,
/// replays and server-side result validation are all worthless if two machines
/// disagree about where the ground is.
public enum TrackBuilder {

    /// Distance of flat run-up before the first feature, giving the field room
    /// to launch off the gate.
    public static let startPadding: Double = 22

    /// Flat run-out after the last feature so a rider crossing the line at speed
    /// has somewhere to slow down.
    public static let endPadding: Double = 30

    public static func build(_ definition: TrackDefinition) -> Terrain {
        var random = DeterministicRandom(seed: definition.seed)
        let spacing = Terrain.sampleSpacing

        var heights: [Double] = []
        var surfaces: [SurfaceType] = []
        heights.reserveCapacity(Int((definition.lapLength + startPadding + endPadding) / spacing) + 8)

        // The start pad is deliberately dead flat: a consistent launch is a
        // skill test, not a terrain lottery.
        appendConstant(height: 0, length: startPadding, surface: .hardDirt,
                       into: &heights, surfaces: &surfaces)

        var elevation: Double = 0
        for feature in definition.features {
            elevation = append(feature,
                               startingAt: elevation,
                               baseSurface: definition.baseSurface,
                               random: &random,
                               into: &heights,
                               surfaces: &surfaces)
        }

        // Bring the run-out back to the start elevation so laps loop seamlessly.
        appendRamp(from: elevation, to: 0, length: endPadding * 0.6, surface: definition.baseSurface,
                   into: &heights, surfaces: &surfaces)
        appendConstant(height: 0, length: endPadding * 0.4, surface: .hardDirt,
                       into: &heights, surfaces: &surfaces)

        applyMicroDetail(to: &heights, random: &random, surfaces: surfaces)
        smooth(&heights, passes: 1)

        return Terrain(heights: heights, surfaces: surfaces, originX: 0)
    }

    // MARK: - Feature construction

    /// Appends one feature and returns the elevation the next feature starts at.
    private static func append(_ feature: TrackFeature,
                               startingAt elevation: Double,
                               baseSurface: SurfaceType,
                               random: inout DeterministicRandom,
                               into heights: inout [Double],
                               surfaces: inout [SurfaceType]) -> Double {
        switch feature {
        case let .straight(length, grade):
            let end = elevation + length * grade
            appendRamp(from: elevation, to: end, length: length, surface: baseSurface,
                       into: &heights, surfaces: &surfaces)
            return end

        case let .tabletop(length, height, lipSharpness):
            // Split as ramp / deck / landing. The lip sharpness biases the ramp
            // easing curve: a sharp lip kicks the bike upward, a rolling lip
            // preserves forward speed.
            let rampLength = length * 0.34
            let deckLength = length * 0.22
            let landingLength = length - rampLength - deckLength
            appendCurve(from: elevation, to: elevation + height, length: rampLength,
                        surface: baseSurface, into: &heights, surfaces: &surfaces) { t in
                let sharp = pow(t, 1.0 + 1.6 * lipSharpness)
                return MathUtils.lerp(MathUtils.smoothstep(0, 1, t), sharp, lipSharpness)
            }
            appendConstant(height: elevation + height, length: deckLength, surface: baseSurface,
                           into: &heights, surfaces: &surfaces)
            appendCurve(from: elevation + height, to: elevation, length: landingLength,
                        surface: baseSurface, into: &heights, surfaces: &surfaces) { t in
                // A landing ramp is close to straight so that a well-matched
                // trajectory meets it flush and keeps its speed.
                MathUtils.lerp(t, MathUtils.smoothstep(0, 1, t), 0.25)
            }
            return elevation

        case let .gap(takeoffLength, gapLength, landingLength, height):
            appendCurve(from: elevation, to: elevation + height, length: takeoffLength,
                        surface: baseSurface, into: &heights, surfaces: &surfaces) { t in
                pow(t, 1.9)
            }
            // The gap floor sits below the takeoff so a short jump is punished
            // by a hard, flat-bottomed landing rather than an instant reset.
            let floor = elevation - height * 0.35
            appendCurve(from: elevation + height, to: floor, length: gapLength * 0.45,
                        surface: .softDirt, into: &heights, surfaces: &surfaces) { t in
                MathUtils.smoothstep(0, 1, t)
            }
            appendCurve(from: floor, to: elevation + height * 0.85, length: gapLength * 0.55,
                        surface: baseSurface, into: &heights, surfaces: &surfaces) { t in
                MathUtils.smoothstep(0, 1, t)
            }
            appendCurve(from: elevation + height * 0.85, to: elevation, length: landingLength,
                        surface: baseSurface, into: &heights, surfaces: &surfaces) { t in
                MathUtils.lerp(t, MathUtils.smoothstep(0, 1, t), 0.2)
            }
            return elevation

        case let .whoops(count, spacing, amplitude):
            // Cosine bumps give a continuous surface with no slope discontinuity,
            // which is what allows a skilled rider to skim across the tops.
            let total = Double(count) * spacing
            appendSampled(length: total, surface: baseSurface,
                          into: &heights, surfaces: &surfaces) { distance in
                let phase = distance / spacing * 2 * .pi
                // Taper the first and last bump so the section blends in.
                let taper = MathUtils.smoothstep(0, spacing, distance)
                    * MathUtils.smoothstep(0, spacing, total - distance)
                return elevation + amplitude * 0.5 * (1 - cos(phase)) * taper
            }
            return elevation

        case let .rhythm(count, spacing, amplitude):
            let total = Double(count) * spacing
            appendSampled(length: total, surface: baseSurface,
                          into: &heights, surfaces: &surfaces) { distance in
                let local = distance.truncatingRemainder(dividingBy: spacing) / spacing
                // Asymmetric profile: steep face, shallower back side.
                let shape: Double
                if local < 0.55 {
                    shape = MathUtils.smoothstep(0, 1, local / 0.55)
                } else {
                    shape = 1 - MathUtils.smoothstep(0, 1, (local - 0.55) / 0.45)
                }
                let taper = MathUtils.smoothstep(0, spacing * 0.8, total - distance)
                return elevation + amplitude * shape * taper
            }
            return elevation

        case let .berm(length, height):
            appendSampled(length: length, surface: .softDirt,
                          into: &heights, surfaces: &surfaces) { distance in
                let t = distance / length
                // A single smooth rise and fall — carrying speed through it
                // costs less than braking for it, but only if the line is right.
                return elevation + height * sin(t * .pi)
            }
            return elevation

        case let .rockGarden(length, roughness):
            appendSampled(length: length, surface: .rock,
                          into: &heights, surfaces: &surfaces) { distance in
                // Layered sine waves at incommensurable frequencies read as
                // broken ground while staying perfectly reproducible.
                let a = sin(distance * 2.7) * 0.5
                let b = sin(distance * 6.1 + 1.3) * 0.28
                let c = sin(distance * 11.3 + 2.7) * 0.14
                let taper = MathUtils.smoothstep(0, 1.5, distance)
                    * MathUtils.smoothstep(0, 1.5, length - distance)
                return elevation + (a + b + c) * roughness * taper
            }
            return elevation

        case let .elevation(length, rise):
            let end = elevation + rise
            appendCurve(from: elevation, to: end, length: length, surface: baseSurface,
                        into: &heights, surfaces: &surfaces) { t in
                MathUtils.smoothstep(0, 1, t)
            }
            return end

        case let .stepUp(length, rise):
            let end = elevation + rise
            appendCurve(from: elevation, to: end, length: length, surface: baseSurface,
                        into: &heights, surfaces: &surfaces) { t in
                // Front-loaded: most of the climb happens early, forming a face
                // the bike can launch from.
                pow(MathUtils.smoothstep(0, 1, t), 0.65)
            }
            return end
        }
    }

    // MARK: - Sampling primitives

    private static func appendConstant(height: Double,
                                       length: Double,
                                       surface: SurfaceType,
                                       into heights: inout [Double],
                                       surfaces: inout [SurfaceType]) {
        appendSampled(length: length, surface: surface, into: &heights, surfaces: &surfaces) { _ in height }
    }

    private static func appendRamp(from start: Double,
                                   to end: Double,
                                   length: Double,
                                   surface: SurfaceType,
                                   into heights: inout [Double],
                                   surfaces: inout [SurfaceType]) {
        appendSampled(length: length, surface: surface, into: &heights, surfaces: &surfaces) { distance in
            MathUtils.lerp(start, end, length > 0 ? distance / length : 0)
        }
    }

    private static func appendCurve(from start: Double,
                                    to end: Double,
                                    length: Double,
                                    surface: SurfaceType,
                                    into heights: inout [Double],
                                    surfaces: inout [SurfaceType],
                                    easing: (Double) -> Double) {
        appendSampled(length: length, surface: surface, into: &heights, surfaces: &surfaces) { distance in
            let t = length > 0 ? MathUtils.clamp01(distance / length) : 1
            return MathUtils.lerp(start, end, easing(t))
        }
    }

    /// Core sampler. Every other primitive funnels through here, which is what
    /// guarantees a consistent sample spacing across the whole track.
    private static func appendSampled(length: Double,
                                      surface: SurfaceType,
                                      into heights: inout [Double],
                                      surfaces: inout [SurfaceType],
                                      height: (Double) -> Double) {
        guard length > 0 else { return }
        let count = max(Int((length / Terrain.sampleSpacing).rounded()), 1)
        for i in 0..<count {
            let distance = Double(i) * Terrain.sampleSpacing
            heights.append(height(distance))
            surfaces.append(surface)
        }
    }

    // MARK: - Detail and conditioning

    /// Adds sub-feature roughness so no stretch of ground is perfectly smooth.
    /// The amplitude follows the surface's deformability, so hardpack stays
    /// clean and sand gets choppy.
    private static func applyMicroDetail(to heights: inout [Double],
                                         random: inout DeterministicRandom,
                                         surfaces: [SurfaceType]) {
        guard heights.count > 4 else { return }
        // Value noise built from a random lattice, interpolated smoothly.
        let latticeStride = 12
        let latticeCount = heights.count / latticeStride + 2
        var lattice = [Double](repeating: 0, count: latticeCount)
        for i in 0..<latticeCount { lattice[i] = random.range(-1, 1) }

        for i in 0..<heights.count {
            // Leave the start pad untouched.
            let padSamples = Int(startPadding / Terrain.sampleSpacing)
            guard i > padSamples else { continue }

            let position = Double(i) / Double(latticeStride)
            let index = Int(position)
            let t = MathUtils.smoothstep(0, 1, position - Double(index))
            let a = lattice[min(index, latticeCount - 1)]
            let b = lattice[min(index + 1, latticeCount - 1)]
            let noise = MathUtils.lerp(a, b, t)

            let deformability = surfaces[i].properties.deformability
            heights[i] += noise * 0.022 * (0.35 + deformability)
        }
    }

    /// A light box filter removes the sharp corners left where features meet.
    /// Sharp corners are not a style choice — they make the suspension spike and
    /// can throw a wheel through the ground on a single step.
    private static func smooth(_ heights: inout [Double], passes: Int) {
        guard heights.count > 2 else { return }
        for _ in 0..<passes {
            var output = heights
            for i in 1..<(heights.count - 1) {
                output[i] = (heights[i - 1] + 2 * heights[i] + heights[i + 1]) * 0.25
            }
            heights = output
        }
    }
}
