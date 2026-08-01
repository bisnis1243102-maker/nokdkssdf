import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameModel()
    @State private var showMenu = false

    var body: some View {
        ZStack {
            GameSceneView(model: model)
                .ignoresSafeArea()

            hud
            controls

            if let r = model.result {
                resultCard(r)
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $showMenu) {
            MenuView(model: model)
        }
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                // Location / time / weather.
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.area.uppercased())
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .kerning(1.4)
                    HStack(spacing: 8) {
                        Text(model.clockText)
                        Text("•")
                        Text(model.weatherText)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.75)

                    if model.heat > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<model.heat, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(red: 1, green: 0.75, blue: 0.2))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .foregroundColor(.white)
                .shadow(radius: 4)

                Spacer()

                // Cash + menu.
                VStack(alignment: .trailing, spacing: 6) {
                    Text("$\(model.cash)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 1, blue: 0.7))
                        .shadow(radius: 4)

                    Button { showMenu = true } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 32)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Objective banner.
            if model.activeMission != nil {
                objectiveBanner
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
            } else if model.nearMissionStart, let id = model.offeredMissionID,
                      let m = Campaign.mission(id) {
                Text("Stop in the marker to start “\(m.title)”")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
            }

            Spacer()

            HStack(alignment: .bottom) {
                MiniMap(model: model)
                Spacer()
                speedo
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 96)
        }
        .allowsHitTesting(true)
    }

    private var objectiveBanner: some View {
        HStack(spacing: 10) {
            // Waypoint arrow, rotated into the player's frame of reference.
            if model.hasWaypoint {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0.25))
                    .rotationEffect(.radians(Double(model.waypointAngle)))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.objectiveText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                if model.hasWaypoint {
                    Text("\(Int(model.waypointDistance)) m")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
            }
            .foregroundColor(.white)

            if let t = model.objectiveTimer {
                Spacer()
                Text(String(format: "%.0f", max(0, t)))
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundColor(t < 10 ? .red : .white)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 340, alignment: .leading)
    }

    private var speedo: some View {
        VStack(spacing: -2) {
            Text("\(model.speedKmh)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text("KM/H")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .kerning(2)
                .foregroundColor(.white.opacity(0.6))
        }
        .shadow(radius: 6)
        .opacity(model.mode == .driving ? 1 : 0.25)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            Stick(model: model)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    model.enterExitRequested = true
                } label: {
                    Label(model.mode == .driving ? "Get out" : "Get in",
                          systemImage: model.mode == .driving ? "figure.walk" : "car.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .opacity(model.mode == .driving || model.canEnterCar ? 1 : 0.35)
                .disabled(model.mode == .onFoot && !model.canEnterCar)

                if model.mode == .driving {
                    HStack(spacing: 14) {
                        Pedal(symbol: "arrow.down", tint: .red) { pressed in
                            model.throttle = pressed ? -1 : 0
                        }
                        Pedal(symbol: "arrow.up", tint: .green) { pressed in
                            model.throttle = pressed ? 1 : 0
                        }
                    }
                    Pedal(symbol: "hand.raised.fill", tint: .orange, size: 54) { pressed in
                        model.handbrake = pressed
                    }
                }
            }
            .padding(.trailing, 26)
            .padding(.bottom, 24)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Result card

    private func resultCard(_ r: GameModel.MissionResult) -> some View {
        VStack(spacing: 10) {
            Text(r.success ? "MISSION PASSED" : "MISSION FAILED")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .kerning(2)
                .foregroundColor(r.success ? Color(red: 0.5, green: 1, blue: 0.7) : .red)
            Text(r.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(r.reason)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            if r.payout > 0 {
                Text("+$\(r.payout)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 1, blue: 0.7))
            }
            Button("Continue") {
                model.result = nil
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 28).padding(.vertical, 10)
            .background(Color.white, in: Capsule())
            .padding(.top, 4)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 30)
    }
}

// MARK: - Analogue stick
//
// Steers when driving, walks when on foot. Absolute-position style: the knob
// tracks your thumb inside the ring, and snaps back on release.

private struct Stick: View {
    @ObservedObject var model: GameModel
    @State private var knob: CGSize = .zero

    private let radius: CGFloat = 62

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            Circle()
                .fill(.white.opacity(0.75))
                .frame(width: 46, height: 46)
                .offset(knob)
                .shadow(radius: 6)
        }
        .frame(width: radius * 2, height: radius * 2)
        // The gesture must sit directly on the framed circle: padding applied
        // first would shift the local coordinates the knob is derived from.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    var dx = g.location.x - radius
                    var dy = g.location.y - radius
                    let len = sqrt(dx * dx + dy * dy)
                    let maxLen = radius - 22
                    if len > maxLen {
                        dx = dx / len * maxLen
                        dy = dy / len * maxLen
                    }
                    knob = CGSize(width: dx, height: dy)
                    let nx = Float(dx / maxLen)
                    let ny = Float(-dy / maxLen)
                    if model.mode == .driving {
                        model.steer = nx
                    } else {
                        model.walkX = nx
                        model.walkZ = ny
                    }
                }
                .onEnded { _ in
                    knob = .zero
                    model.steer = 0
                    model.walkX = 0
                    model.walkZ = 0
                }
        )
        .padding(.leading, 26)
        .padding(.bottom, 24)
    }
}

// MARK: - Hold-to-press pedal

private struct Pedal: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 66
    let onChange: (Bool) -> Void

    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(tint.opacity(pressed ? 0.9 : 0.35), lineWidth: 2))
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 0.93 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true; onChange(true) }
                }
                .onEnded { _ in
                    pressed = false
                    onChange(false)
                }
        )
    }
}

// MARK: - Minimap

private struct MiniMap: View {
    @ObservedObject var model: GameModel
    private let size: CGFloat = 108

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)

            // Road grid.
            Canvas { ctx, s in
                let scale = s.width / CGFloat(CityWorld.half * 2)
                var path = Path()
                for a in CityWorld.avenues {
                    let p = (CGFloat(a) + CGFloat(CityWorld.half)) * scale
                    path.move(to: CGPoint(x: p, y: 0))
                    path.addLine(to: CGPoint(x: p, y: s.height))
                    path.move(to: CGPoint(x: 0, y: p))
                    path.addLine(to: CGPoint(x: s.width, y: p))
                }
                ctx.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 1)
            }
            .padding(6)

            // Player.
            GeometryReader { geo in
                let scale = geo.size.width / CGFloat(CityWorld.half * 2)
                let x = (CGFloat(model.playerX) + CGFloat(CityWorld.half)) * scale
                let y = (CGFloat(model.playerZ) + CGFloat(CityWorld.half)) * scale
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
                    .rotationEffect(.radians(Double(model.heading)))
                    .position(x: x, y: y)

                if model.hasWaypoint {
                    // Waypoint plotted from the player's own bearing to it.
                    let ang = Double(model.waypointAngle + model.heading)
                    let d = CGFloat(model.waypointDistance) * scale
                    Circle()
                        .fill(Color(red: 1, green: 0.84, blue: 0.25))
                        .frame(width: 6, height: 6)
                        .position(x: x + sin(ang) * d, y: y + cos(ang) * d)
                }
            }
            .padding(6)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Menu (missions + settings)

private struct MenuView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Jobs") {
                    ForEach(Campaign.missions) { m in
                        missionRow(m)
                    }
                }

                Section("Graphics") {
                    Picker("Quality", selection: $model.quality) {
                        ForEach(GraphicsQuality.allCases) { q in
                            Text(q.label).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(model.quality.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if model.activeMission != nil {
                        Button("Abandon current job", role: .destructive) {
                            model.abandonMissionRequested = true
                            dismiss()
                        }
                    }
                    Button("Reset progress", role: .destructive) {
                        model.resetProgress()
                    }
                }
            }
            .navigationTitle("Neon Reign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func missionRow(_ m: Mission) -> some View {
        let done = model.missionsCompleted.contains(m.id)
        let unlocked = done || model.nextMission?.id == m.id

        return Button {
            guard unlocked else { return }
            model.startMissionRequested = m.id
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill"
                      : (unlocked ? "play.circle.fill" : "lock.fill"))
                    .foregroundStyle(done ? .green : (unlocked ? .yellow : .secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.headline)
                    Text(unlocked ? m.brief : "Locked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("$\(m.payout)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!unlocked)
    }
}
