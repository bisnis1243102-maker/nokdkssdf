import SwiftUI
import Combine

final class GardenModel: ObservableObject {

    struct Plot: Identifiable {
        let id: Int
        var cropID: String?
        var plantedAt: Date?
        var fertilized: Bool = false
    }

    // MARK: Published state
    @Published var money: Int = 50
    @Published var seeds: [String: Int] = ["carrot": 3]
    @Published var plots: [Plot] = []
    @Published var unlockedPlots: Int = 4
    @Published var backpack: [HarvestStack] = []
    @Published var lifetimeEarned: Int = 0
    @Published var now: Date = Date()      // ticks every second to refresh growth

    // Upgrades
    @Published var sprinklerLevel: Int = 0
    @Published var fertilizer: Int = 0
    @Published var autoHarvesterUnlocked: Bool = false
    @Published var autoHarvestEnabled: Bool = false
    @Published var useFertilizerOnPlant: Bool = false

    /// Set by the model when a harvest happens, so the 3D view can play an effect.
    @Published var lastHarvest: (plotID: Int, mutation: Mutation)? = nil

    static let maxPlots = 24
    static let maxSprinkler = 10
    private let saveKey = "growagarden2.save.v2"
    private var timer: Timer?

    init() {
        if !load() {
            plots = (0..<Self.maxPlots).map { Plot(id: $0, cropID: nil, plantedAt: nil) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.now = Date()
            if self.autoHarvestEnabled { self.harvestAll(animated: false) }
        }
    }

    // MARK: Growth helpers

    func effectiveGrow(_ crop: Crop) -> Double {
        crop.growSeconds * pow(0.92, Double(sprinklerLevel))
    }

    func progress(of plot: Plot) -> Double {
        guard let cropID = plot.cropID, let planted = plot.plantedAt else { return 0 }
        let grow = effectiveGrow(CropCatalog.crop(cropID))
        return min(1.0, now.timeIntervalSince(planted) / grow)
    }

    func isReady(_ plot: Plot) -> Bool { plot.cropID != nil && progress(of: plot) >= 1.0 }

    func secondsLeft(of plot: Plot) -> Int {
        guard let cropID = plot.cropID, let planted = plot.plantedAt else { return 0 }
        let grow = effectiveGrow(CropCatalog.crop(cropID))
        return max(0, Int(grow - now.timeIntervalSince(planted)))
    }

    var readyCount: Int { plots.prefix(unlockedPlots).filter { isReady($0) }.count }

    // MARK: Economy / level

    var level: Int { Level.level(forEarned: lifetimeEarned) }
    var levelProgress: (current: Int, into: Int, needed: Int) { Level.progress(forEarned: lifetimeEarned) }

    // MARK: Seeds & planting

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

        var fertilized = false
        if useFertilizerOnPlant && fertilizer > 0 {
            fertilizer -= 1
            fertilized = true
        }
        plots[idx].cropID = crop.id
        plots[idx].plantedAt = Date()
        plots[idx].fertilized = fertilized
        save()
    }

    // MARK: Harvest

    @discardableResult
    func harvest(plotID: Int, animated: Bool = true) -> Bool {
        guard let idx = plots.firstIndex(where: { $0.id == plotID }),
              let cropID = plots[idx].cropID, isReady(plots[idx]) else { return false }
        let crop = CropCatalog.crop(cropID)
        let mutation = Weather.current.rollMutation(fertilized: plots[idx].fertilized)
        let value = crop.baseValue * mutation.multiplier
        addToBackpack(cropID: cropID, mutation: mutation, value: value)
        plots[idx].cropID = nil
        plots[idx].plantedAt = nil
        plots[idx].fertilized = false
        if animated { lastHarvest = (plotID, mutation) }
        save()
        return true
    }

    func harvestAll(animated: Bool = true) {
        var any = false
        for plot in plots.prefix(unlockedPlots) where isReady(plot) {
            if harvest(plotID: plot.id, animated: animated) { any = true }
        }
        if any && !animated { objectWillChange.send() }
    }

    private func addToBackpack(cropID: String, mutation: Mutation, value: Int) {
        if let i = backpack.firstIndex(where: { $0.cropID == cropID && $0.mutation == mutation }) {
            backpack[i].count += 1
        } else {
            backpack.append(HarvestStack(cropID: cropID, mutation: mutation, count: 1, unitValue: value))
        }
    }

    // MARK: Selling

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

    // MARK: Upgrades

    func sprinklerCost() -> Int? {
        guard sprinklerLevel < Self.maxSprinkler else { return nil }
        return Int(250 * pow(Double(sprinklerLevel + 1), 2))
    }

    func buySprinkler() {
        guard let cost = sprinklerCost(), money >= cost else { return }
        money -= cost
        sprinklerLevel += 1
        save()
    }

    let fertilizerCost = 150
    func buyFertilizer(_ qty: Int = 1) {
        let total = fertilizerCost * qty
        guard money >= total else { return }
        money -= total
        fertilizer += qty
        save()
    }

    let autoHarvesterCost = 5000
    func buyAutoHarvester() {
        guard !autoHarvesterUnlocked, money >= autoHarvesterCost else { return }
        money -= autoHarvesterCost
        autoHarvesterUnlocked = true
        autoHarvestEnabled = true
        save()
    }

    // MARK: Persistence

    func save() {
        let snapshot = GardenSave(
            money: money,
            seeds: seeds,
            unlockedPlots: unlockedPlots,
            plots: plots.map { PlotSave(cropID: $0.cropID, plantedAt: $0.plantedAt, fertilized: $0.fertilized) },
            backpack: backpack,
            lifetimeEarned: lifetimeEarned,
            sprinklerLevel: sprinklerLevel,
            fertilizer: fertilizer,
            autoHarvesterUnlocked: autoHarvesterUnlocked,
            autoHarvestEnabled: autoHarvestEnabled
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
        sprinklerLevel = s.sprinklerLevel
        fertilizer = s.fertilizer
        autoHarvesterUnlocked = s.autoHarvesterUnlocked
        autoHarvestEnabled = s.autoHarvestEnabled
        plots = (0..<Self.maxPlots).map { i in
            if i < s.plots.count {
                return Plot(id: i, cropID: s.plots[i].cropID, plantedAt: s.plots[i].plantedAt, fertilized: s.plots[i].fertilized)
            }
            return Plot(id: i, cropID: nil, plantedAt: nil)
        }
        return true
    }
}
