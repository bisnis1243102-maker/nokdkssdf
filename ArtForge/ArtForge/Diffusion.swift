import Foundation
import CoreML
import UIKit
import StableDiffusion

/// On-device Stable Diffusion.
///
/// Nothing here talks to a server. Apple's `StableDiffusionPipeline` runs the
/// UNet, text encoder, and VAE decoder as Core ML models on the Neural Engine,
/// so once the model files are on the phone the app generates images with the
/// device in airplane mode.
///
/// The model is not shipped inside the app — it is 1.5–2.5 GB, far past what a
/// sideloaded build can carry — so it lives in the app's Documents directory
/// and is imported once by the user.
@MainActor
final class DiffusionEngine: ObservableObject {

    enum State: Equatable {
        case missingModel
        case idle
        case loading
        case generating(step: Int, total: Int)
        case failed(String)
    }

    @Published private(set) var state: State = .missingModel
    @Published private(set) var image: UIImage?

    /// Where an imported model lives. Everything the pipeline needs sits in
    /// this one folder: TextEncoder, Unet, VAEDecoder, the tokenizer files.
    static var modelDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("StableDiffusionModel", isDirectory: true)
    }

    /// A model counts as installed only if the pieces the pipeline actually
    /// loads are present — a half-copied folder should read as missing, not
    /// blow up at generation time.
    static func modelInstalled() -> Bool {
        let fm = FileManager.default
        let required = ["TextEncoder.mlmodelc", "Unet.mlmodelc", "VAEDecoder.mlmodelc",
                        "merges.txt", "vocab.json"]
        return required.allSatisfy { fm.fileExists(atPath: modelDirectory.appendingPathComponent($0).path) }
    }

    static func installedModelSize() -> String? {
        guard modelInstalled(),
              let e = FileManager.default.enumerator(at: modelDirectory,
                                                     includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var bytes: Int64 = 0
        for case let url as URL in e {
            bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var pipeline: StableDiffusionPipeline?
    private let queue = DispatchQueue(label: "art.diffusion", qos: .userInitiated)

    init() {
        state = Self.modelInstalled() ? .idle : .missingModel
    }

    func refreshModelState() {
        if Self.modelInstalled() {
            if state == .missingModel { state = .idle }
        } else {
            pipeline = nil
            state = .missingModel
        }
    }

    /// Drops the loaded pipeline. Worth calling on a memory warning — the
    /// resident models are the biggest thing this app ever holds.
    func unload() {
        pipeline = nil
        if Self.modelInstalled() { state = .idle }
    }

    // MARK: - Generation

    func generate(prompt: String, negativePrompt: String, steps: Int, guidance: Float, seed: UInt32) {
        guard Self.modelInstalled() else { state = .missingModel; return }
        guard state != .loading else { return }
        if case .generating = state { return }

        state = .loading
        let modelURL = Self.modelDirectory
        let existing = pipeline

        queue.async { [weak self] in
            do {
                let pipe: StableDiffusionPipeline
                if let existing {
                    pipe = existing
                } else {
                    let configuration = MLModelConfiguration()
                    // The Neural Engine is both the fastest and the coolest
                    // running option for these models on A14 and later.
                    configuration.computeUnits = .cpuAndNeuralEngine
                    pipe = try StableDiffusionPipeline(resourcesAt: modelURL,
                                                       controlNet: [],
                                                       configuration: configuration,
                                                       disableSafety: false,
                                                       reduceMemory: true)
                    try pipe.loadResources()
                }

                var config = StableDiffusionPipeline.Configuration(prompt: prompt)
                config.negativePrompt = negativePrompt
                config.stepCount = steps
                config.seed = seed
                config.guidanceScale = guidance
                config.disableSafety = false
                config.schedulerType = .dpmSolverMultistepScheduler

                let images = try pipe.generateImages(configuration: config) { progress in
                    Task { @MainActor [weak self] in
                        self?.pipeline = pipe
                        self?.state = .generating(step: progress.step, total: progress.stepCount)
                    }
                    return true
                }

                let result = images.compactMap { $0 }.first
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pipeline = pipe
                    if let cg = result {
                        self.image = UIImage(cgImage: cg)
                        self.state = .idle
                    } else {
                        // A nil image is what the pipeline returns when the
                        // safety checker rejects the result.
                        self.state = .failed("The result was filtered. Try a different prompt.")
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.pipeline = nil
                    self?.state = .failed(Self.describe(error))
                }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("memory") || text.contains("resource") {
            return "Ran out of memory loading the model. A palettized (6-bit) model uses much less."
        }
        return text
    }

    // MARK: - Model import

    /// Copies a model folder the user picked in Files into the app's Documents
    /// directory. Done off the main thread — this moves gigabytes.
    nonisolated static func importModel(from pickedURL: URL,
                                        progress: @escaping @Sendable (String) -> Void) async throws {
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let destination = modelDirectory

        // The user may have picked the folder that *contains* the model rather
        // than the model folder itself; find the level that has the Unet.
        var source = pickedURL
        if !fm.fileExists(atPath: source.appendingPathComponent("Unet.mlmodelc").path) {
            let children = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
            if let nested = children.first(where: {
                fm.fileExists(atPath: $0.appendingPathComponent("Unet.mlmodelc").path)
            }) {
                source = nested
            }
        }

        guard fm.fileExists(atPath: source.appendingPathComponent("Unet.mlmodelc").path) else {
            throw NSError(domain: "ArtForge", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "That folder doesn't contain Unet.mlmodelc. Pick the folder holding the compiled Core ML model."
            ])
        }

        progress("Clearing old model…")
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for (index, item) in items.enumerated() {
            progress("Copying \(item.lastPathComponent) (\(index + 1)/\(items.count))…")
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: item, to: target)
        }

        // Keep the model out of iCloud backups; it is re-downloadable bulk.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = destination
        try? mutable.setResourceValues(values)

        progress("Done")
    }

    static func deleteModel() throws {
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
        }
    }
}
