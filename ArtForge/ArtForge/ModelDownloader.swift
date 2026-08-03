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

    /// One model, chosen rather than offered as a menu: 6-bit palettized and
    /// compiled for the Neural Engine, which is the best balance of speed,
    /// quality, and memory on a phone.
    static let standard = ModelOption(
        id: "sd21-base-palettized",
        title: "Stable Diffusion 2.1 base",
        detail: "6-bit palettized, tuned for the Neural Engine.",
        approximateBytes: 1_140_000_000,
        url: URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-2-1-base-palettized/resolve/main/coreml-stable-diffusion-2-1-base-palettized_split_einsum_v2_compiled.zip")!
    )
}

/// Downloads a model zip straight to the phone and unpacks it into place, so
/// no computer is needed anywhere in the process.
///
/// A background `URLSession` does the transfer, which means it keeps running
/// when the app is backgrounded or the screen locks — a gigabyte takes long
/// enough that requiring the app stay open in the foreground was the single
/// biggest thing making installation feel slow.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {

    /// One instance for the whole app: a background session is tied to its
    /// identifier, and creating a second with the same one traps.
    static let shared = ModelDownloader()

    enum Phase: Equatable {
        case idle
        case waitingForNetwork
        case downloading(received: Int64, total: Int64)
        case unpacking(fraction: Double)
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Bytes per second, smoothed. Nil until there is enough to measure.
    @Published private(set) var speed: Double?
    /// Set when a download is interrupted and can be picked up where it left off.
    @Published private(set) var canResume = false

    /// Cellular is allowed only if the user opts in — this is over a gigabyte.
    @Published var allowCellular = false

    private var resumeData: Data?
    private var task: URLSessionDownloadTask?
    private var lastSampleTime: Date?
    private var lastSampleBytes: Int64 = 0

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.example.ArtForge.modelDownload")
        // Discretionary lets iOS defer the transfer to "a good time", which can
        // mean not starting for ages. The user just tapped a button; go now.
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true   // gated per request instead
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        // A transfer may have kept running while the app was away; adopt it.
        Task { await adoptExistingTask() }
    }

    private func adoptExistingTask() async {
        let tasks = await session.tasks.2
        if let existing = tasks.first {
            task = existing
            phase = .downloading(received: existing.countOfBytesReceived,
                                 total: max(existing.countOfBytesExpectedToReceive,
                                            ModelOption.standard.approximateBytes))
        }
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .unpacking, .waitingForNetwork: return true
        default: return false
        }
    }

    /// Human-readable one-liner for the UI.
    var statusText: String {
        switch phase {
        case .idle:
            return ""
        case .waitingForNetwork:
            return allowCellular ? "Waiting for a connection…" : "Waiting for Wi-Fi…"
        case .downloading(let received, let total):
            let got = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
            guard total > 0 else { return "Downloading \(got)…" }
            let all = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            var text = "\(got) of \(all)"
            if let speed, speed > 0 {
                let rate = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
                text += " · \(rate)/s"
                let remaining = Double(total - received) / speed
                if remaining.isFinite, remaining > 0, remaining < 60 * 60 * 6 {
                    text += " · \(Self.timeText(remaining)) left"
                }
            }
            return text
        case .unpacking(let fraction):
            return fraction > 0 ? "Unpacking \(Int(fraction * 100))%" : "Unpacking…"
        case .finished:
            return "Installed"
        case .failed(let message):
            return message
        }
    }

    private static func timeText(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%.1f hr", seconds / 3600)
    }

    var fraction: Double? {
        switch phase {
        case .downloading(let received, let total) where total > 0:
            return Double(received) / Double(total)
        case .unpacking(let fraction) where fraction > 0:
            return fraction
        default:
            return nil
        }
    }

    // MARK: - Control

    func start(_ option: ModelOption) {
        guard !isBusy else { return }

        // A model needs room for the zip and the unpacked copy at once.
        if let free = Self.availableBytes(), free < option.approximateBytes * 5 / 2 {
            let needed = ByteCountFormatter.string(fromByteCount: option.approximateBytes * 5 / 2, countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            phase = .failed("Not enough space. Need about \(needed) free while installing, you have \(have).")
            return
        }

        speed = nil
        lastSampleTime = nil
        lastSampleBytes = 0
        phase = .downloading(received: 0, total: option.approximateBytes)

        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            var request = URLRequest(url: option.url)
            request.allowsCellularAccess = allowCellular
            task = session.downloadTask(with: request)
        }
        task.countOfBytesClientExpectsToReceive = option.approximateBytes
        self.task = task
        canResume = false
        task.resume()
    }

    /// Stops but keeps what has been fetched, so Resume picks up mid-file.
    func pause() {
        task?.cancel { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.resumeData = data
                self.canResume = data != nil
                self.task = nil
                self.phase = .idle
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        resumeData = nil
        canResume = false
        speed = nil
        phase = .idle
    }

    private static func availableBytes() -> Int64? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    fileprivate func record(received: Int64, total: Int64) {
        let now = Date()
        if let last = lastSampleTime {
            let elapsed = now.timeIntervalSince(last)
            if elapsed > 0.5 {
                let sample = Double(received - lastSampleBytes) / elapsed
                // Exponential smoothing; raw samples jump around too much to read.
                speed = speed.map { $0 * 0.7 + sample * 0.3 } ?? sample
                lastSampleTime = now
                lastSampleBytes = received
            }
        } else {
            lastSampleTime = now
            lastSampleBytes = received
        }
        phase = .downloading(received: received, total: total)
    }

    // MARK: - Unpacking

    fileprivate func finish(downloadedTo temporaryURL: URL) {
        phase = .unpacking(fraction: 0)
        canResume = false
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-unpack-\(UUID().uuidString)", isDirectory: true)
        let progress = Progress(totalUnitCount: 1)

        // Poll the unzip's progress so the UI has something honest to show
        // during the slowest part of the install.
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if case .unpacking = self.phase {
                    self.phase = .unpacking(fraction: progress.fractionCompleted)
                } else {
                    return
                }
            }
        }

        Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)

                let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
                try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
                // skipCRC32 avoids a second full pass over a gigabyte of data
                // that HTTPS has already checksummed in transit.
                try fm.unzipItem(at: temporaryURL, to: unpacked,
                                 skipCRC32: true, progress: progress)
                try? fm.removeItem(at: temporaryURL)

                guard let root = Self.findModelRoot(in: unpacked) else {
                    throw NSError(domain: "ArtForge", code: 10, userInfo: [
                        NSLocalizedDescriptionKey: "The download unpacked, but no Unet.mlmodelc was found inside it."
                    ])
                }

                let destination = DiffusionEngine.modelDirectory
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                // Same volume, so this is a rename rather than a gigabyte copy.
                try fm.moveItem(at: root, to: destination)

                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutable = destination
                try? mutable.setResourceValues(values)

                try? fm.removeItem(at: staging)

                await MainActor.run {
                    ticker.cancel()
                    self.phase = .finished
                }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                try? FileManager.default.removeItem(at: temporaryURL)
                await MainActor.run {
                    ticker.cancel()
                    self.phase = .failed(error.localizedDescription)
                }
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
            self.record(received: totalBytesWritten,
                        total: totalBytesExpectedToWrite > 0
                            ? totalBytesExpectedToWrite
                            : ModelOption.standard.approximateBytes)
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

    nonisolated func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        Task { @MainActor in
            if case .downloading(let received, _) = self.phase, received == 0 {
                self.phase = .waitingForNetwork
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        let cancelled = nsError.code == NSURLErrorCancelled
        let resume = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            if let resume {
                self.resumeData = resume
                self.canResume = true
            }
            guard !cancelled else { return }
            switch self.phase {
            case .downloading, .waitingForNetwork:
                self.phase = .failed(error.localizedDescription)
            default:
                break
            }
        }
    }
}
