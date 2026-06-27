import SwiftUI

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
        }
        .statusBarHidden(true)
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
            }
            .foregroundColor(.white)

            Spacer()

            VStack(spacing: 6) {
                MiniMap(model: model).frame(width: 96, height: 96)
                speedo
            }
        }
        .shadow(radius: 3)
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
