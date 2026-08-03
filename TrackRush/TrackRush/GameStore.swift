import Foundation

/// One frame of a recorded run. Small on purpose — a two-minute run at 30 Hz
/// is only a few thousand of these.
struct GhostSample: Codable {
    let t: Double
    let x: Double
    let y: Double
    let r: Double
}

enum Medal: Int, Comparable {
    case none = 0, bronze, silver, gold

    static func < (lhs: Medal, rhs: Medal) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .none: return "No medal"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }
}

/// Best times, medals, unlock progress, and the ghost of your best run.
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

    func medal(for track: Track) -> Medal {
        guard let time = bestTimes[track.id] else { return .none }
        return track.medal(for: time)
    }

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

    // MARK: - Ghosts

    /// Recorded runs are a few hundred kilobytes each, so they live as files
    /// rather than bloating UserDefaults.
    private func ghostURL(for track: Track) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ghost-\(track.id).json")
    }

    func ghost(for track: Track) -> [GhostSample] {
        guard let data = try? Data(contentsOf: ghostURL(for: track)),
              let samples = try? JSONDecoder().decode([GhostSample].self, from: data) else { return [] }
        return samples
    }

    func saveGhost(_ samples: [GhostSample], for track: Track) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: ghostURL(for: track), options: .atomic)
    }
}
