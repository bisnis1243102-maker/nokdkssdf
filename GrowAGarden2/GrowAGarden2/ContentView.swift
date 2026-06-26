import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var game = GardenModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showShop = false
    @State private var showBackpack = false
    @State private var plantingPlot: Int? = nil

    var body: some View {
        ZStack {
            GardenSceneView(game: game, plantingPlot: $plantingPlot)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                header
                weatherBar
                Spacer()
                hintBar
                bottomBar
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 10)
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

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Lv \(game.level)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green))
                    Text("Grow a Garden 3D")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                levelBar.frame(width: 150, height: 5)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("🪙")
                Text(Format.money(game.money))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .foregroundColor(.white)
        .shadow(radius: 3)
    }

    private var levelBar: some View {
        GeometryReader { geo in
            let p = game.levelProgress
            let frac = p.needed > 0 ? CGFloat(p.into) / CGFloat(p.needed) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.3))
                Capsule().fill(Color.yellow).frame(width: max(2, geo.size.width * min(1, frac)))
            }
        }
    }

    private var weatherBar: some View {
        let w = Weather.current
        return HStack(spacing: 8) {
            Text(w.emoji)
            Text(w.name).font(.subheadline.weight(.bold))
            Text("·").opacity(0.5)
            Text(w.blurb).font(.caption).opacity(0.9).lineLimit(1)
            Spacer()
            Text("\(Weather.secondsUntilChange)s").font(.caption.monospacedDigit()).opacity(0.7)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.28)))
        .shadow(radius: 2)
    }

    private var hintBar: some View {
        HStack(spacing: 10) {
            if game.sprinklerLevel > 0 {
                Tag(text: "💦 Sprinkler \(game.sprinklerLevel)")
            }
            if game.fertilizer > 0 {
                Tag(text: "🧪 \(game.fertilizer)")
            }
            if game.autoHarvesterUnlocked {
                Tag(text: game.autoHarvestEnabled ? "🤖 Auto ON" : "🤖 Auto OFF")
            }
            Spacer()
            Text("Drag to orbit · tap a plot")
                .font(.caption2).foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            BarButton(icon: "cart.fill", label: "Shop") { showShop = true }
            BarButton(icon: "leaf.fill",
                      label: game.readyCount > 0 ? "Harvest (\(game.readyCount))" : "Harvest",
                      highlighted: game.readyCount > 0) {
                game.harvestAll()
                if game.readyCount == 0 {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            BarButton(icon: "bag.fill",
                      label: game.backpack.isEmpty ? "Bag" : "Bag (\(game.backpack.count))") {
                showBackpack = true
            }
        }
    }
}

extension Int: Identifiable { public var id: Int { self } }

private struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.3)))
            .foregroundColor(.white)
    }
}

private struct BarButton: View {
    let icon: String
    let label: String
    var highlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(highlighted ? Color.green : Color.black.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
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
                    List {
                        if game.fertilizer > 0 {
                            Toggle(isOn: $game.useFertilizerOnPlant) {
                                Label("Use Fertilizer (×\(game.fertilizer)) — boosts mutations",
                                      systemImage: "testtube.2")
                            }
                            .tint(.green)
                        }
                        Section("Your seeds") {
                            ForEach(ownedSeeds, id: \.0.id) { crop, count in
                                Button {
                                    game.plant(crop, in: plotID)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onDone()
                                } label: {
                                    HStack {
                                        Text(crop.emoji).font(.title2)
                                        VStack(alignment: .leading) {
                                            Text(crop.name).font(.headline)
                                            Text("Grows in \(Format.time(Int(game.effectiveGrow(crop))))")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("×\(count)").font(.headline).foregroundColor(.green)
                                    }
                                }
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
    @State private var tab = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Seeds").tag(0)
                    Text("Upgrades").tag(1)
                }
                .pickerStyle(.segmented).padding()

                if tab == 0 { seedList } else { upgradeList }
            }
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("🪙 \(Format.money(game.money))").font(.headline)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var seedList: some View {
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
                BuyButton(price: crop.seedCost, enabled: game.money >= crop.seedCost) {
                    game.buySeed(crop)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var upgradeList: some View {
        List {
            Section("Garden") {
                if let cost = game.nextPlotCost() {
                    UpgradeRow(icon: "square.grid.3x3.fill", title: "Expand Garden",
                               subtitle: "Unlock plot \(game.unlockedPlots + 1) of \(GardenModel.maxPlots)",
                               price: cost, enabled: game.money >= cost) { game.buyPlot() }
                } else {
                    InfoRow(icon: "checkmark.seal.fill", title: "Garden maxed",
                            subtitle: "All \(GardenModel.maxPlots) plots unlocked")
                }
            }
            Section("Boosters") {
                if let cost = game.sprinklerCost() {
                    UpgradeRow(icon: "drop.fill", title: "Sprinkler Lv \(game.sprinklerLevel + 1)",
                               subtitle: "Crops grow ~8% faster (now \(Int((1 - pow(0.92, Double(game.sprinklerLevel))) * 100))% faster)",
                               price: cost, enabled: game.money >= cost) { game.buySprinkler() }
                } else {
                    InfoRow(icon: "drop.fill", title: "Sprinkler maxed",
                            subtitle: "Max growth speed reached")
                }
                UpgradeRow(icon: "testtube.2", title: "Fertilizer (×1)",
                           subtitle: "Apply at planting to boost mutation odds. Have: \(game.fertilizer)",
                           price: game.fertilizerCost, enabled: game.money >= game.fertilizerCost) {
                    game.buyFertilizer()
                }
            }
            Section("Automation") {
                if game.autoHarvesterUnlocked {
                    Toggle(isOn: $game.autoHarvestEnabled) {
                        Label("Auto-Harvester", systemImage: "gearshape.2.fill")
                    }.tint(.green)
                } else {
                    UpgradeRow(icon: "gearshape.2.fill", title: "Auto-Harvester",
                               subtitle: "Automatically collects ready crops",
                               price: game.autoHarvesterCost, enabled: game.money >= game.autoHarvesterCost) {
                        game.buyAutoHarvester()
                    }
                }
            }
        }
    }
}

private struct BuyButton: View {
    let price: Int
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("🪙\(Format.money(price))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(enabled ? Color.green : Color.gray))
                .foregroundColor(.white)
        }.disabled(!enabled)
    }
}

private struct UpgradeRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let price: Int
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: icon).font(.title2).frame(width: 34).foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            BuyButton(price: price, enabled: enabled, action: action)
        }.padding(.vertical, 2)
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack {
            Image(systemName: icon).font(.title2).frame(width: 34).foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }.padding(.vertical, 2)
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
                                    Text("×\(stack.count) · 🪙\(Format.money(stack.unitValue)) each")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("🪙\(Format.money(stack.totalValue))") {
                                    withAnimation { game.sell(stackID: stack.id) }
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .buttonStyle(.borderedProminent).tint(.green)
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
                        Text("Sell All  🪙\(Format.money(game.backpackTotal))").frame(maxWidth: .infinity)
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
