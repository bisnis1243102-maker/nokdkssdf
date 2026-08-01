import Foundation
import UIKit
import os
import os.log

/// On-device instrumentation.
///
/// There is no debugger attached to a sideloaded build and no way for me to run
/// this app, so it has to report on itself: what it is using, how close it is to
/// being killed, and — if it dies during launch — how far it got.
enum Diagnostics {

    // MARK: Memory

    /// The app's physical footprint in bytes. This is the figure iOS actually
    /// judges for jetsam; `resident_size` is not.
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    /// Bytes remaining before iOS kills the app. When this gets small, the next
    /// crash is a memory crash.
    static func availableBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    static var footprintMB: Double { Double(footprintBytes()) / 1_000_000 }
    static var availableMB: Double { Double(availableBytes()) / 1_000_000 }

    // MARK: Launch breadcrumbs
    //
    // A blank screen followed by a kill tells us nothing on its own. Stamping
    // the launch stage means the *next* launch can show where the last one
    // stopped, which is the closest thing to a debugger we can get onto a
    // sideloaded phone.

    enum Stage: String {
        case started        = "started"
        case buildingCity   = "buildingCity"
        case sceneReady     = "sceneReady"
        case firstFrame     = "firstFrame"

        var readable: String {
            switch self {
            case .started:      return "app start"
            case .buildingCity: return "building the city"
            case .sceneReady:   return "scene built, first frame pending"
            case .firstFrame:   return "running"
            }
        }
    }

    private static let stageKey = "neonreign.launchStage"
    private static let lastFailedKey = "neonreign.lastFailedStage"

    /// Records how far this launch has got.
    static func stamp(_ stage: Stage) {
        let d = UserDefaults.standard
        d.set(stage.rawValue, forKey: stageKey)
        if stage == .firstFrame {
            // Reached a live frame: this launch is a success, so clear the
            // in-progress marker rather than leaving it to look like a failure.
            d.removeObject(forKey: stageKey)
        }
        os_log("NeonReign stage: %{public}@", log: .default, type: .info, stage.rawValue)
    }

    /// Called once at startup, before anything heavy runs.
    ///
    /// - Returns: the stage the *previous* launch died at, or nil if the last
    ///   run reached a frame (or this is the first ever launch).
    static func consumePreviousFailure() -> Stage? {
        let d = UserDefaults.standard
        defer { d.removeObject(forKey: lastFailedKey) }

        // A stage marker still sitting there means the last run never reached
        // `firstFrame` — it was killed mid-launch.
        guard let raw = d.string(forKey: stageKey), let stage = Stage(rawValue: raw) else {
            return nil
        }
        d.set(raw, forKey: lastFailedKey)
        d.removeObject(forKey: stageKey)
        return stage
    }

    // MARK: Frame rate

    /// Rolling frame-rate estimate, fed from the scene's per-frame tick.
    final class FrameCounter {
        private var frames = 0
        private var elapsed: Double = 0
        private(set) var fps: Double = 0

        func tick(dt: Double) {
            frames += 1
            elapsed += dt
            if elapsed >= 0.5 {
                fps = Double(frames) / elapsed
                frames = 0
                elapsed = 0
            }
        }
    }
}
