import SwiftUI

struct ContentView: View {
    @StateObject private var store = GalleryStore()
    @FocusState private var promptFocused: Bool
    @State private var showGallery = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    canvas
                    promptField
                    styleStrip
                    actions
                    if !store.gallery.isEmpty { galleryStrip }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            if let toast = store.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Theme.card))
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        .foregroundColor(Theme.primaryText)
                        .padding(.bottom, 28)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.toast)
        .onAppear {
            if store.currentRecipe == nil { store.generate() }
        }
        .sheet(isPresented: $showGallery) {
            GalleryView(store: store)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ArtForge")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundColor(Theme.primaryText)
                Text("Generative studio · runs entirely on device")
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            Button {
                showGallery = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
            }
        }
        .padding(.top, 8)
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.card)

            if let image = store.current {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.opacity)
                    .id(store.currentRecipe?.id)
            }

            if store.isRendering {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.black.opacity(store.current == nil ? 0.0 : 0.45))
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.primaryText)
                    .scaleEffect(1.2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: store.current)
        .overlay(alignment: .bottomLeading) {
            if let recipe = store.currentRecipe, !store.isRendering {
                Text(recipe.signature)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.4)))
                    .padding(12)
            }
        }
        .onTapGesture {
            promptFocused = false
            store.variation()
        }
    }

    // MARK: Prompt

    private var promptField: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .foregroundColor(Theme.secondaryText)
                .font(.system(size: 14))
            TextField("Describe a mood — \"deep sea at dusk\"", text: $store.prompt)
                .focused($promptFocused)
                .submitLabel(.go)
                .foregroundColor(Theme.primaryText)
                .tint(Theme.accent)
                .onSubmit {
                    promptFocused = false
                    store.generate()
                }
            if !store.prompt.isEmpty {
                Button {
                    store.prompt = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: Styles

    private var styleStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(ArtStyle.allCases) { style in
                        let selected = store.style == style
                        Button {
                            store.style = style
                            promptFocused = false
                            store.generate()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: style.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(style.title)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(selected ? Theme.accent : Theme.card)
                            )
                            .overlay(Capsule().stroke(selected ? .clear : Theme.hairline, lineWidth: 1))
                            .foregroundColor(selected ? .black : Theme.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            Text(understoodText ?? store.style.blurb)
                .font(.caption)
                .foregroundColor(understoodText == nil ? Theme.secondaryText : Theme.accent)
                .padding(.horizontal, 2)
        }
    }

    /// For the Scene engine, spell out what the prompt was read as — it makes
    /// the connection between the words and the picture obvious.
    private var understoodText: String? {
        guard let recipe = store.currentRecipe, let summary = ArtGenerator.sceneSummary(for: recipe) else { return nil }
        return "Read as: " + summary
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                promptFocused = false
                store.reroll()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text("Generate")
                }
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .disabled(store.isRendering)
            .opacity(store.isRendering ? 0.6 : 1)

            HStack(spacing: 10) {
                secondaryButton("Variation", icon: "arrow.2.squarepath") {
                    store.variation()
                }
                secondaryButton("Surprise", icon: "dice") {
                    store.randomizeEverything()
                }
                secondaryButton("Keep", icon: "bookmark") {
                    store.keepCurrent()
                }
            }

            HStack(spacing: 10) {
                secondaryButton("Save", icon: "square.and.arrow.down") {
                    store.saveToPhotos()
                }
                if let image = store.current {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("ArtForge", image: Image(uiImage: image))) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                        .foregroundColor(Theme.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            promptFocused = false
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            .foregroundColor(Theme.primaryText)
        }
        .buttonStyle(.plain)
        .disabled(store.isRendering)
        .opacity(store.isRendering ? 0.6 : 1)
    }

    // MARK: Gallery strip

    private var galleryStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gallery")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                Spacer()
                Button("See all") { showGallery = true }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.gallery) { recipe in
                        Button {
                            store.restore(recipe)
                        } label: {
                            thumbnailView(for: recipe, side: 84)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func thumbnailView(for recipe: ArtRecipe, side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
            if let image = store.thumbnails[recipe.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ProgressView().tint(Theme.secondaryText)
            }
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Full gallery

struct GalleryView: View {
    @ObservedObject var store: GalleryStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if store.gallery.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 34))
                            .foregroundColor(Theme.secondaryText)
                        Text("Nothing kept yet")
                            .font(.headline)
                            .foregroundColor(Theme.primaryText)
                        Text("Tap Keep on a piece you like and it will show up here.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Theme.secondaryText)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.gallery) { recipe in
                                VStack(spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
                                        if let image = store.thumbnails[recipe.id] {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        } else {
                                            ProgressView().tint(Theme.secondaryText)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    Text(recipe.prompt.isEmpty ? recipe.signature : recipe.prompt)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .foregroundColor(Theme.secondaryText)
                                }
                                .onTapGesture {
                                    store.restore(recipe)
                                    dismiss()
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(recipe)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Theme

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let hairline = Color.white.opacity(0.09)
    static let accent = Color(red: 0.98, green: 0.83, blue: 0.38)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.5)
}
