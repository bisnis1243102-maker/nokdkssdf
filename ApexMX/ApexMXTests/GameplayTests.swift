import XCTest
@testable import ApexMX

/// Tests for the rules layer: timing, progression, economy and persistence.
final class GameplayTests: XCTestCase {

    // MARK: - Fixed timestep

    func testFixedTimestepIsFrameRateIndependent() {
        var at60 = FixedTimestepAccumulator(stepsPerSecond: 240)
        var at120 = FixedTimestepAccumulator(stepsPerSecond: 240)

        var stepsAt60 = 0
        var stepsAt120 = 0
        // One second of real time, delivered at two different frame rates.
        for _ in 0..<60 { stepsAt60 += at60.advance(by: 1.0 / 60.0) }
        for _ in 0..<120 { stepsAt120 += at120.advance(by: 1.0 / 120.0) }

        XCTAssertEqual(stepsAt60, stepsAt120,
                       "The same wall-clock time must produce the same number of simulation steps")
        XCTAssertEqual(stepsAt60, 240)
    }

    func testFixedTimestepClampsRunawayFrames() {
        var accumulator = FixedTimestepAccumulator(stepsPerSecond: 240, maxFrameTime: 0.25)
        // A ten-second stall must not queue ten seconds of physics.
        let steps = accumulator.advance(by: 10)
        XCTAssertLessThanOrEqual(steps, 60)
    }

    func testFixedTimestepIgnoresInvalidDeltas() {
        var accumulator = FixedTimestepAccumulator()
        XCTAssertEqual(accumulator.advance(by: -1), 0)
        XCTAssertEqual(accumulator.advance(by: .nan), 0)
        XCTAssertEqual(accumulator.advance(by: 0), 0)
    }

    // MARK: - Race session

    func testRaceStartsWithACountdownAndNobodyMoves() {
        let session = makeSession()
        XCTAssertEqual(session.phase, .countdown(RaceSession.countdownDuration))

        let startX = session.player!.bike.position.x
        session.playerInput = RiderInput(throttle: 1)
        // Advance less than the countdown.
        for _ in 0..<60 { session.update(deltaTime: 1.0 / 60.0) }

        XCTAssertEqual(session.player!.bike.position.x, startX, accuracy: 1e-9,
                       "Nobody may move before the gate drops")
    }

    func testRaceProgressesOnceUnderway() {
        let session = makeSession()
        session.playerInput = RiderInput(throttle: 1, lean: 0.2)
        for _ in 0..<(60 * 8) { session.update(deltaTime: 1.0 / 60.0) }

        XCTAssertEqual(session.phase, .racing)
        XCTAssertGreaterThan(session.player!.totalDistance, 5)
    }

    func testStandingsAreOrderedByProgress() {
        let session = makeSession()
        session.playerInput = RiderInput(throttle: 1, lean: 0.2)
        for _ in 0..<(60 * 10) { session.update(deltaTime: 1.0 / 60.0) }

        let standings = session.standings()
        XCTAssertEqual(standings.count, session.riders.count)
        for (index, standing) in standings.enumerated() {
            XCTAssertEqual(standing.position, index + 1)
            if index > 0 {
                XCTAssertGreaterThanOrEqual(standings[index - 1].distance, standing.distance)
            }
        }
    }

    func testAIRidersUseTheSameSpecAsTheirDeclaredMachine() {
        // The fairness guarantee: opponents get no hidden performance edge.
        let spec = BikeCatalog.scoutFX250
        let session = RaceSession(track: TrackCatalog.ridgelinePark,
                                  playerSpec: spec,
                                  opponents: [("Test", spec, 0.9)],
                                  recordGhost: false)
        for rider in session.riders {
            XCTAssertEqual(rider.bike.spec.engine.peakTorque, spec.engine.peakTorque)
            XCTAssertEqual(rider.bike.spec.tyreGripMultiplier, spec.tyreGripMultiplier)
            XCTAssertEqual(rider.bike.spec.totalMass, spec.totalMass)
        }
    }

    // MARK: - Upgrades and economy

    func testUpgradesImproveTheMachineMonotonically() {
        let base = BikeCatalog.scoutFX250
        var previousTorque = base.engine.peakTorque

        for level in 1...UpgradeCategory.maximumLevel {
            var loadout = UpgradeLoadout()
            loadout.setLevel(level, for: .engine)
            let upgraded = UpgradeSystem.apply(loadout, to: base)
            XCTAssertGreaterThan(upgraded.engine.peakTorque, previousTorque)
            previousTorque = upgraded.engine.peakTorque
        }
    }

    func testUpgradeLevelsAreClamped() {
        var loadout = UpgradeLoadout()
        loadout.setLevel(99, for: .brakes)
        XCTAssertEqual(loadout.level(.brakes), UpgradeCategory.maximumLevel)
        loadout.setLevel(-5, for: .brakes)
        XCTAssertEqual(loadout.level(.brakes), 0)
    }

    func testCannotBuyWhatYouCannotAfford() {
        var profile = PlayerProfile(credits: 10)
        XCTAssertFalse(CareerService.purchaseUpgrade(.engine,
                                                     bikeID: profile.selectedBikeID,
                                                     in: &profile))
        XCTAssertEqual(profile.credits, 10)
        XCTAssertFalse(CareerService.purchaseBike(BikeCatalog.apexPrototype.id, in: &profile))
        XCTAssertFalse(profile.owns(BikeCatalog.apexPrototype.id))
    }

    func testPurchaseDeductsExactlyTheAdvertisedPrice() {
        var profile = PlayerProfile(credits: 100_000)
        let loadout = profile.loadout(for: profile.selectedBikeID)
        let cost = loadout.upgradeCost(for: .suspension)!

        XCTAssertTrue(CareerService.purchaseUpgrade(.suspension,
                                                    bikeID: profile.selectedBikeID,
                                                    in: &profile))
        XCTAssertEqual(profile.credits, 100_000 - cost)
        XCTAssertEqual(profile.loadout(for: profile.selectedBikeID).level(.suspension), 1)
    }

    func testWinningPaysMoreThanLosing() {
        var winner = PlayerProfile()
        var loser = PlayerProfile()
        let track = TrackCatalog.ridgelinePark

        let first = RaceResult(id: 0, name: "You", isPlayer: true, position: 1,
                               totalTime: 80, bestLap: 40, crashes: 0,
                               cleanLandings: 10, bestAirTime: 1.4)
        let last = RaceResult(id: 0, name: "You", isPlayer: true, position: 6,
                              totalTime: 110, bestLap: 55, crashes: 3,
                              cleanLandings: 2, bestAirTime: 0.8)

        let winReward = CareerService.applyResult(first, track: track, fieldSize: 6, to: &winner)
        let lossReward = CareerService.applyResult(last, track: track, fieldSize: 6, to: &loser)

        XCTAssertGreaterThan(winReward.totalCredits, lossReward.totalCredits)
        XCTAssertEqual(winner.statistics.racesWon, 1)
        XCTAssertEqual(loser.statistics.racesWon, 0)
    }

    func testTracksUnlockOnMedalPoints() {
        var profile = PlayerProfile()
        XCTAssertFalse(profile.hasUnlocked(TrackCatalog.copperFlats.id))

        // A gold on the opening track is worth three points; Copper Flats needs two.
        profile.records[TrackCatalog.ridgelinePark.id] = TrackRecord(
            trackID: TrackCatalog.ridgelinePark.id,
            bestLapTime: TrackCatalog.ridgelinePark.goldLapTime - 1,
            bestTotalTime: 80,
            bestPosition: 1,
            timesRaced: 1,
            bikeID: BikeCatalog.scoutFX250.id
        )
        CareerService.unlockEligibleTracks(in: &profile)

        XCTAssertTrue(profile.hasUnlocked(TrackCatalog.copperFlats.id))
        XCTAssertFalse(profile.hasUnlocked(TrackCatalog.summitRidge.id))
    }

    // MARK: - Ghosts

    func testGhostReplayReproducesTheOriginalRun() {
        let track = TrackCatalog.ridgelinePark
        let terrain = TrackBuilder.build(track)
        let spec = BikeCatalog.scoutFX250

        // Record a run.
        let recorder = GhostRecorder(trackID: track.id, bikeID: spec.id)
        var original = BikePhysicsBody(spec: spec, position: .zero)
        original.settle(on: terrain, atX: TrackBuilder.startPadding)

        var random = DeterministicRandom(seed: 4_242)
        let dt = 1.0 / 240.0
        var time: Double = 0
        for _ in 0..<2_000 {
            let input = RiderInput(throttle: random.unit(),
                                   rearBrake: random.unit() * 0.2,
                                   lean: random.range(-0.6, 0.6))
            recorder.record(input: input, at: time)
            original.step(dt: dt, input: input, terrain: terrain)
            time += dt
        }
        recorder.finalise(totalTime: time)

        // Replay it.
        let run = recorder.completedRun!
        let player = GhostPlayer(run: run, spec: spec, terrain: terrain,
                                 startX: TrackBuilder.startPadding)!
        for _ in 0..<2_000 {
            player.step(dt: dt, terrain: terrain)
        }

        // Keyframe quantisation means the replay is close, not bit-exact — but
        // it must stay on the same part of the track, not diverge.
        XCTAssertEqual(player.bike.position.x, original.position.x, accuracy: 6.0,
                       "A replayed ghost must follow the run it recorded")
    }

    func testGhostFromAnIncompatiblePhysicsVersionIsRejected() {
        let run = GhostRun(trackID: "t", bikeID: "b", totalTime: 60,
                           recordedAt: Date(), keyframes: [],
                           physicsVersion: GhostRun.currentPhysicsVersion - 1)
        XCTAssertFalse(run.isReplayable)

        let terrain = TrackBuilder.build(TrackCatalog.ridgelinePark)
        XCTAssertNil(GhostPlayer(run: run, spec: BikeCatalog.scoutFX250,
                                 terrain: terrain, startX: 0))
    }

    // MARK: - Persistence

    func testProfileSurvivesAnEncodeDecodeRound() throws {
        var profile = PlayerProfile(displayName: "Tester", credits: 4_321)
        profile.settings.hudScale = 1.15
        profile.settings.colorblindMode = .deuteranopia
        var loadout = UpgradeLoadout()
        loadout.setLevel(3, for: .tyres)
        profile.loadouts[profile.selectedBikeID] = loadout

        let data = try JSONEncoder().encode(profile)
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: data)

        XCTAssertEqual(restored.displayName, "Tester")
        XCTAssertEqual(restored.credits, 4_321)
        XCTAssertEqual(restored.settings.hudScale, 1.15)
        XCTAssertEqual(restored.settings.colorblindMode, .deuteranopia)
        XCTAssertEqual(restored.loadout(for: restored.selectedBikeID).level(.tyres), 3)
    }

    // MARK: - Terrain

    func testTerrainHeightIsContinuous() {
        let terrain = TrackBuilder.build(TrackCatalog.ironworks)
        var previous = terrain.height(at: terrain.originX)
        var x = terrain.originX
        while x < terrain.endX {
            let height = terrain.height(at: x)
            XCTAssertLessThan(abs(height - previous), 0.6,
                              "A step in the ground would spike the suspension")
            previous = height
            x += Terrain.sampleSpacing
        }
    }

    func testTerrainQueriesOutsideTheTrackAreClamped() {
        let terrain = TrackBuilder.build(TrackCatalog.ridgelinePark)
        XCTAssertTrue(terrain.height(at: -10_000).isFinite)
        XCTAssertTrue(terrain.height(at: 10_000).isFinite)
        XCTAssertTrue(terrain.gradient(at: -10_000).isFinite)
    }

    func testLapWrapPreservesMomentum() {
        var bike = BikePhysicsBody(spec: BikeCatalog.scoutFX450Fallback, position: Vector2(100, 5))
        let velocity = Vector2(18, -2)
        bike.applyStartImpulse(velocity * bike.mass)
        let before = bike.velocity
        let angleBefore = bike.angle

        bike.translate(by: Vector2(-500, 0))

        XCTAssertEqual(bike.velocity.x, before.x, accuracy: 0)
        XCTAssertEqual(bike.velocity.y, before.y, accuracy: 0)
        XCTAssertEqual(bike.angle, angleBefore, accuracy: 0)
        XCTAssertEqual(bike.position.x, -400, accuracy: 1e-9)
    }

    // MARK: - Helpers

    private func makeSession() -> RaceSession {
        RaceSession(track: TrackCatalog.ridgelinePark,
                    playerSpec: BikeCatalog.scoutFX250,
                    opponents: CareerService.buildField(for: TrackCatalog.ridgelinePark,
                                                        playerLevel: 1,
                                                        size: 3),
                    recordGhost: false)
    }
}

private extension BikeCatalog {
    /// Alias used by a test that only needs *some* valid machine, making the
    /// test's intent — "any bike" — explicit at the call site.
    static var scoutFX450Fallback: BikeSpec { vantageR450 }
}
