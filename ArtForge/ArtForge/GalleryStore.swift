import Foundation
import SwiftUI

/// Owns the current piece, the render queue, and the saved gallery.
///
/// Only recipes are persisted — images are re-rendered on demand, which keeps
/// the on-disk footprint tiny no matter how much you generate.
@MainActor
final class GalleryStore: ObservableObject {

    @Published var prompt: String = ""
    @Published var style: ArtStyle = .scene
    @Published var seed: UInt64 = UInt64.random(in: 0...UInt64.max)

    @Published private(set) var current: UIImage?
    @Published private(set) var currentRecipe: ArtRecipe?
    @Published private(set) var isRendering = false

    @Published private(set) var gallery: [ArtRecipe] = []
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]

    @Published var toast: String?

    private let storageURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("gallery.json")
    }()

    private let queue = DispatchQueue(label: "art.render", qos: .userInitiated)
    private var renderToken = 0

    init() {
        loadGallery()
    }

    // MARK: - Rendering

    /// Renders the current settings. The token guard means that if you tap
    /// generate again mid-render, the stale result is discarded instead of
    /// flashing on screen after the newer one.
    func generate() {
        let recipe = ArtRecipe(prompt: prompt, style: style, seed: seed)
        renderToken += 1
        let token = renderToken
        isRendering = true

        queue.async {
            let image = ArtGenerator.render(recipe)
            Task { @MainActor [weak self] in
                guard let self, token == self.renderToken else { return }
                self.current = image
                self.currentRecipe = recipe
                self.isRendering = false
            }
        }
    }

    /// New seed, same prompt and style — a different take on the same idea.
    func reroll() {
        seed = UInt64.random(in: 0...UInt64.max)
        generate()
    }

    /// Nudges the seed slightly instead of replacing it, for a piece that is
    /// recognisably related to the one on screen.
    func variation() {
        seed = seed &+ UInt64.random(in: 1...64)
        generate()
    }

    func randomizeEverything() {
        style = ArtStyle.allCases.randomElement() ?? .scene
        seed = UInt64.random(in: 0...UInt64.max)
        generate()
    }

    func restore(_ recipe: ArtRecipe) {
        prompt = recipe.prompt
        style = recipe.style
        seed = recipe.seed
        generate()
    }

    // MARK: - Gallery

    func keepCurrent() {
        guard let recipe = currentRecipe else { return }
        guard !gallery.contains(where: { $0.prompt == recipe.prompt && $0.style == recipe.style && $0.seed == recipe.seed }) else {
            show("Already in your gallery")
            return
        }
        gallery.insert(recipe, at: 0)
        if let image = current { thumbnails[recipe.id] = thumbnail(from: image) }
        persist()
        show("Added to gallery")
    }

    func delete(_ recipe: ArtRecipe) {
        gallery.removeAll { $0.id == recipe.id }
        thumbnails[recipe.id] = nil
        persist()
    }

    private func thumbnail(from image: UIImage) -> UIImage {
        let side: CGFloat = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func persist() {
        let snapshot = gallery
        queue.async { [storageURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func loadGallery() {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode([ArtRecipe].self, from: data) else { return }
        gallery = saved
        // Re-render thumbnails in the background so the grid fills in smoothly
        // rather than blocking launch.
        queue.async {
            let rendered = saved.map { ($0.id, ArtGenerator.render($0, size: 300)) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for (id, image) in rendered { self.thumbnails[id] = image }
            }
        }
    }

    // MARK: - Export

    func saveToPhotos() {
        guard let image = current else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        show("Saved to Photos")
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self.toast == message { self.toast = nil }
        }
    }
}
