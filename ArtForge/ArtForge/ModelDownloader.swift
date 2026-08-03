import Foundation
import UIKit
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
/// The bytes are streamed into a file this app owns, rather than using a
/// download task. A download task hands back a file staged in the URL session
/// daemon's own directory, and a re-signed sideloaded build has no permission
/// to read — let alone delete — anything in there, which fails the install at
/// the very last step. Writing our own file sidesteps that completely and
/// makes resuming a matter of an HTTP range request.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {

    /// One instance for the whole app so a download survives leaving the tab.
    static let shared = ModelDownloader()

    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case unpacking(fraction: Double)
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Bytes per second, smoothed. Nil until there is enough to measure.
    @Published private(set) var speed: Double?
    /// True when a partial file is on disk and the server can resume it.
    @Published private(set) var canResume = false

    /// Cellular is allowed only if the user opts in — this is over a gigabyte.
    @Published var allowCellular = false

    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var expected: Int64 = 0
    private var lastSampleTime: Date?
    private var lastSampleBytes: Int64 = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// The partial download. Kept in Application Support rather than tmp so iOS
    /// will not reclaim it between attempts.
    nonisolated static var partialURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("model-download.zip")
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true    // gated per request instead
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        canResume = Self.partialBytes() > 0
    }

    nonisolated private static func partialBytes() -> Int64 {
        let values = try? partialURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .unpacking: return true
        default: return false
        }
    }

    /// Human-readable one-liner for the UI.
    var statusText: String {
        switch phase {
        case .idle:
            return canResume ? "Paused — \(ByteCountFormatter.string(fromByteCount: Self.partialBytes(), countStyle: .file)) downloaded" : ""
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

        let alreadyHave = Self.partialBytes()
        if let free = Self.availableBytes(), free + alreadyHave < option.approximateBytes * 3 {
            let needed = ByteCountFormatter.string(fromByteCount: option.approximateBytes * 3, countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            phase = .failed("Not enough space. Need about \(needed) free while installing, you have \(have).")
            return
        }

        var request = URLRequest(url: option.url)
        request.allowsCellularAccess = allowCellular
        if alreadyHave > 0 {
            // Ask the server to carry on from where the partial file stops.
            request.setValue("bytes=\(alreadyHave)-", forHTTPHeaderField: "Range")
        }

        received = alreadyHave
        expected = option.approximateBytes
        speed = nil
        lastSampleTime = nil
        lastSampleBytes = alreadyHave
        phase = .downloading(received: received, total: expected)

        beginBackgroundAssertion()
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    /// Stops but keeps the partial file, so Resume continues mid-download.
    func pause() {
        task?.cancel()
        task = nil
        closeHandle()
        endBackgroundAssertion()
        canResume = Self.partialBytes() > 0
        phase = .idle
    }

    /// Throws away the partial file and any error state.
    func cancel() {
        task?.cancel()
        task = nil
        closeHandle()
        endBackgroundAssertion()
        try? FileManager.default.removeItem(at: Self.partialURL)
        canResume = false
        speed = nil
        phase = .idle
    }

    /// Clears a failure and starts over from scratch.
    func restart(_ option: ModelOption) {
        cancel()
        start(option)
    }

    private static func availableBytes() -> Int64? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    /// Buys a few minutes of running time if the user leaves the app mid-file.
    private func beginBackgroundAssertion() {
        endBackgroundAssertion()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "model-download") { [weak self] in
            Task { @MainActor in self?.pause() }
        }
    }

    private func endBackgroundAssertion() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func closeHandle() {
        try? handle?.close()
        handle = nil
    }

    // MARK: - Streaming

    fileprivate func openFile(appending: Bool, total expectedTotal: Int64) -> Bool {
        let fm = FileManager.default
        let url = Self.partialURL
        if !appending {
            try? fm.removeItem(at: url)
            received = 0
            lastSampleBytes = 0
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            self.handle = handle
            self.expected = expectedTotal
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    fileprivate func append(_ data: Data) {
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            task?.cancel()
            task = nil
            phase = .failed(error.localizedDescription)
            return
        }
        received += Int64(data.count)

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
        phase = .downloading(received: received, total: max(expected, received))
    }

    fileprivate func completed(error: Error?) {
        closeHandle()
        endBackgroundAssertion()
        task = nil

        if let error {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            canResume = Self.partialBytes() > 0
            phase = .failed(error.localizedDescription)
            return
        }
        unpack()
    }

    // MARK: - Unpacking

    private func unpack() {
        phase = .unpacking(fraction: 0)
        canResume = false
        let archive = Self.partialURL
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
                try fm.unzipItem(at: archive, to: unpacked, skipCRC32: true, progress: progress)
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
                await MainActor.run {
                    ticker.cancel()
                    // The archive is suspect if it would not open; start clean.
                    try? FileManager.default.removeItem(at: archive)
                    self.canResume = false
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

extension ModelDownloader: URLSessionDataDelegate {

    nonisolated func urlSession(_ session: URLSession,
                                dataTask: URLSessionDataTask,
                                didReceive response: URLResponse,
                                completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 200
        // 206 means the server honoured our range request and we append;
        // 200 means it sent the whole file, so start the file over.
        let appending = status == 206
        let length = response.expectedContentLength
        let existing = Self.partialBytes()
        let total = appending && length > 0 ? existing + length : max(length, 0)

        Task { @MainActor in
            guard status < 400 else {
                completionHandler(.cancel)
                self.phase = .failed("The server refused the download (HTTP \(status)).")
                return
            }
            let ready = self.openFile(appending: appending,
                                      total: total > 0 ? total : ModelOption.standard.approximateBytes)
            completionHandler(ready ? .allow : .cancel)
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in self.append(data) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in self.completed(error: error) }
    }
}
