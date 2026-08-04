import SwiftUI

struct GarageView: View {
    @EnvironmentObject var game: GameState
    @State private var toast: String = ""

    var body: some View {
        ZStack {
            MenuBackground()
            VStack(spacing: 10) {
                HStack {
                    PillButton(title: "Back", systemImage: "chevron.left",
                               tint: Theme.panelHi, textColor: .white) {
                        game.screen = .career
                    }
                    Spacer()
                    Text("GARAGE")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    CurrencyChip(icon: "circle.fill", value: "\(game.profile.coins)", tint: Theme.gold)
                }

                HStack(spacing: 12) {
                    ShowcaseView(content: .bike(bikeId: game.profile.currentBike,
                                                tint: game.currentSpec.color,
                                                withRider: false))
                        .frame(width: 240, height: 140)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.currentSpec.name)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(game.currentSpec.blurb)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("POWER")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(game.currentPower)")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(Theme.gold)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("UPGRADES")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white.opacity(0.7))
                        ForEach(UpgradeLine.all) { line in
                            upgradeRow(line)
                        }

                        Text("BIKES")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 6)
                        ForEach(BikeSpec.all) { spec in
                            bikeRow(spec)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(14)

            if !toast.isEmpty {
                VStack {
                    Text(toast)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
    }

    private func upgradeRow(_ line: UpgradeLine) -> some View {
        let lvl = game.currentUpgrades[line.id] ?? 0
        let cost = game.upgradeCost(line)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.name)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                Text(line.effect)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                HStack(spacing: 4) {
                    ForEach(0..<line.maxLevel, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i < lvl ? Theme.accent : Color.white.opacity(0.16))
                            .frame(width: 22, height: 6)
                    }
                }
            }
            Spacer()
            if lvl >= line.maxLevel {
                Text("MAX")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Theme.green)
            } else {
                PillButton(title: "\(cost)", systemImage: "circle.fill") {
                    if game.buyUpgrade(line) { flash("\(line.name) → \(lvl + 1)") }
                    else { flash("Not enough coins") }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32)))
    }

    private func bikeRow(_ spec: BikeSpec) -> some View {
        let owned = game.profile.bikes.contains(spec.id)
        let selected = game.profile.currentBike == spec.id
        let locked = game.profile.level < spec.unlockLevel
        return HStack(spacing: 10) {
            ShowcaseView(content: .bike(bikeId: spec.id, tint: spec.color, withRider: false),
                         spins: false)
                .frame(width: 76, height: 48)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                Text("\(spec.cls) · power \(spec.rating)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
            }
            Spacer()
            if owned {
                PillButton(title: selected ? "Selected" : "Select",
                           tint: selected ? Theme.panelHi : Theme.gold,
                           textColor: selected ? .white : .black) {
                    game.selectBike(spec)
                }
            } else if locked {
                Text("Level \(spec.unlockLevel)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white.opacity(0.6))
            } else {
                PillButton(title: "\(spec.price)", systemImage: "circle.fill") {
                    if game.buyBike(spec) { flash("\(spec.name) unlocked") }
                    else { flash("Not enough coins") }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(selected ? Theme.accent.opacity(0.18) : Color.black.opacity(0.32)))
    }

    private func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if toast == text { toast = "" }
        }
    }
}

struct RiderView: View {
    @EnvironmentObject var game: GameState
    @State private var name: String = ""
    @State private var number: String = ""

    var body: some View {
        ZStack {
            MenuBackground()
            VStack(spacing: 14) {
                HStack {
                    PillButton(title: "Back", systemImage: "chevron.left",
                               tint: Theme.panelHi, textColor: .white) { game.screen = .career }
                    Spacer()
                    Text("RIDER").font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 80, height: 1)
                }

                HStack(spacing: 20) {
                    ShowcaseView(content: .rider(tint: Theme.jerseyHex))
                        .frame(width: 150, height: 210)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NAME").font(.system(size: 10, weight: .black))
                                .foregroundColor(.white.opacity(0.7))
                            TextField("Rider", text: $name)
                                .textFieldStyle(.plain)
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
                                .foregroundColor(.white)
                                .frame(width: 200)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NUMBER").font(.system(size: 10, weight: .black))
                                .foregroundColor(.white.opacity(0.7))
                            TextField("482", text: $number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.plain)
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
                                .foregroundColor(.white)
                                .frame(width: 110)
                        }
                        PillButton(title: "Save") {
                            game.profile.name = name.isEmpty ? "You" : String(name.prefix(14))
                            game.profile.number = max(1, min(999, Int(number) ?? 482))
                            game.save()
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        statLine("Races", "\(game.profile.races)")
                        statLine("Wins", "\(game.profile.wins)")
                        statLine("Perfect landings", "\(game.profile.perfects)")
                        statLine("Crashes", "\(game.profile.crashes)")
                        statLine("Air time", String(format: "%.0fs", game.profile.airtime))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32)))
                }
                Spacer()
            }
            .padding(16)
        }
        .onAppear {
            name = game.profile.name
            number = "\(game.profile.number)"
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
            Spacer(minLength: 18)
            Text(value).font(.system(size: 13, weight: .heavy)).foregroundColor(.white)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var game: GameState
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            MenuBackground()
            VStack(spacing: 14) {
                HStack {
                    PillButton(title: "Back", systemImage: "chevron.left",
                               tint: Theme.panelHi, textColor: .white) { game.screen = .career }
                    Spacer()
                    Text("SETTINGS").font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 80, height: 1)
                }

                VStack(spacing: 10) {
                    toggleRow("Haptics", isOn: Binding(
                        get: { game.profile.hapticsOn },
                        set: { game.profile.hapticsOn = $0; Haptics.enabled = $0; game.save() }))
                    toggleRow("Landing assist", isOn: Binding(
                        get: { game.profile.assistLanding },
                        set: { game.profile.assistLanding = $0; game.save() }),
                              note: "Blends a corrective lean into your input in the air. Never adds grip.")
                    HStack {
                        Text("Reset progress")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.white)
                        Spacer()
                        PillButton(title: confirmReset ? "Tap to confirm" : "Reset",
                                   tint: Theme.red, textColor: .white) {
                            if confirmReset {
                                game.profile = Profile()
                                game.rollDailyGoal()
                                game.save()
                                confirmReset = false
                            } else {
                                confirmReset = true
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32)))
                }

                Text("Original game — no third-party assets, tracks or branding.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            .padding(16)
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: isOn) {
                Text(label).font(.system(size: 14, weight: .heavy)).foregroundColor(.white)
            }
            .tint(Theme.accent)
            if let n = note {
                Text(n).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32)))
    }
}
