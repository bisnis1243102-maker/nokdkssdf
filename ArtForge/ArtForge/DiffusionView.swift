import SwiftUI
import UniformTypeIdentifiers

/// The AI tab: prompt in, generated image out, plus the one-time model setup.
struct DiffusionView: View {
    @StateObject private var engine = DiffusionEngine()

    @State private var prompt = ""
    @State private var negativePrompt = "blurry, low quality, watermark, text"
    @State private var steps: Double = 20
    @State private var guidance: Double = 7.5
    @State private var lockedSeed = false
    @State private var seed: UInt32 = UInt32.random(in: 0...UInt32.max)

    @State private var showImporter = false
    @State private var importStatus: String?
    @State private var importError: String?
    @State private var showSetupHelp = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    canvas
                    if engine.state == .missingModel {
                        setupCard
                    } else {
                        controls
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { engine.refreshModelState() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showSetupHelp) { setupInstructions }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card)

            if let image = engine.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            switch engine.state {
            case .loading:
                progressOverlay(title: "Loading model…", detail: "First run takes a minute", fraction: nil)
            case .generating(let step, let total):
                progressOverlay(title: "Generating…",
                                detail: "Step \(step) of \(total)",
                                fraction: total > 0 ? Double(step) / Double(total) : nil)
            case .failed(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.accent)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 24)
                }
            case .missingModel:
                VStack(spacing: 8) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 30))
                        .foregroundColor(Theme.secondaryText)
                    Text("No model installed")
                        .font(.headline)
                        .foregroundColor(Theme.primaryText)
                }
            case .idle:
                if engine.image == nil {
                    Text("Describe anything")
                        .font(.footnote)
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private func progressOverlay(title: String, detail: String, fraction: Double?) -> some View {
        VStack(spacing: 10) {
            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 160)
            } else {
                ProgressView().tint(Theme.primaryText)
            }
            Text(title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.primaryText)
            Text(detail).font(.caption).foregroundColor(Theme.secondaryText)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.55)))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            field("Prompt", text: $prompt, placeholder: "a red fox in a snowy forest, cinematic")
            field("Avoid", text: $negativePrompt, placeholder: "things to keep out of the image")

            VStack(spacing: 10) {
                slider(label: "Steps", value: $steps, range: 6...50, step: 1,
                       caption: "\(Int(steps)) — higher is slower and more detailed")
                slider(label: "Guidance", value: $guidance, range: 1...15, step: 0.5,
                       caption: String(format: "%.1f — how strictly it follows the prompt", guidance))
            }

            Toggle(isOn: $lockedSeed) {
                Text("Lock seed (\(seed))")
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
            }
            .tint(Theme.accent)

            Button {
                if !lockedSeed { seed = UInt32.random(in: 0...UInt32.max) }
                engine.generate(prompt: prompt,
                                negativePrompt: negativePrompt,
                                steps: Int(steps),
                                guidance: Float(guidance),
                                seed: seed)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Generate")
                }
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
            .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isBusy ? 0.55 : 1)

            HStack(spacing: 10) {
                if let image = engine.image {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    } label: {
                        secondaryLabel("Save", icon: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("ArtForge", image: Image(uiImage: image))) {
                        secondaryLabel("Share", icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
            }

            modelFooter
        }
    }

    private var isBusy: Bool {
        if case .generating = engine.state { return true }
        return engine.state == .loading
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .foregroundColor(Theme.primaryText)
                .tint(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private func slider(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                        step: Double, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.weight(.semibold)).foregroundColor(Theme.primaryText)
                Spacer()
                Text(caption).font(.caption2).foregroundColor(Theme.secondaryText)
            }
            Slider(value: value, in: range, step: step).tint(Theme.accent)
        }
    }

    private func secondaryLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 13).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hairline, lineWidth: 1))
        .foregroundColor(Theme.primaryText)
    }

    private var modelFooter: some View {
        HStack {
            if let size = DiffusionEngine.installedModelSize() {
                Text("Model installed · \(size)")
                    .font(.caption2)
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            Button("Replace") { showImporter = true }
                .font(.caption2.weight(.semibold))
                .foregroundColor(Theme.accent)
            Button("Remove") {
                try? DiffusionEngine.deleteModel()
                engine.unload()
                engine.refreshModelState()
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.red.opacity(0.8))
        }
        .padding(.top, 4)
    }

    // MARK: Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One-time setup")
                .font(.headline)
                .foregroundColor(Theme.primaryText)
            Text("""
                 To generate any subject you describe, ArtForge needs a Stable \
                 Diffusion model converted to Core ML. The model is 1.5–2.5 GB, \
                 which is far too large to ship inside a sideloaded app, so you \
                 install it once yourself.

                 Nothing is uploaded and no account or key is involved — once the \
                 model is on your phone, generation works in airplane mode.
                 """)
                .font(.footnote)
                .foregroundColor(Theme.secondaryText)

            if let importStatus {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    Text(importStatus).font(.caption).foregroundColor(Theme.primaryText)
                }
            }

            Button { showImporter = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                    Text("Choose model folder")
                }
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .disabled(importStatus != nil)

            Button("How do I get the model?") { showSetupHelp = true }
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accent)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
    }

    private var setupInstructions: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    step(1, "Download a Core ML model",
                         "On a computer, get a Core ML converted Stable Diffusion model — for example Apple's own `coreml-stable-diffusion-2-1-base-palettized` on Hugging Face. Pick the `split_einsum` variant: it is the one built for the Neural Engine.")
                    step(2, "Unzip it",
                         "You want the folder that directly contains `Unet.mlmodelc`, `TextEncoder.mlmodelc`, `VAEDecoder.mlmodelc`, `merges.txt`, and `vocab.json`.")
                    step(3, "Get it onto the phone",
                         "AirDrop the folder to your iPhone, or drag it into the Files app via iCloud Drive or a USB connection in Finder.")
                    step(4, "Import it here",
                         "Tap “Choose model folder” and select that folder. ArtForge copies it into its own storage — this takes a couple of minutes for a few gigabytes.")
                    step(5, "Generate",
                         "A 20-step image takes roughly 20–40 seconds on an A16 or newer, longer on older devices. Palettized (6-bit) models load faster and use far less memory.")

                    Text("Requires an iPhone with at least 6 GB of RAM (iPhone 13 Pro or newer is comfortable). Older devices may run out of memory loading the model.")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Model setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showSetupHelp = false }.foregroundColor(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func step(_ number: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.primaryText)
                Text(body).font(.footnote).foregroundColor(Theme.secondaryText)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importStatus = "Preparing…"
            Task {
                do {
                    try await DiffusionEngine.importModel(from: url) { message in
                        Task { @MainActor in importStatus = message }
                    }
                    importStatus = nil
                    engine.refreshModelState()
                } catch {
                    importStatus = nil
                    importError = error.localizedDescription
                }
            }
        }
    }
}
