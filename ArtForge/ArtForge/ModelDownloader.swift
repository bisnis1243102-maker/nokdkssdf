import Foundation
import ZIPFoundation

/// A model the app knows how to fetch. These are Apple's own Core ML
/// conversions, published as public zips — no account, token, or API involved,
/// just a file download over HTTPS.
struct ModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let approximateBytes: Int64
    let url: URL

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }

    static let catalog: [ModelOption] = [
        ModelOption(
            id: "sd21-base-palettized",
            title: "Stable Diffusion 2.1 base",
            detail: "6-bit palettized, tuned for the Neural Engine. Best balance of speed, quality, and memory.",
            approximateBytes: 1_140_000_000,
            url: URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-2-1-base-palettized/resolve/main/coreml-stable-diffusion-2-1-base-palettized_split_einsum_v2_compiled.zip")!
        ),
        ModelOption(
            id: "sd15-palettized",
            title: "Stable Diffusion 1.5",
            detail: "6-bit palettized. Older model, often better at people and illustration styles.",
            approximateBytes: 1_570_000_000,
            url: URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip")!
        )
    ]
}

/// Downloads a model zip straight to the phone and unpacks it into place, so
/// no computer is needed anywhere in the process.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case unpacking
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    var isBusy: Bool {
        switch phase {
        case .downloading, .unpacking: return true
        default: return false
        }
    }

    /// Human-readable one-liner for the UI.
    var statusText: String {
        switch phase {
        case .idle: return ""
        case .downloading(let received, let total):
            let got = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
            guard total > 0 else { return "Downloading \(got)…" }
            let all = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "Downloading \(got) of \(all)"
        case .unpacking: return "Unpacking — this takes a minute…"
        case .finished: return "Installed"
        case .failed(let message): return message
        }
    }

    var fraction: Double? {
        if case .downloading(let received, let total) = phase, total > 0 {
            return Double(received) / Double(total)
        }
        return nil
    }

    func start(_ option: ModelOption) {
        guard !isBusy else { return }

        // A model needs room for the zip and the unpacked copy at the same time.
        if let free = Self.availableBytes(), free < option.approximateBytes * 5 / 2 {
            let needed = ByteCountFormatter.string(fromByteCount: option.approximateBytes * 5 / 2, countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            phase = .failed("Not enough space. Need about \(needed) free while installing, you have \(have).")
            return
        }

        phase = .downloading(received: 0, total: option.approximateBytes)

        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = false      // this is a gigabyte-plus
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 60 * 60

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: option.url)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        phase = .idle
    }

    private static func availableBytes() -> Int64? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    fileprivate func finish(downloadedTo temporaryURL: URL) {
        phase = .unpacking
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-unpack-\(UUID().uuidString)", isDirectory: true)

        Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)

                let archive = staging.appendingPathComponent("model.zip")
                try fm.moveItem(at: temporaryURL, to: archive)

                let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
                try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
                try fm.unzipItem(at: archive, to: unpacked)
                // The zip is a big chunk of disk; drop it before copying.
                try? fm.removeItem(at: archive)

                guard let root = Self.findModelRoot(in: unpacked) else {
                    throw NSError(domain: "ArtForge", code: 10, userInfo: [
                        NSLocalizedDescriptionKey: "The download unpacked, but no Unet.mlmodelc was found inside it."
                    ])
                }

                let destination = DiffusionEngine.modelDirectory
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.moveItem(at: root, to: destination)

                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutable = destination
                try? mutable.setResourceValues(values)

                try? fm.removeItem(at: staging)

                await MainActor.run { self.phase = .finished }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// Zips from Hugging Face wrap the model in one or two folders, and the
    /// depth differs between repos — so look for the Unet rather than assume.
    nonisolated private static func findModelRoot(in directory: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.appendingPathComponent("Unet.mlmodelc").path) {
            return directory
        }
        guard let items = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for item in items {
            // Don't descend into compiled model packages; they are directories too.
            guard !item.lastPathComponent.hasSuffix(".mlmodelc") else { continue }
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            if let found = findModelRoot(in: item) { return found }
        }
        return nil
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            self.phase = .downloading(received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // The temp file is deleted the moment this returns, so move it now,
        // synchronously, before hopping to the main actor.
        let holding = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-download-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: holding)
        } catch {
            Task { @MainActor in self.phase = .failed(error.localizedDescription) }
            return
        }
        Task { @MainActor in self.finish(downloadedTo: holding) }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        Task { @MainActor in
            if !cancelled, case .downloading = self.phase {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }
}
