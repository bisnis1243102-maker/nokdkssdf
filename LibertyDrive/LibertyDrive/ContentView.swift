import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = DriveModel()
    @State private var showGarage = false

    var body: some View {
        ZStack {
            CityScene(model: model)
                .ignoresSafeArea()

            VStack {
                topHUD
                Spacer()
                controls
            }
            .padding()

            if model.raceFinished {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 10) {
                        Text("🏁 FINISH!")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Time  \(timeString(model.lastTime))")
                            .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(.pink)
                        Text(model.lastTime <= model.bestTime ? "🏆 New Best!" : "Best  \(timeString(model.bestTime))")
                            .font(.headline).foregroundColor(.yellow)
                    }
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .animation(.easeInOut, value: model.raceFinished)
        .sheet(isPresented: $showGarage) { GarageView(model: model) }
    }

    // MARK: HUD

    private var topHUD: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.area.uppercased())
                        .font(.system(size: 18, weight: .black, design: .rounded))
                    Text(model.weather)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                HStack(spacing: 8) {
                    Text("💰 \(model.credits)")
                        .font(.caption.weight(.bold))
                    Button {
                        showGarage = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Garage", systemImage: "car.2.fill")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.indigo))
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.3)))

                Text("\(model.distanceM) m driven")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.3)))
                if model.driftScore > 0 {
                    HStack(spacing: 5) {
                        if model.drifting {
                            Text("DRIFT!").foregroundColor(.orange)
                        }
                        Text("\(model.driftScore) pts").foregroundColor(.white)
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .scaleEffect(model.drifting ? 1.08 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: model.drifting)
                }
            }
            .foregroundColor(.white)

            Spacer()
            raceCenter
            Spacer()

            VStack(spacing: 6) {
                MiniMap(model: model).frame(width: 96, height: 96)
                speedo
            }
        }
        .shadow(radius: 3)
    }

    @ViewBuilder
    private var raceCenter: some View {
        if model.racing {
            VStack(spacing: 6) {
                Text("CHECKPOINT \(min(model.cpIndex + 1, model.cpTotal))/\(model.cpTotal)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                Text(timeString(model.raceTime))
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                Image(systemName: "location.north.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.pink)
                    .rotationEffect(.radians(Double(model.arrowAngle)))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.35)))
        } else {
            Button {
                model.startRaceRequested = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "flag.checkered").font(.system(size: 22, weight: .bold))
                    Text("START RACE").font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Capsule().fill(LinearGradient(colors: [.purple, .pink],
                                                          startPoint: .leading, endPoint: .trailing)))
            }
        }
    }

    private func timeString(_ t: Double) -> String {
        let m = Int(t) / 60, s = Int(t) % 60, cs = Int((t - floor(t)) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }

    private var speedo: some View {
        HStack(spacing: 4) {
            Text("\(model.speedKmh)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .contentTransition(.numericText())
            Text("km/h").font(.caption2.weight(.bold)).padding(.top, 8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.35)))
    }

    // MARK: Controls

    private var controls: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 14) {
                PedalButton(symbol: "arrowtriangle.left.fill", tint: .blue) { down in
                    model.steer = down ? -1 : 0
                }
                PedalButton(symbol: "arrowtriangle.right.fill", tint: .blue) { down in
                    model.steer = down ? 1 : 0
                }
            }
            Spacer()
            VStack(spacing: 14) {
                PedalButton(symbol: "chevron.up", tint: .green, big: true) { down in
                    model.throttle = down ? 1 : 0
                }
                PedalButton(symbol: "chevron.down", tint: .red) { down in
                    model.throttle = down ? -1 : 0
                }
            }
        }
    }
}

// MARK: - Hold-to-press control

private struct PedalButton: View {
    let symbol: String
    let tint: Color
    var big: Bool = false
    let onChange: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        let size: CGFloat = big ? 92 : 76
        Image(systemName: symbol)
            .font(.system(size: big ? 34 : 26, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(pressed ? 0.95 : 0.65)))
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
            .scaleEffect(pressed ? 0.93 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true; onChange(true) } }
                    .onEnded { _ in pressed = false; onChange(false) }
            )
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

// MARK: - Minimap

private struct MiniMap: View {
    @ObservedObject var model: DriveModel

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                VStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<3, id: \.self) { col in
                                Color(uiColor: World.districts[row * 3 + col].color)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Circle().fill(.white)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
                    .position(
                        x: CGFloat((model.carX + World.half) / (World.half * 2)) * s,
                        y: CGFloat((model.carZ + World.half) / (World.half * 2)) * s)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.7), lineWidth: 2))
        }
    }
}

// MARK: - Garage

private struct GarageView: View {
    @ObservedObject var model: DriveModel
    @Environment(\.dismiss) private var dismiss

    private let paints: [(Double, Double, Double)] = [
        (0.85, 0.13, 0.16), (0.95, 0.55, 0.10), (0.96, 0.82, 0.18),
        (0.20, 0.75, 0.35), (0.20, 0.55, 0.95), (0.55, 0.25, 0.85),
        (0.95, 0.35, 0.65), (0.95, 0.95, 0.97), (0.08, 0.09, 0.11)
    ]

    var body: some View {
        NavigationView {
            List {
                Section("Paint — \(model.selectedSpec.name)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<paints.count, id: \.self) { i in
                                let p = paints[i]
                                Circle()
                                    .fill(Color(red: p.0, green: p.1, blue: p.2))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                                    .onTapGesture { model.setPaint(p.0, p.1, p.2) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Cars") {
                    ForEach(CarShop.all) { spec in
                        carRow(spec)
                    }
                }
            }
            .navigationTitle("Garage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("💰 \(model.credits)").font(.headline) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func carRow(_ spec: CarSpec) -> some View {
        let owned = model.ownedCarIDs.contains(spec.id)
        let selected = model.selectedCarID == spec.id
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: spec.baseColor))
                .frame(width: 46, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.5)))
            VStack(alignment: .leading, spacing: 3) {
                Text(spec.name).font(.headline)
                Text(spec.category).font(.caption2).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    StatBar(label: "SPD", value: spec.topSpeed)
                    StatBar(label: "ACC", value: spec.accel)
                    StatBar(label: "HND", value: spec.handling)
                }
            }
            Spacer()
            if selected {
                Text("DRIVING").font(.caption.bold()).foregroundColor(.green)
            } else if owned {
                Button("Select") { model.selectCar(spec) }
                    .buttonStyle(.borderedProminent).tint(.blue)
            } else {
                Button("💰\(spec.price)") { model.buyCar(spec) }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(model.credits < spec.price)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatBar: View {
    let label: String
    let value: Float
    var body: some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 5)
                Capsule().fill(Color.orange).frame(width: 40 * CGFloat(value), height: 5)
            }
        }
    }
}

#Preview {
    ContentView()
}
