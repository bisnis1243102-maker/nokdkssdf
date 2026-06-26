import SwiftUI
import Combine

final class GardenModel: ObservableObject {

    struct Plot: Identifiable {
        let id: Int
        var cropID: String?
        var plantedAt: Date?
    }

    // MARK: Published state
    @Published var money: Int = 50
    @Published var seeds: [String: Int] = ["carrot": 3]
    @Published var plots: [Plot] = []
    @Published var unlockedPlots: Int = 4
    @Published var backpack: [HarvestStack] = []
    @Published var lifetimeEarned: Int = 0
    @Published var now: Date = Date()      // ticks every second to refresh growth UI

    static let maxPlots = 24
    private let saveKey = "growagarden2.save.v1"
    private var timer: Timer?

    init() {
        if !load() {
            plots = (0..<Self.maxPlots).map { Plot(id: $0, cropID: nil, plantedAt: nil) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
    }

    // MARK: Growth helpers

    func progress(of plot: Plot) -> Double {
        guard let cropID = plot.cropID, let planted = plot.plantedAt else { return 0 }
        let grow = CropCatalog.crop(cropID).growSeconds
        return min(1.0, now.timeIntervalSince(planted) / grow)
    }

    func isReady(_ plot: Plot) -> Bool { plot.cropID != nil && progress(of: plot) >= 1.0 }

    func secondsLeft(of plot: Plot) -> Int {
        guard let cropID = plot.cropID, let planted = plot.plantedAt else { return 0 }
        let grow = CropCatalog.crop(cropID).growSeconds
        return max(0, Int(grow - now.timeIntervalSince(planted)))
    }

    var readyCount: Int { plots.prefix(unlockedPlots).filter { isReady($0) }.count }

    // MARK: Actions

    func buySeed(_ crop: Crop) {
        guard money >= crop.seedCost else { return }
        money -= crop.seedCost
        seeds[crop.id, default: 0] += 1
        save()
    }

    func plant(_ crop: Crop, in plotID: Int) {
        guard (seeds[crop.id] ?? 0) > 0,
              let idx = plots.firstIndex(where: { $0.id == plotID }),
              plots[idx].cropID == nil else { return }
        seeds[crop.id]! -= 1
        if seeds[crop.id]! <= 0 { seeds[crop.id] = nil }
        plots[idx].cropID = crop.id
        plots[idx].plantedAt = Date()
        save()
    }

    func harvest(plotID: Int) {
        guard let idx = plots.firstIndex(where: { $0.id == plotID }),
              let cropID = plots[idx].cropID, isReady(plots[idx]) else { return }
        let crop = CropCatalog.crop(cropID)
        let mutation = Weather.current.rollMutation()
        let value = crop.baseValue * mutation.multiplier
        addToBackpack(cropID: cropID, mutation: mutation, value: value)
        plots[idx].cropID = nil
        plots[idx].plantedAt = nil
        save()
    }

    func harvestAll() {
        for plot in plots.prefix(unlockedPlots) where isReady(plot) {
            harvest(plotID: plot.id)
        }
    }

    private func addToBackpack(cropID: String, mutation: Mutation, value: Int) {
        if let i = backpack.firstIndex(where: { $0.cropID == cropID && $0.mutation == mutation }) {
            backpack[i].count += 1
        } else {
            backpack.append(HarvestStack(cropID: cropID, mutation: mutation, count: 1, unitValue: value))
        }
    }

    func sell(stackID: UUID) {
        guard let i = backpack.firstIndex(where: { $0.id == stackID }) else { return }
        gainMoney(backpack[i].totalValue)
        backpack.remove(at: i)
        save()
    }

    func sellAll() {
        let total = backpack.reduce(0) { $0 + $1.totalValue }
        guard total > 0 else { return }
        gainMoney(total)
        backpack.removeAll()
        save()
    }

    private func gainMoney(_ amount: Int) {
        money += amount
        lifetimeEarned += amount
    }

    var backpackTotal: Int { backpack.reduce(0) { $0 + $1.totalValue } }

    // MARK: Plots

    func nextPlotCost() -> Int? {
        guard unlockedPlots < Self.maxPlots else { return nil }
        return Int(100 * pow(1.7, Double(unlockedPlots - 4)))
    }

    func buyPlot() {
        guard let cost = nextPlotCost(), money >= cost else { return }
        money -= cost
        unlockedPlots += 1
        save()
    }

    // MARK: Persistence

    func save() {
        let snapshot = GardenSave(
            money: money,
            seeds: seeds,
            unlockedPlots: unlockedPlots,
            plots: plots.map { PlotSave(cropID: $0.cropID, plantedAt: $0.plantedAt) },
            backpack: backpack,
            lifetimeEarned: lifetimeEarned
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    @discardableResult
    private func load() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let s = try? JSONDecoder().decode(GardenSave.self, from: data) else { return false }
        money = s.money
        seeds = s.seeds
        unlockedPlots = s.unlockedPlots
        backpack = s.backpack
        lifetimeEarned = s.lifetimeEarned
        plots = (0..<Self.maxPlots).map { i in
            if i < s.plots.count {
                return Plot(id: i, cropID: s.plots[i].cropID, plantedAt: s.plots[i].plantedAt)
            }
            return Plot(id: i, cropID: nil, plantedAt: nil)
        }
        return true
    }
}
