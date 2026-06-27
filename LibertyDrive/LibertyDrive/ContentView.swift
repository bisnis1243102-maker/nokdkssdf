import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = DriveModel()

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

            if model.busted {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    Text("BUSTED")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.red)
                        .shadow(radius: 8)
                }
                .transition(.opacity)
            }

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
        .animation(.easeInOut, value: model.busted)
        .animation(.easeInOut, value: model.raceFinished)
    }

    // MARK: HUD

    private var topHUD: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.district.uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                Text("\(model.distanceM) m driven")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.3)))
                if model.stars > 0 {
                    HStack(spacing: 3) {
                        ForEach(0..<model.stars, id: \.self) { _ in
                            Image(systemName: "star.fill")
                        }
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.3)))
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
            // Steering
            HStack(spacing: 14) {
                PedalButton(symbol: "arrowtriangle.left.fill", tint: .blue) { down in
                    model.steer = down ? -1 : 0
                }
                PedalButton(symbol: "arrowtriangle.right.fill", tint: .blue) { down in
                    model.steer = down ? 1 : 0
                }
            }
            Spacer()
            stealButton
            Spacer()
            // Throttle / brake
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

    private var stealButton: some View {
        Button {
            model.stealRequested = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "hand.raised.fill").font(.system(size: 20, weight: .bold))
                Text("STEAL").font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(width: 76, height: 76)
            .background(Circle().fill(Color.orange.opacity(0.85)))
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
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
                    .onChanged { _ in
                        if !pressed { pressed = true; onChange(true) }
                    }
                    .onEnded { _ in
                        pressed = false; onChange(false)
                    }
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
                // 3x3 district grid (row 0 = north = top).
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

                // Player dot.
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

#Preview {
    ContentView()
}
