import SwiftUI

// Shared UI vocabulary: one place for the colours, plates and buttons the
// menus are built from.

enum Theme {
    static let bg = Color(hex: "#0B1220")
    static let panel = Color(hex: "#16202F")
    static let panelHi = Color(hex: "#1E2B3E")
    static let line = Color.white.opacity(0.10)
    static let text = Color(hex: "#EAF0FA")
    static let muted = Color(hex: "#8D9AB2")
    static let accent = Color(hex: "#FF5D3B")
    static let gold = Color(hex: "#F5C842")
    static let cyan = Color(hex: "#39C6F0")
    static let green = Color(hex: "#4ADE80")
    static let red = Color(hex: "#FF5D73")

    static let skyTop = Color(hex: "#1CA8DC")
    static let skyBottom = Color(hex: "#0E5C85")

    /// The rider's jersey colour, as a hex string for the SceneKit stage.
    static let jerseyHex = "#2E6BFF"

    static func medalColor(_ m: Int) -> Color {
        switch m {
        case 3: return gold
        case 2: return Color(hex: "#CBD5E1")
        case 1: return Color(hex: "#C97B3C")
        default: return Color.white.opacity(0.18)
        }
    }
}

/// The angled menu background used across the career and garage screens.
struct MenuBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.skyTop, Theme.skyBottom],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                Canvas { ctx, size in
                    // Low-poly facets — cheap, and it keeps the menus from
                    // reading as a flat gradient.
                    let cols = 7, rows = 5
                    for r in 0..<rows {
                        for c in 0..<cols {
                            let w = size.width / CGFloat(cols)
                            let h = size.height / CGFloat(rows)
                            let x = CGFloat(c) * w, y = CGFloat(r) * h
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: y))
                            path.addLine(to: CGPoint(x: x + w, y: y + h * 0.25))
                            path.addLine(to: CGPoint(x: x + w, y: y + h))
                            path.addLine(to: CGPoint(x: x, y: y + h * 0.75))
                            path.closeSubpath()
                            let shade = Double((r * cols + c) % 5) * 0.012
                            ctx.fill(path, with: .color(Color.white.opacity(0.02 + shade)))
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.gold
    var textColor: Color = Color(hex: "#141A26")
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.select()
            action()
        }) {
            HStack(spacing: 6) {
                if let s = systemImage { Image(systemName: s) }
                Text(title).fontWeight(.heavy)
            }
            .font(.system(size: 15))
            .foregroundColor(textColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CurrencyChip: View {
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.system(size: 13, weight: .black))
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Image(systemName: "plus.square.fill")
                .foregroundColor(Theme.gold)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LevelRing: View {
    let level: Int
    let progress: Double

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.4))
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(Theme.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "helmet.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.9))
            Text("\(level)")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 5)
                .background(Capsule().fill(Theme.green))
                .offset(y: 20)
        }
        .frame(width: 46, height: 46)
    }
}

struct IconTile: View {
    let system: String
    var badge: String? = nil
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.select()
            action()
        }) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(hex: "#123246"))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.18)))
                    .frame(width: 46, height: 40)
                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 46, height: 40)
                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold))
                        .offset(x: 4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
