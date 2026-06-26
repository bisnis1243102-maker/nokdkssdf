import SwiftUI

struct ContentView: View {
    @StateObject private var game = GardenModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showShop = false
    @State private var showBackpack = false
    @State private var plantingPlot: Int? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.52, green: 0.80, blue: 0.45),
                                    Color(red: 0.27, green: 0.55, blue: 0.30)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                weatherBar

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(game.plots.prefix(game.unlockedPlots)) { plot in
                            PlotView(game: game, plot: plot)
                                .onTapGesture { tapPlot(plot) }
                        }
                        if let cost = game.nextPlotCost() {
                            BuyPlotTile(cost: cost, canAfford: game.money >= cost) {
                                game.buyPlot()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 90)
                }
            }

            VStack { Spacer(); bottomBar }
        }
        .sheet(isPresented: $showShop) { ShopView(game: game) }
        .sheet(isPresented: $showBackpack) { BackpackView(game: game) }
        .sheet(item: $plantingPlot) { plotID in
            PlantPickerView(game: game, plotID: plotID) { plantingPlot = nil }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { game.save() }
        }
    }

    private func tapPlot(_ plot: GardenModel.Plot) {
        if plot.cropID == nil {
            plantingPlot = plot.id
        } else if game.isReady(plot) {
            withAnimation(.spring(response: 0.3)) { game.harvest(plotID: plot.id) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Grow a Garden 2")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Text("Lifetime: \(Format.money(game.lifetimeEarned))")
                    .font(.caption2).opacity(0.8)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("🪙").font(.title3)
                Text(Format.money(game.money))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .foregroundColor(.white)
        .padding(.horizontal).padding(.top, 8)
    }

    private var weatherBar: some View {
        let w = Weather.current
        return HStack(spacing: 8) {
            Text(w.emoji)
            Text(w.name).font(.subheadline.weight(.bold))
            Text("·").opacity(0.5)
            Text(w.blurb).font(.caption).opacity(0.9)
            Spacer()
            Text("\(Weather.secondsUntilChange)s")
                .font(.caption.monospacedDigit()).opacity(0.7)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.18)))
        .padding(.horizontal)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            BarButton(icon: "cart.fill", label: "Shop") { showShop = true }
            BarButton(icon: "leaf.fill",
                      label: game.readyCount > 0 ? "Harvest (\(game.readyCount))" : "Harvest",
                      highlighted: game.readyCount > 0) {
                withAnimation(.spring(response: 0.35)) { game.harvestAll() }
            }
            BarButton(icon: "bag.fill",
                      label: game.backpack.isEmpty ? "Bag" : "Bag (\(game.backpack.count))") {
                showBackpack = true
            }
        }
        .padding(.horizontal).padding(.bottom, 10)
    }
}

// Lets us use a plot Int as a sheet item.
extension Int: Identifiable { public var id: Int { self } }

// MARK: - Plot tile

private struct PlotView: View {
    @ObservedObject var game: GardenModel
    let plot: GardenModel.Plot

    var body: some View {
        let ready = game.isReady(plot)
        let progress = game.progress(of: plot)
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.42, green: 0.29, blue: 0.18))
            RoundedRectangle(cornerRadius: 14)
                .stroke(ready ? Color.yellow : Color.black.opacity(0.2),
                        lineWidth: ready ? 3 : 1)

            if let cropID = plot.cropID {
                let crop = CropCatalog.crop(cropID)
                VStack(spacing: 4) {
                    Text(crop.emoji)
                        .font(.system(size: 34))
                        .scaleEffect(0.45 + 0.55 * progress)
                        .opacity(0.6 + 0.4 * progress)
                        .shadow(color: ready ? .yellow.opacity(0.8) : .clear, radius: 6)
                    if ready {
                        Text("Harvest!")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.yellow)
                    } else {
                        ProgressView(value: progress)
                            .tint(.green)
                            .scaleEffect(x: 1, y: 0.7)
                            .padding(.horizontal, 8)
                        Text(Format.time(game.secondsLeft(of: plot)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .padding(6)
            } else {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(height: 84)
        .scaleEffect(ready ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: ready)
    }
}

private struct BuyPlotTile: View {
    let cost: Int
    let canAfford: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.18))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(.white.opacity(0.4))
                VStack(spacing: 4) {
                    Image(systemName: "lock.open.fill").foregroundColor(.white)
                    Text("🪙 \(Format.money(cost))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(canAfford ? .yellow : .white.opacity(0.6))
                }
            }
            .frame(height: 84)
        }
        .disabled(!canAfford)
    }
}

// MARK: - Bottom bar button

private struct BarButton: View {
    let icon: String
    let label: String
    var highlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(label).font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(highlighted ? Color.green : Color.black.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)))
        }
    }
}

// MARK: - Plant picker

private struct PlantPickerView: View {
    @ObservedObject var game: GardenModel
    let plotID: Int
    let onDone: () -> Void

    var ownedSeeds: [(Crop, Int)] {
        CropCatalog.all.compactMap { crop in
            let c = game.seeds[crop.id] ?? 0
            return c > 0 ? (crop, c) : nil
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if ownedSeeds.isEmpty {
                    VStack(spacing: 10) {
                        Text("🌱").font(.system(size: 50))
                        Text("No seeds yet").font(.headline)
                        Text("Buy seeds from the Shop first.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }.padding()
                } else {
                    List(ownedSeeds, id: \.0.id) { crop, count in
                        Button {
                            game.plant(crop, in: plotID)
                            onDone()
                        } label: {
                            HStack {
                                Text(crop.emoji).font(.title2)
                                VStack(alignment: .leading) {
                                    Text(crop.name).font(.headline)
                                    Text("Grows in \(Format.time(Int(crop.growSeconds)))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("x\(count)").font(.headline).foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plant a seed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDone) } }
        }
    }
}

// MARK: - Shop

private struct ShopView: View {
    @ObservedObject var game: GardenModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(CropCatalog.all) { crop in
                HStack {
                    Text(crop.emoji).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crop.name).font(.headline)
                        Text("Sells ~🪙\(Format.money(crop.baseValue)) · \(Format.time(Int(crop.growSeconds)))")
                            .font(.caption).foregroundColor(.secondary)
                        if let owned = game.seeds[crop.id], owned > 0 {
                            Text("Owned: \(owned)").font(.caption2).foregroundColor(.green)
                        }
                    }
                    Spacer()
                    Button {
                        withAnimation { game.buySeed(crop) }
                    } label: {
                        Text("🪙\(Format.money(crop.seedCost))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(game.money >= crop.seedCost ? Color.green : Color.gray))
                            .foregroundColor(.white)
                    }
                    .disabled(game.money < crop.seedCost)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Seed Shop")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("🪙 \(Format.money(game.money))").font(.headline)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Backpack

private struct BackpackView: View {
    @ObservedObject var game: GardenModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if game.backpack.isEmpty {
                    VStack(spacing: 10) {
                        Text("🎒").font(.system(size: 50))
                        Text("Backpack empty").font(.headline)
                        Text("Harvest crops, then sell them here.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }.padding()
                } else {
                    List {
                        ForEach(game.backpack) { stack in
                            HStack {
                                Text(stack.crop.emoji).font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(stack.crop.name).font(.headline)
                                        if stack.mutation != .normal {
                                            Text("\(stack.mutation.badge) \(stack.mutation.name)")
                                                .font(.caption.bold())
                                                .foregroundColor(stack.mutation.tint)
                                        }
                                    }
                                    Text("x\(stack.count) · 🪙\(Format.money(stack.unitValue)) each")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("🪙\(Format.money(stack.totalValue))") {
                                    withAnimation { game.sell(stackID: stack.id) }
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Backpack")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        withAnimation { game.sellAll() }
                    } label: {
                        Text("Sell All  🪙\(Format.money(game.backpackTotal))")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(game.backpack.isEmpty)
                }
            }
        }
    }
}

// MARK: - Formatting

enum Format {
    static func money(_ n: Int) -> String {
        let v = Double(n)
        switch n {
        case 1_000_000_000...: return String(format: "%.2fB", v / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.2fM", v / 1_000_000)
        case 10_000...:        return String(format: "%.1fK", v / 1_000)
        default:               return "\(n)"
        }
    }

    static func time(_ seconds: Int) -> String {
        if seconds <= 0 { return "0s" }
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

#Preview {
    ContentView()
}
