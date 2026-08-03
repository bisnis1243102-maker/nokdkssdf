import SwiftUI
import UniformTypeIdentifiers

/// One turn in the conversation.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    enum Body: Equatable {
        case text(String)
        case image(UIImage)
        case working(String)
        case setup
    }

    let id = UUID()
    let role: Role
    var body: Body
    /// Kept so "again" knows what to re-run.
    var sourcePrompt: String = ""
}

/// A conversational front end for the on-device model: you type, it answers
/// with a picture. Same shape as any chat app — thread above, composer below.
struct ChatView: View {
    @StateObject private var engine = DiffusionEngine()

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var composerFocused: Bool

    // Generation settings, tucked behind the toolbar so the thread stays clean.
    @AppStorage("negativePrompt") private var negativePrompt = "blurry, low quality, watermark, text"
    @AppStorage("steps") private var steps = 20.0
    @AppStorage("guidance") private var guidance = 7.5

    @State private var showSettings = false
    @State private var showImporter = false
    @State private var showSetupHelp = false
    @State private var importStatus: String?
    @State private var importError: String?
    @StateObject private var downloader = ModelDownloader()

    private let suggestions = [
        "a red fox in a snowy forest, cinematic",
        "an astronaut riding a horse on mars",
        "a cosy bookshop café, warm light",
        "a cyberpunk street at night, neon reflections"
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                thread
                composer
            }
        }
        .navigationTitle("ArtForge AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    messages.removeAll()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .foregroundColor(Theme.primaryText)
                .disabled(messages.isEmpty)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .foregroundColor(Theme.primaryText)
            }
        }
        .onAppear {
            engine.refreshModelState()
            if messages.isEmpty && engine.state == .missingModel {
                messages = [ChatMessage(role: .assistant, body: .setup)]
            }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showSetupHelp) { setupInstructions }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { handleImport($0) }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty { emptyState }
                    ForEach(messages) { message in
                        row(for: message).id(message.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages) { _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: engine.state) { _ in
                updateWorkingMessage()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.accent)
            Text("What should I draw?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.primaryText)

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        draft = suggestion
                        send()
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.footnote)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(Theme.primaryText)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundColor(Theme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func row(for message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            // User turns sit on the right, in a bubble.
            HStack {
                Spacer(minLength: 50)
                if case .text(let text) = message.body {
                    Text(text)
                        .font(.body)
                        .foregroundColor(Theme.primaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
                }
            }
        case .assistant:
            // Assistant turns run the full width behind a small avatar.
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle().fill(Theme.accent)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }
                .frame(width: 27, height: 27)

                VStack(alignment: .leading, spacing: 10) {
                    switch message.body {
                    case .text(let text):
                        Text(text)
                            .font(.body)
                            .foregroundColor(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                    case .working(let status):
                        HStack(spacing: 9) {
                            TypingDots()
                            Text(status).font(.footnote).foregroundColor(Theme.secondaryText)
                        }

                    case .image(let image):
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.hairline, lineWidth: 1))

                        HStack(spacing: 16) {
                            imageAction("Save", icon: "square.and.arrow.down") {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            }
                            ShareLink(item: Image(uiImage: image),
                                      preview: SharePreview("ArtForge", image: Image(uiImage: image))) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.secondaryText)
                            }
                            imageAction("Again", icon: "arrow.clockwise") {
                                draft = message.sourcePrompt
                                send()
                            }
                        }

                    case .setup:
                        setupCard
                    }
                }
            }
        }
    }

    private func imageAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.hairline)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Describe an image…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .foregroundColor(Theme.primaryText)
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.card))
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))

                Button(action: send) {
                    ZStack {
                        Circle().fill(canSend ? Theme.accent : Theme.card)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(canSend ? .black : Theme.secondaryText)
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Theme.background)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Sending

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        draft = ""
        composerFocused = false
        messages.append(ChatMessage(role: .user, body: .text(prompt)))

        guard DiffusionEngine.modelInstalled() else {
            messages.append(ChatMessage(role: .assistant, body: .setup))
            return
        }

        isSending = true
        messages.append(ChatMessage(role: .assistant,
                                    body: .working("Warming up the model…"),
                                    sourcePrompt: prompt))

        Task {
            do {
                let image = try await engine.generateImage(prompt: prompt,
                                                           negativePrompt: negativePrompt,
                                                           steps: Int(steps),
                                                           guidance: Float(guidance),
                                                           seed: UInt32.random(in: 0...UInt32.max))
                replaceLastAssistant(with: .image(image), prompt: prompt)
            } catch {
                replaceLastAssistant(with: .text(error.localizedDescription), prompt: prompt)
            }
            isSending = false
        }
    }

    /// Mirrors engine progress into the pending assistant bubble.
    private func updateWorkingMessage() {
        guard let index = messages.lastIndex(where: {
            if case .working = $0.body { return true } else { return false }
        }) else { return }

        switch engine.state {
        case .loading:
            messages[index].body = .working("Loading the model…")
        case .generating(let step, let total):
            messages[index].body = .working("Drawing… step \(step) of \(total)")
        default:
            break
        }
    }

    private func replaceLastAssistant(with body: ChatMessage.Body, prompt: String) {
        if let index = messages.lastIndex(where: {
            if case .working = $0.body { return true } else { return false }
        }) {
            messages[index].body = body
            messages[index].sourcePrompt = prompt
        } else {
            messages.append(ChatMessage(role: .assistant, body: body, sourcePrompt: prompt))
        }
    }

    // MARK: Settings

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Things to avoid", text: $negativePrompt, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Quality") {
                    VStack(alignment: .leading) {
                        Text("Steps: \(Int(steps))").font(.caption)
                        Slider(value: $steps, in: 6...50, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Guidance: %.1f", guidance)).font(.caption)
                        Slider(value: $guidance, in: 1...15, step: 0.5)
                    }
                    Text("More steps is slower and more detailed. Higher guidance follows the prompt more literally.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Section("Model") {
                    if let size = DiffusionEngine.installedModelSize() {
                        Text("Installed · \(size)")
                    } else {
                        Text("No model installed").foregroundColor(.secondary)
                    }
                    if !DiffusionEngine.modelInstalled() {
                        Button("Download a model") { showSettings = false }
                    }
                    Button("Import model folder") { showSettings = false; showImporter = true }
                    Button("How do I get a model?") { showSetupHelp = true }
                    if DiffusionEngine.modelInstalled() {
                        Button("Remove model", role: .destructive) {
                            try? DiffusionEngine.deleteModel()
                            engine.unload()
                            engine.refreshModelState()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("I need a model first")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.primaryText)
            Text("""
                 To draw anything you describe I need a Stable Diffusion model. \
                 I can download it right here over Wi-Fi — no computer, no \
                 account, no key. It is a one-time download; after that this \
                 works in airplane mode.
                 """)
                .font(.footnote)
                .foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if downloader.isBusy || downloader.phase == .finished || isDownloadFailed {
                downloadProgress
            } else {
                Button {
                    downloader.start(ModelOption.standard)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download model")
                        Text(ModelOption.standard.sizeText)
                            .font(.caption2)
                            .opacity(0.75)
                    }
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
                    .foregroundColor(.black)
                }
                .buttonStyle(.plain)

                Text("\(ModelOption.standard.title) · Wi-Fi only · keep the app open while it runs.")
                    .font(.caption2)
                    .foregroundColor(Theme.secondaryText)

                HStack(spacing: 14) {
                    Button("Already have one? Import") { showImporter = true }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                    Button("Details") { showSetupHelp = true }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.secondaryText)
                }
            }

            if let importStatus {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    Text(importStatus).font(.caption).foregroundColor(Theme.primaryText)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
        .onChange(of: downloader.phase) { phase in
            if phase == .finished {
                engine.refreshModelState()
                messages.append(ChatMessage(role: .assistant,
                                            body: .text("Model installed. What should I draw?")))
            }
        }
    }

    private var isDownloadFailed: Bool {
        if case .failed = downloader.phase { return true }
        return false
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fraction = downloader.fraction {
                ProgressView(value: fraction).tint(Theme.accent)
            } else if downloader.isBusy {
                ProgressView().tint(Theme.accent)
            }
            HStack {
                Text(downloader.statusText)
                    .font(.caption)
                    .foregroundColor(isDownloadFailed ? .red.opacity(0.9) : Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if downloader.isBusy {
                    Button("Cancel") { downloader.cancel() }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red.opacity(0.85))
                } else if isDownloadFailed {
                    Button("Try again") { downloader.cancel() }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private var setupInstructions: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    step(1, "Tap Download model",
                         "The app downloads it straight to your phone from Apple's public Core ML model release. No computer, no account, no key — it is an ordinary file download.")
                    step(2, "Wait for the download",
                         "1.1–1.6 GB over Wi-Fi. Keep ArtForge open while it runs; you can cancel any time and start again later.")
                    step(3, "Unpacking",
                         "The zip is expanded and installed automatically. You need roughly 3 GB free while this happens; about half is freed again at the end.")
                    step(4, "Chat",
                         "Type anything. A 20-step image takes roughly 20–40 seconds on an A16 or newer.")
                    step(5, "Or bring your own",
                         "If you already have a Core ML model in Files, use Import instead and pick the folder containing Unet.mlmodelc.")

                    Text("Needs an iPhone with plenty of RAM — iPhone 13 Pro or newer is comfortable. Palettized (6-bit) models load faster and use far less memory.")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
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

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.primaryText)
                Text(detail).font(.footnote).foregroundColor(Theme.secondaryText)
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
                    messages.append(ChatMessage(role: .assistant,
                                                body: .text("Model installed. What should I draw?")))
                } catch {
                    importStatus = nil
                    importError = error.localizedDescription
                }
            }
        }
    }
}

/// The three-dot "thinking" indicator.
struct TypingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.secondaryText)
                    .frame(width: 6, height: 6)
                    .opacity(opacity(for: index))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 3
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        let position = (phase - Double(index)).truncatingRemainder(dividingBy: 3)
        return 0.35 + 0.65 * max(0, 1 - abs(position))
    }
}
