import Foundation

/// The shipping roster of machines.
///
/// These are the default values only. `BikeCatalog.load()` prefers a
/// `Bikes.json` file in the app bundle when one is present, which lets balance
/// changes ship as data rather than as a new binary.
public enum BikeCatalog {

    /// Lightweight 250-class machine. Rewards momentum and precision over power.
    public static let scoutFX250 = BikeSpec(
        id: "scout_fx250",
        displayName: "Scout FX250",
        className: "250 Class",
        flavorText: "Light, forgiving and quick to change direction. The machine that teaches you the rhythm sections.",
        chassisMass: 104,
        riderMass: 76,
        centerOfMassOffset: Vector2Data(-0.02, 0.62),
        momentOfInertia: 62,
        wheelbase: 1.47,
        axleHeight: 0.06,
        frontWheelRadius: 0.36,
        rearWheelRadius: 0.34,
        wheelInertia: 0.72,
        frontSuspension: SuspensionSpec(travel: 0.30, stiffness: 20_500, compressionDamping: 1_500,
                                        reboundDamping: 2_200, bumpStopStiffness: 150_000, preload: 0.30),
        rearSuspension: SuspensionSpec(travel: 0.31, stiffness: 23_000, compressionDamping: 1_750,
                                       reboundDamping: 2_600, bumpStopStiffness: 175_000, preload: 0.33),
        engine: EngineSpec(peakTorque: 28, peakTorqueRPM: 8_200, redlineRPM: 13_000, idleRPM: 1_900,
                           overallGearRatio: 6.4, flywheelInertia: 0.055, throttleResponse: 9.0),
        frontBrakeTorque: 720,
        rearBrakeTorque: 340,
        tyreStiffness: 14_000,
        tyreGripMultiplier: 1.02,
        airRotationTorque: 165,
        airRotationDamping: 0.65,
        dragArea: 0.52,
        riderShiftRange: 0.30,
        landingForgiveness: 0.44
    )

    /// Balanced 450-class machine. More torque, more mass, less patience.
    public static let vantageR450 = BikeSpec(
        id: "vantage_r450",
        displayName: "Vantage R450",
        className: "450 Class",
        flavorText: "Serious torque and a planted chassis. Punishes a lazy throttle hand, rewards a disciplined one.",
        chassisMass: 112,
        riderMass: 78,
        centerOfMassOffset: Vector2Data(-0.01, 0.64),
        momentOfInertia: 71,
        wheelbase: 1.50,
        axleHeight: 0.06,
        frontWheelRadius: 0.37,
        rearWheelRadius: 0.35,
        wheelInertia: 0.84,
        frontSuspension: SuspensionSpec(travel: 0.31, stiffness: 23_500, compressionDamping: 1_700,
                                        reboundDamping: 2_500, bumpStopStiffness: 180_000, preload: 0.30),
        rearSuspension: SuspensionSpec(travel: 0.32, stiffness: 26_500, compressionDamping: 2_000,
                                       reboundDamping: 3_000, bumpStopStiffness: 210_000, preload: 0.33),
        engine: EngineSpec(peakTorque: 48, peakTorqueRPM: 7_000, redlineRPM: 11_200, idleRPM: 1_700,
                           overallGearRatio: 6.0, flywheelInertia: 0.082, throttleResponse: 8.0),
        frontBrakeTorque: 810,
        rearBrakeTorque: 400,
        tyreStiffness: 16_000,
        tyreGripMultiplier: 1.00,
        airRotationTorque: 150,
        airRotationDamping: 0.60,
        dragArea: 0.55,
        riderShiftRange: 0.31,
        landingForgiveness: 0.40
    )

    /// Open-class prototype. Fastest machine on the roster and the least forgiving.
    public static let apexPrototype = BikeSpec(
        id: "apex_prototype",
        displayName: "Apex Prototype",
        className: "Open Class",
        flavorText: "A works bike with no compromises left in it. Every mistake arrives sooner and costs more.",
        chassisMass: 108,
        riderMass: 76,
        centerOfMassOffset: Vector2Data(0.00, 0.60),
        momentOfInertia: 66,
        wheelbase: 1.49,
        axleHeight: 0.05,
        frontWheelRadius: 0.37,
        rearWheelRadius: 0.35,
        wheelInertia: 0.78,
        frontSuspension: SuspensionSpec(travel: 0.32, stiffness: 25_500, compressionDamping: 1_900,
                                        reboundDamping: 2_800, bumpStopStiffness: 200_000, preload: 0.28),
        rearSuspension: SuspensionSpec(travel: 0.33, stiffness: 28_500, compressionDamping: 2_150,
                                       reboundDamping: 3_250, bumpStopStiffness: 230_000, preload: 0.31),
        engine: EngineSpec(peakTorque: 55, peakTorqueRPM: 8_000, redlineRPM: 12_500, idleRPM: 1_800,
                           overallGearRatio: 5.7, flywheelInertia: 0.070, throttleResponse: 11.0),
        frontBrakeTorque: 880,
        rearBrakeTorque: 430,
        tyreStiffness: 17_500,
        tyreGripMultiplier: 1.06,
        airRotationTorque: 180,
        airRotationDamping: 0.55,
        dragArea: 0.50,
        riderShiftRange: 0.32,
        landingForgiveness: 0.37
    )

    /// Built-in roster, in unlock order.
    public static let builtIn: [BikeSpec] = [scoutFX250, vantageR450, apexPrototype]

    /// Loads the roster, preferring bundled data over the compiled-in defaults.
    ///
    /// A malformed or missing `Bikes.json` is not a fatal condition: the game
    /// falls back to `builtIn` so a bad data drop can never brick the app.
    public static func load(from bundle: Bundle = .main) -> [BikeSpec] {
        guard let url = bundle.url(forResource: "Bikes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let specs = try? JSONDecoder().decode([BikeSpec].self, from: data),
              !specs.isEmpty else {
            return builtIn
        }
        return specs
    }

    public static func spec(withID id: String, in roster: [BikeSpec] = builtIn) -> BikeSpec {
        roster.first { $0.id == id } ?? scoutFX250
    }

    /// Purchase price in career currency. The starter machine is free.
    public static func price(for id: String) -> Int {
        switch id {
        case scoutFX250.id: return 0
        case vantageR450.id: return 12_000
        case apexPrototype.id: return 38_000
        default: return 25_000
        }
    }
}
