import SwiftUI

struct MenuView: View {
    @StateObject private var store = GameStore()
    @State private var selected: Track?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.skyTop, Palette.skyBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    ForEach(Track.all) { track in
                        row(for: track)
                    }
                }
                .padding(20)
            }
        }
        .fullScreenCover(item: $selected) { track in
            RaceView(track: track, store: store)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("TRACK RUSH")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Palette.accent, .orange],
                                   startPoint: .top, endPoint: .bottom)
                )
            Text("Throttle, brake, lean. Don't land on your head.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private func row(for track: Track) -> some View {
        let unlocked = store.isUnlocked(track)
        return Button {
            guard unlocked else { return }
            selected = track
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(unlocked ? Palette.accent : Color.white.opacity(0.12))
                    if unlocked {
                        Text("\(track.id + 1)")
                            .font(.system(size: 19, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                    } else {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white.opacity(unlocked ? 0.95 : 0.45))
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { index in
                            Image(systemName: index < track.difficultyStars ? "flame.fill" : "flame")
                                .font(.system(size: 9))
                                .foregroundColor(index < track.difficultyStars
                                                 ? .orange.opacity(unlocked ? 0.95 : 0.35)
                                                 : .white.opacity(0.18))
                        }
                        Text("· \(Int(track.length / 100))0 m")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.45))
                    }
                }

                Spacer()

                if let best = store.best(for: track) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("BEST").font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                        Text(GameStore.timeText(best))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(Palette.accent)
                    }
                } else if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(unlocked ? 0.28 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}

enum Palette {
    static let skyTop = Color(red: 0.11, green: 0.15, blue: 0.26)
    static let skyBottom = Color(red: 0.29, green: 0.35, blue: 0.48)
    static let accent = Color(red: 0.99, green: 0.79, blue: 0.24)
}
