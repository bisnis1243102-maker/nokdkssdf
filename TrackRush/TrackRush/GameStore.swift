import Foundation

/// Best times and unlock progress. Small enough that UserDefaults is the right
/// tool — there is nothing here worth a database.
final class GameStore: ObservableObject {
    @Published private(set) var bestTimes: [Int: TimeInterval] = [:]

    private let key = "bestTimes"

    init() {
        if let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] {
            for (id, time) in raw {
                if let track = Int(id) { bestTimes[track] = time }
            }
        }
    }

    func best(for track: Track) -> TimeInterval? { bestTimes[track.id] }

    /// Returns true when the run beat the stored time (or was the first).
    @discardableResult
    func record(time: TimeInterval, for track: Track) -> Bool {
        let previous = bestTimes[track.id]
        guard previous == nil || time < previous! else { return false }
        bestTimes[track.id] = time
        persist()
        return true
    }

    /// A track opens once the one before it has been finished.
    func isUnlocked(_ track: Track) -> Bool {
        track.id == 0 || bestTimes[track.id - 1] != nil
    }

    private func persist() {
        var raw: [String: Double] = [:]
        for (id, time) in bestTimes { raw[String(id)] = time }
        UserDefaults.standard.set(raw, forKey: key)
    }

    static func timeText(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        return minutes > 0
            ? String(format: "%d:%05.2f", minutes, seconds)
            : String(format: "%.2fs", seconds)
    }
}
