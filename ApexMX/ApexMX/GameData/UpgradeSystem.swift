import Foundation

/// A category of performance part the player can fit to a machine.
public enum UpgradeCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case engine
    case suspension
    case tyres
    case brakes
    case chassis

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .engine: return "Engine"
        case .suspension: return "Suspension"
        case .tyres: return "Tyres"
        case .brakes: return "Brakes"
        case .chassis: return "Chassis"
        }
    }

    public var summary: String {
        switch self {
        case .engine: return "More torque everywhere in the range. Raises top speed and drive out of corners."
        case .suspension: return "Firmer springs and better damping. Absorbs bigger hits without bottoming out."
        case .tyres: return "A softer compound with more bite. Higher peak grip on every surface."
        case .brakes: return "Stronger stoppers with better feel. Later braking and finer rear-brake air control."
        case .chassis: return "Lighter frame and revised geometry. Quicker rotation in the air and less mass to haul."
        }
    }

    public var iconName: String {
        switch self {
        case .engine: return "bolt.fill"
        case .suspension: return "arrow.up.and.down.circle.fill"
        case .tyres: return "circle.circle.fill"
        case .brakes: return "hand.raised.fill"
        case .chassis: return "square.stack.3d.up.fill"
        }
    }

    /// Levels above stock. Level 0 is the standard part.
    public static let maximumLevel = 5
}

/// The set of parts fitted to one machine.
public struct UpgradeLoadout: Codable, Sendable, Equatable {
    public private(set) var levels: [String: Int]

    public init(levels: [String: Int] = [:]) {
        self.levels = levels
    }

    public func level(_ category: UpgradeCategory) -> Int {
        min(levels[category.rawValue] ?? 0, UpgradeCategory.maximumLevel)
    }

    public mutating func setLevel(_ level: Int, for category: UpgradeCategory) {
        levels[category.rawValue] = min(max(level, 0), UpgradeCategory.maximumLevel)
    }

    /// Total levels fitted; used for the garage's overall rating readout.
    public var totalLevels: Int {
        UpgradeCategory.allCases.reduce(0) { $0 + level($1) }
    }

    /// Cost of the next level in a category, or `nil` when fully upgraded.
    public func upgradeCost(for category: UpgradeCategory) -> Int? {
        let next = level(category) + 1
        guard next <= UpgradeCategory.maximumLevel else { return nil }
        // Costs scale super-linearly so late upgrades remain a meaningful goal.
        return 1_500 * next * next
    }
}

/// Applies fitted parts to a base specification.
///
/// Upgrades are pure transformations of data: the physics never asks what is
/// fitted, it only ever sees a finished `BikeSpec`. That keeps the simulation
/// oblivious to progression and makes the effect of every part testable.
public enum UpgradeSystem {

    /// Per-level multipliers, chosen so a fully upgraded machine is roughly 20%
    /// quicker rather than a different game — skill has to stay dominant.
    private enum Gains {
        static let torquePerLevel = 0.042
        static let suspensionStiffnessPerLevel = 0.035
        static let suspensionDampingPerLevel = 0.045
        static let gripPerLevel = 0.028
        static let brakeTorquePerLevel = 0.055
        static let massReductionPerLevel = 0.014
        static let rotationPerLevel = 0.030
    }

    public static func apply(_ loadout: UpgradeLoadout, to base: BikeSpec) -> BikeSpec {
        var spec = base

        let engine = Double(loadout.level(.engine))
        spec.engine.peakTorque *= 1 + Gains.torquePerLevel * engine
        spec.engine.throttleResponse *= 1 + 0.02 * engine

        let suspension = Double(loadout.level(.suspension))
        let stiffnessScale = 1 + Gains.suspensionStiffnessPerLevel * suspension
        let dampingScale = 1 + Gains.suspensionDampingPerLevel * suspension
        spec.frontSuspension.stiffness *= stiffnessScale
        spec.rearSuspension.stiffness *= stiffnessScale
        spec.frontSuspension.compressionDamping *= dampingScale
        spec.rearSuspension.compressionDamping *= dampingScale
        spec.frontSuspension.reboundDamping *= dampingScale
        spec.rearSuspension.reboundDamping *= dampingScale
        // Better damping also buys a wider landing window, which is what the
        // upgrade actually feels like to the player.
        spec.landingForgiveness *= 1 + 0.030 * suspension

        let tyres = Double(loadout.level(.tyres))
        spec.tyreGripMultiplier *= 1 + Gains.gripPerLevel * tyres
        spec.tyreStiffness *= 1 + 0.020 * tyres

        let brakes = Double(loadout.level(.brakes))
        spec.frontBrakeTorque *= 1 + Gains.brakeTorquePerLevel * brakes
        spec.rearBrakeTorque *= 1 + Gains.brakeTorquePerLevel * brakes

        let chassis = Double(loadout.level(.chassis))
        let massScale = 1 - Gains.massReductionPerLevel * chassis
        spec.chassisMass *= massScale
        spec.momentOfInertia *= massScale
        spec.airRotationTorque *= 1 + Gains.rotationPerLevel * chassis
        spec.dragArea *= 1 - 0.012 * chassis

        return spec
    }

    /// A 0–100 rating per category, for the garage's stat bars.
    public static func rating(for spec: BikeSpec, category: UpgradeCategory) -> Double {
        switch category {
        case .engine:
            return MathUtils.remap(spec.engine.peakTorque, 24, 70, 15, 100)
        case .suspension:
            return MathUtils.remap(spec.rearSuspension.stiffness, 20_000, 36_000, 20, 100)
        case .tyres:
            return MathUtils.remap(spec.tyreGripMultiplier, 0.95, 1.25, 20, 100)
        case .brakes:
            return MathUtils.remap(spec.frontBrakeTorque, 680, 1_200, 20, 100)
        case .chassis:
            return MathUtils.remap(spec.totalMass, 200, 170, 20, 100)
        }
    }
}
