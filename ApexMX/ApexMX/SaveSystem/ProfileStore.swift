import Foundation

/// Persists the player profile to disk.
///
/// Writes are atomic and go through a temporary file, so a crash or a kill
/// mid-write leaves the previous save intact rather than a truncated one. A
/// save that fails to decode is preserved on disk under a `.corrupt` name for
/// diagnosis instead of being silently overwritten.
public final class ProfileStore: @unchecked Sendable {

    public enum StoreError: Error, LocalizedError {
        case encodingFailed(Error)
        case writeFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed(let error): return "Could not encode profile: \(error.localizedDescription)"
            case .writeFailed(let error): return "Could not write profile: \(error.localizedDescription)"
            }
        }
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.apexmx.profilestore", qos: .utility)

    public init(filename: String = "profile.json",
                directory: FileManager.SearchPathDirectory = .applicationSupportDirectory) {
        let manager = FileManager.default
        let base = (try? manager.url(for: directory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)) ?? manager.temporaryDirectory
        let folder = base.appendingPathComponent("ApexMX", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileURL = folder.appendingPathComponent(filename)
    }

    /// Loads the saved profile, or returns a fresh one for a new player.
    public func load() -> PlayerProfile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PlayerProfile()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var profile = try decoder.decode(PlayerProfile.self, from: data)
            profile = migrate(profile)
            return profile
        } catch {
            quarantineCorruptSave()
            return PlayerProfile()
        }
    }

    /// Saves asynchronously. Gameplay never blocks on disk I/O.
    public func save(_ profile: PlayerProfile) {
        queue.async { [fileURL] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(profile)
                // `.atomic` writes to a temporary file and renames, so the save
                // on disk is always either the old one or the new one.
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                Log.error("Failed to save profile: \(error.localizedDescription)", category: .save)
            }
        }
    }

    /// Saves and waits. Used when the app is heading to the background and the
    /// process may not survive long enough for an async write.
    public func saveSynchronously(_ profile: PlayerProfile) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: [.atomic])
        } catch let error as EncodingError {
            throw StoreError.encodingFailed(error)
        } catch {
            throw StoreError.writeFailed(error)
        }
    }

    /// Applies forward migrations for older save formats.
    private func migrate(_ profile: PlayerProfile) -> PlayerProfile {
        var migrated = profile
        // Version 1 is the first shipping format; future versions add their
        // migration steps here, each guarded on the stored version.
        if migrated.version < PlayerProfile.currentVersion {
            migrated.version = PlayerProfile.currentVersion
        }
        // Repair invariants that a bad write or a hand-edited file could break.
        if !migrated.ownedBikeIDs.contains(migrated.selectedBikeID) {
            migrated.selectedBikeID = migrated.ownedBikeIDs.first ?? BikeCatalog.scoutFX250.id
        }
        if migrated.ownedBikeIDs.isEmpty {
            migrated.ownedBikeIDs = [BikeCatalog.scoutFX250.id]
            migrated.selectedBikeID = BikeCatalog.scoutFX250.id
        }
        if migrated.unlockedTrackIDs.isEmpty {
            migrated.unlockedTrackIDs = [TrackCatalog.ridgelinePark.id]
        }
        return migrated
    }

    private func quarantineCorruptSave() {
        let destination = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: fileURL, to: destination)
        Log.error("Profile was unreadable and has been quarantined", category: .save)
    }
}

/// Persists ghost runs, one file per track/bike combination.
public final class GhostStore: @unchecked Sendable {

    private let folderURL: URL

    public init() {
        let manager = FileManager.default
        let base = (try? manager.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)) ?? manager.temporaryDirectory
        folderURL = base.appendingPathComponent("ApexMX/Ghosts", isDirectory: true)
        try? manager.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    private func url(forTrack trackID: String) -> URL {
        folderURL.appendingPathComponent("\(trackID).ghost.json")
    }

    /// Stores the run only if it beats what is already saved for that track.
    @discardableResult
    public func storeIfFaster(_ run: GhostRun) -> Bool {
        if let existing = bestRun(forTrack: run.trackID), existing.totalTime <= run.totalTime {
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(run)
            try data.write(to: url(forTrack: run.trackID), options: [.atomic])
            return true
        } catch {
            Log.error("Failed to store ghost: \(error.localizedDescription)", category: .save)
            return false
        }
    }

    public func bestRun(forTrack trackID: String) -> GhostRun? {
        let location = url(forTrack: trackID)
        guard let data = try? Data(contentsOf: location) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let run = try? decoder.decode(GhostRun.self, from: data) else { return nil }
        // A ghost recorded against different physics cannot be trusted to
        // reproduce, so it is discarded rather than replayed wrongly.
        guard run.isReplayable else {
            try? FileManager.default.removeItem(at: location)
            return nil
        }
        return run
    }

    public func deleteRun(forTrack trackID: String) {
        try? FileManager.default.removeItem(at: url(forTrack: trackID))
    }
}
