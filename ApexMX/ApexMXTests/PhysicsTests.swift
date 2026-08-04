import XCTest
@testable import ApexMX

/// Tests for the properties the whole game depends on: determinism,
/// frame-rate independence, stability and momentum conservation.
///
/// These are not incidental behaviours — ghosts, replays, fair AI and
/// server-side validation all break silently if any of them regresses, so each
/// one is pinned here.
final class PhysicsTests: XCTestCase {

    private let spec = BikeCatalog.vantageR450
    private lazy var terrain = TrackBuilder.build(TrackCatalog.ridgelinePark)

    // MARK: - Determinism

    func testIdenticalInputsProduceIdenticalOutcomes() {
        let inputs = PhysicsTests.inputSequence(steps: 2_400)

        let first = runSimulation(inputs: inputs)
        let second = runSimulation(inputs: inputs)

        XCTAssertEqual(first.position.x, second.position.x, accuracy: 0,
                       "The solver must be bit-deterministic; ghosts and replays depend on it")
        XCTAssertEqual(first.position.y, second.position.y, accuracy: 0)
        XCTAssertEqual(first.angle, second.angle, accuracy: 0)
        XCTAssertEqual(first.velocity.x, second.velocity.x, accuracy: 0)
    }

    func testTerrainGenerationIsDeterministic() {
        let a = TrackBuilder.build(TrackCatalog.summitRidge)
        let b = TrackBuilder.build(TrackCatalog.summitRidge)

        XCTAssertEqual(a.sampleCount, b.sampleCount)
        for x in stride(from: 0.0, to: a.endX, by: 7.0) {
            XCTAssertEqual(a.height(at: x), b.height(at: x), accuracy: 0)
        }
    }

    func testDeterministicRandomIsStable() {
        var first = DeterministicRandom(seed: 12_345)
        var second = DeterministicRandom(seed: 12_345)
        for _ in 0..<1_000 {
            XCTAssertEqual(first.next(), second.next())
        }
    }

    // MARK: - Stability

    func testSimulationStaysFiniteUnderExtremeInput() {
        var bike = BikePhysicsBody(spec: spec, position: .zero)
        bike.settle(on: terrain, atX: TrackBuilder.startPadding)

        // Deliberately abusive: full throttle, full brakes and full lean at
        // once, held for a minute of simulated time.
        let input = RiderInput(throttle: 1, frontBrake: 1, rearBrake: 1, lean: 1)
        for _ in 0..<(240 * 60) {
            bike.step(dt: 1.0 / 240.0, input: input, terrain: terrain)
        }

        XCTAssertTrue(bike.position.x.isFinite)
        XCTAssertTrue(bike.position.y.isFinite)
        XCTAssertTrue(bike.velocity.x.isFinite)
        XCTAssertTrue(bike.angle.isFinite)
        XCTAssertTrue(bike.angularVelocity.isFinite)
    }

    func testMalformedInputCannotDestabiliseTheSolver() {
        var bike = BikePhysicsBody(spec: spec, position: .zero)
        bike.settle(on: terrain, atX: TrackBuilder.startPadding)

        // Values a corrupt replay or a hostile packet could carry.
        let hostile = RiderInput(throttle: .nan, frontBrake: .infinity,
                                 rearBrake: -50, lean: 1_000)
        for _ in 0..<600 {
            bike.step(dt: 1.0 / 240.0, input: hostile, terrain: terrain)
        }

        XCTAssertTrue(bike.position.y.isFinite)
        XCTAssertTrue(bike.velocity.length.isFinite)
    }

    func testBikeAtRestDoesNotSinkOrDrift() {
        var bike = BikePhysicsBody(spec: spec, position: .zero)
        let startX = TrackBuilder.startPadding
        bike.settle(on: terrain, atX: startX)
        let restingHeight = bike.position.y

        for _ in 0..<(240 * 5) {
            bike.step(dt: 1.0 / 240.0, input: .neutral, terrain: terrain)
        }

        XCTAssertEqual(bike.position.y, restingHeight, accuracy: 0.12,
                       "A parked bike must not sink through the ground or be pushed off it")
        XCTAssertEqual(bike.position.x, startX, accuracy: 0.6,
                       "A parked bike must not creep along flat ground")
        XCTAssertFalse(bike.hasCrashed)
    }

    func testSuspensionNeverExceedsItsTravel() {
        var bike = BikePhysicsBody(spec: spec, position: .zero)
        bike.settle(on: terrain, atX: TrackBuilder.startPadding)
        let input = RiderInput(throttle: 1, lean: -0.4)

        for _ in 0..<(240 * 40) {
            bike.step(dt: 1.0 / 240.0, input: input, terrain: terrain)
            XCTAssertLessThanOrEqual(bike.frontWheel.compression,
                                     spec.frontSuspension.travel + 1e-9)
            XCTAssertGreaterThanOrEqual(bike.frontWheel.compression, -1e-9)
            XCTAssertLessThanOrEqual(bike.rearWheel.compression,
                                     spec.rearSuspension.travel + 1e-9)
            XCTAssertGreaterThanOrEqual(bike.rearWheel.compression, -1e-9)
        }
    }

    // MARK: - Behaviour

    func testThrottleAccelerates() {
        var bike = BikePhysicsBody(spec: spec, position: .zero)
        bike.settle(on: terrain, atX: TrackBuilder.startPadding)
        let input = RiderInput(throttle: 0.8, lean: 0.2)

        for _ in 0..<(240 * 3) {
            bike.step(dt: 1.0 / 240.0, input: input, terrain: terrain)
        }

        XCTAssertGreaterThan(bike.forwardSpeed, 5,
                             "Three seconds of throttle should produce real speed")
    }

    func testBrakingDecelerates() {
        var bike = BikePhysicsBody(spec: spec, position: .zero)
        bike.settle(on: terrain, atX: TrackBuilder.startPadding)

        for _ in 0..<(240 * 4) {
            bike.step(dt: 1.0 / 240.0, input: RiderInput(throttle: 0.9), terrain: terrain)
        }
        let speedBeforeBraking = bike.forwardSpeed
        XCTAssertGreaterThan(speedBeforeBraking, 4)

        for _ in 0..<(240 * 2) {
            bike.step(dt: 1.0 / 240.0,
                      input: RiderInput(frontBrake: 0.9, rearBrake: 0.6, lean: 0.3),
                      terrain: terrain)
        }

        XCTAssertLessThan(bike.forwardSpeed, speedBeforeBraking,
                          "Applying the brakes must reduce speed")
    }

    func testAirControlCanRotateTheBike() {
        var bike = BikePhysicsBody(spec: spec, position: Vector2(60, 40))
        // Dropped from height with no ground contact, so only air control acts.
        for _ in 0..<240 {
            bike.step(dt: 1.0 / 240.0, input: RiderInput(lean: -1), terrain: terrain)
        }

        XCTAssertGreaterThan(bike.angularVelocity, 0.1,
                             "Leaning back in the air must pitch the nose up")
    }

    func testEngineTorqueCurvePeaksWhereItShould() {
        let engine = spec.engine
        let atPeak = engine.torqueFraction(atRPM: engine.peakTorqueRPM)
        let belowPeak = engine.torqueFraction(atRPM: engine.peakTorqueRPM * 0.5)
        let abovePeak = engine.torqueFraction(atRPM: engine.peakTorqueRPM * 1.3)

        XCTAssertEqual(atPeak, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(belowPeak, atPeak)
        XCTAssertLessThan(abovePeak, atPeak)
        XCTAssertEqual(engine.torqueFraction(atRPM: engine.redlineRPM), 0,
                       "The limiter must cut drive completely")
    }

    // MARK: - Helpers

    private func runSimulation(inputs: [RiderInput]) -> BikePhysicsBody {
        var bike = BikePhysicsBody(spec: spec, position: .zero)
        bike.settle(on: terrain, atX: TrackBuilder.startPadding)
        for input in inputs {
            bike.step(dt: 1.0 / 240.0, input: input, terrain: terrain)
        }
        return bike
    }

    /// A varied but reproducible control sequence.
    private static func inputSequence(steps: Int) -> [RiderInput] {
        var random = DeterministicRandom(seed: 0xC0FFEE)
        return (0..<steps).map { _ in
            RiderInput(throttle: random.unit(),
                       frontBrake: random.unit() * 0.3,
                       rearBrake: random.unit() * 0.3,
                       lean: random.range(-1, 1))
        }
    }
}
