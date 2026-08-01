import UIKit
import SceneKit

/// Drives the campaign: starting missions, evaluating the current objective
/// every frame, and placing the markers the player actually steers by.
extension GameSceneView.Coordinator {

    // MARK: Current state helpers

    func currentObjective() -> Objective? {
        guard let m = runningMission else { return nil }
        guard objectiveIdx < m.objectives.count else { return nil }
        return m.objectives[objectiveIdx]
    }

    /// Where the HUD arrow and the world ring should point.
    func currentWaypoint() -> SIMD2<Float>? {
        guard let obj = currentObjective() else {
            // No mission running: point at the next mission's start marker.
            if let id = offeredMissionID(), let m = Campaign.mission(id) {
                return CityWorld.point(m.startPlace)
            }
            return nil
        }
        switch obj {
        case .tail, .ram:
            if let t = missionTarget { return SIMD2<Float>(t.x, t.z) }
            return obj.place.map { CityWorld.point($0) }
        case .loseCops:
            return nil
        default:
            return obj.place.map { CityWorld.point($0) }
        }
    }

    /// The mission on offer in free roam — the first one not yet completed.
    func offeredMissionID() -> Int? {
        guard runningMission == nil else { return nil }
        return Campaign.missions.first { !model.missionsCompleted.contains($0.id) }?.id
    }

    // MARK: Starting

    func startMission(_ m: Mission) {
        runningMission = m
        // The simulation runs on the render thread; every `@Published` write
        // has to hop to main or SwiftUI will complain (and eventually crash).
        DispatchQueue.main.async { [weak self] in
            self?.model.beginMission(m)
        }
        beginObjective(index: 0, in: m)
    }

    private func beginObjective(index: Int, in m: Mission) {
        guard index < m.objectives.count else {
            endMission(m, success: true, reason: "Job done")
            return
        }
        let obj = m.objectives[index]
        objectiveIdx = index
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.objectiveIndex = index
            self.model.objectiveText = obj.hint
        }
        objectiveTime = obj.timeLimit ?? 0
        waitProgress = 0

        // Objectives that need a car to chase get one spawned near their place.
        switch obj {
        case .tail(let place, _, _), .ram(let place, _):
            spawnMissionTarget(near: place)
        default:
            removeMissionTarget()
        }

        if obj.raisesHeat > 0 {
            raiseHeat(to: obj.raisesHeat)
        }
    }

    private func advanceObjective() {
        guard let m = runningMission else { return }
        let next = objectiveIdx + 1
        if next >= m.objectives.count {
            endMission(m, success: true, reason: "Job done")
        } else {
            beginObjective(index: next, in: m)
        }
    }

    func endMission(_ m: Mission, success: Bool, reason: String) {
        runningMission = nil
        removeMissionTarget()
        if !success {
            // Failing doesn't leave you with a permanent tail.
            heat = 0
            clearCops()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if success {
                self.model.completeMission(m)
            } else {
                self.model.failMission(m, reason: reason)
            }
        }
    }

    /// Caught by the police: fail the mission if one is running, otherwise just
    /// clear the heat and let the player carry on.
    func onBusted() {
        heat = 0
        clearCops()
        carSpeed = 0
        if let m = runningMission {
            endMission(m, success: false, reason: "Busted")
        }
    }

    // MARK: Per-frame evaluation

    func updateMission(dt: Float) {
        let px = mode == .driving ? carX : footX
        let pz = mode == .driving ? carZ : footZ

        // Free roam: driving into the start pillar begins the next mission.
        guard let m = runningMission, let obj = currentObjective() else {
            if let id = offeredMissionID(), let next = Campaign.mission(id) {
                let p = CityWorld.point(next.startPlace)
                if hypotf(p.x - px, p.y - pz) < 6 && model.result == nil {
                    startMission(next)
                }
            }
            return
        }

        // Countdown, where the objective has one.
        if obj.timeLimit != nil {
            switch obj {
            case .goToTimed:
                objectiveTime -= Double(dt)
                if objectiveTime <= 0 {
                    endMission(m, success: false, reason: "Out of time")
                    return
                }
            default:
                break
            }
        }

        switch obj {
        case .goTo(let place, _):
            let p = CityWorld.point(place)
            if hypotf(p.x - px, p.y - pz) < 8 { advanceObjective() }

        case .goToTimed(let place, _, _):
            let p = CityWorld.point(place)
            if hypotf(p.x - px, p.y - pz) < 8 { advanceObjective() }

        case .onFootTo(let place, _):
            let p = CityWorld.point(place)
            // Deliberately only satisfiable on foot — this is the "get out" beat.
            if mode == .onFoot && hypotf(p.x - px, p.y - pz) < 5 { advanceObjective() }

        case .waitAt(let place, let seconds, _):
            let p = CityWorld.point(place)
            if hypotf(p.x - px, p.y - pz) < 10 {
                waitProgress += Double(dt)
                objectiveTime = max(0, seconds - waitProgress)
                if waitProgress >= seconds { advanceObjective() }
            } else {
                // Leaving the marker resets the clock rather than failing you.
                waitProgress = 0
                objectiveTime = seconds
            }

        case .tail(_, let seconds, _):
            guard let d = distanceToTarget() else {
                endMission(m, success: false, reason: "Lost the courier")
                return
            }
            if d > 75 {
                endMission(m, success: false, reason: "Lost the courier")
                return
            }
            if d < 3.0 {
                endMission(m, success: false, reason: "You spooked them")
                return
            }
            if d < 45 {
                waitProgress += Double(dt)
                objectiveTime = max(0, seconds - waitProgress)
                if waitProgress >= seconds { advanceObjective() }
            }

        case .ram:
            guard let d = distanceToTarget() else {
                endMission(m, success: false, reason: "Target gone")
                return
            }
            if d < 4.0 && abs(carSpeed) > 12 {
                if let t = missionTarget {
                    spawnSparks(at: SCNVector3(t.x, 0.7, t.z))
                }
                removeMissionTarget()
                advanceObjective()
            }

        case .loseCops:
            if heat == 0 { advanceObjective() }
        }
    }

    // MARK: Markers

    func updateMarkers() {
        // Objective ring.
        if let wp = currentWaypoint(), runningMission != nil {
            waypointNode.isHidden = false
            waypointNode.position = SCNVector3(wp.x, 1.6, wp.y)
        } else {
            waypointNode.isHidden = true
        }

        // Mission start pillar, only while free roaming.
        if let id = offeredMissionID(), let m = Campaign.mission(id) {
            let p = CityWorld.point(m.startPlace)
            startMarkerNode.isHidden = false
            startMarkerNode.position = SCNVector3(p.x, 3.5, p.y)
        } else {
            startMarkerNode.isHidden = true
        }
    }
}
