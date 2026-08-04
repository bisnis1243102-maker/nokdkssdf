import Foundation

/// Physical properties of a terrain material.
///
/// Surfaces are data, not code: adding a new material means adding a case and a
/// `Properties` entry, and every system that consumes surfaces (traction,
/// rolling resistance, particles, audio) picks it up automatically.
public enum SurfaceType: String, CaseIterable, Codable, Sendable {
    case hardDirt
    case softDirt
    case mud
    case grass
    case sand
    case gravel
    case rock
    case wood
    case concrete

    public struct Properties: Sendable {
        /// Peak coefficient of friction available to the tyre.
        public let grip: Double
        /// Fraction of forward momentum lost per second while rolling.
        public let rollingResistance: Double
        /// How much the surface deforms under load; drives rut depth and dust volume.
        public let deformability: Double
        /// Multiplier on impact absorption. Soft surfaces forgive hard landings.
        public let landingForgiveness: Double
        /// Particle colour, expressed as linear RGB in `[0, 1]`.
        public let particleColor: (r: Double, g: Double, b: Double)
        /// Relative volume of the surface's tyre noise.
        public let tyreNoiseLevel: Double
    }

    public var properties: Properties {
        switch self {
        case .hardDirt:
            return Properties(grip: 1.05, rollingResistance: 0.022, deformability: 0.25,
                              landingForgiveness: 1.00,
                              particleColor: (0.48, 0.35, 0.22), tyreNoiseLevel: 0.55)
        case .softDirt:
            return Properties(grip: 0.92, rollingResistance: 0.038, deformability: 0.70,
                              landingForgiveness: 1.18,
                              particleColor: (0.54, 0.40, 0.26), tyreNoiseLevel: 0.70)
        case .mud:
            return Properties(grip: 0.62, rollingResistance: 0.072, deformability: 0.95,
                              landingForgiveness: 1.30,
                              particleColor: (0.30, 0.24, 0.17), tyreNoiseLevel: 0.85)
        case .grass:
            return Properties(grip: 0.74, rollingResistance: 0.048, deformability: 0.45,
                              landingForgiveness: 1.10,
                              particleColor: (0.34, 0.48, 0.22), tyreNoiseLevel: 0.45)
        case .sand:
            return Properties(grip: 0.70, rollingResistance: 0.095, deformability: 1.00,
                              landingForgiveness: 1.35,
                              particleColor: (0.76, 0.66, 0.44), tyreNoiseLevel: 0.60)
        case .gravel:
            return Properties(grip: 0.80, rollingResistance: 0.055, deformability: 0.60,
                              landingForgiveness: 1.05,
                              particleColor: (0.55, 0.53, 0.50), tyreNoiseLevel: 0.90)
        case .rock:
            return Properties(grip: 1.12, rollingResistance: 0.018, deformability: 0.02,
                              landingForgiveness: 0.80,
                              particleColor: (0.42, 0.41, 0.40), tyreNoiseLevel: 0.75)
        case .wood:
            return Properties(grip: 0.88, rollingResistance: 0.014, deformability: 0.05,
                              landingForgiveness: 0.90,
                              particleColor: (0.46, 0.33, 0.19), tyreNoiseLevel: 0.65)
        case .concrete:
            return Properties(grip: 1.20, rollingResistance: 0.011, deformability: 0.00,
                              landingForgiveness: 0.72,
                              particleColor: (0.62, 0.62, 0.63), tyreNoiseLevel: 0.50)
        }
    }

    public var displayName: String {
        switch self {
        case .hardDirt: return "Hardpack"
        case .softDirt: return "Loam"
        case .mud: return "Mud"
        case .grass: return "Grass"
        case .sand: return "Sand"
        case .gravel: return "Gravel"
        case .rock: return "Rock"
        case .wood: return "Timber"
        case .concrete: return "Concrete"
        }
    }
}
