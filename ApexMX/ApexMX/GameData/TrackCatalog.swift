import Foundation

/// The shipping track list.
///
/// Each track is a hand-authored sequence of features, so its personality is
/// deliberate: Ridgeline teaches rhythm, Copper Flats punishes a lazy throttle
/// in deep sand, Ironworks is a technical rock-and-timber course, and Summit
/// Ridge is the open-class finale.
public enum TrackCatalog {

    public static let ridgelinePark = TrackDefinition(
        id: "ridgeline_park",
        displayName: "Ridgeline Park",
        location: "Pine Hollow",
        difficulty: 1,
        laps: 2,
        baseSurface: .hardDirt,
        weather: .sunny,
        timeOfDay: .morning,
        seed: 0x5EED_0001,
        features: [
            .straight(length: 34, grade: 0.00),
            .tabletop(length: 26, height: 2.4, lipSharpness: 0.35),
            .straight(length: 20, grade: 0.00),
            .rhythm(count: 4, spacing: 11, amplitude: 1.5),
            .straight(length: 18, grade: 0.02),
            .berm(length: 16, height: 1.2),
            .tabletop(length: 30, height: 3.1, lipSharpness: 0.45),
            .straight(length: 22, grade: -0.02),
            .whoops(count: 7, spacing: 4.2, amplitude: 0.55),
            .straight(length: 26, grade: 0.00),
            .tabletop(length: 24, height: 2.0, lipSharpness: 0.30),
            .straight(length: 40, grade: 0.00)
        ],
        goldLapTime: 41.0
    )

    public static let copperFlats = TrackDefinition(
        id: "copper_flats",
        displayName: "Copper Flats",
        location: "Basin Reserve",
        difficulty: 2,
        laps: 3,
        baseSurface: .sand,
        weather: .sunny,
        timeOfDay: .afternoon,
        seed: 0x5EED_0002,
        features: [
            .straight(length: 30, grade: 0.00),
            .whoops(count: 9, spacing: 4.6, amplitude: 0.72),
            .straight(length: 16, grade: 0.03),
            .stepUp(length: 18, rise: 3.2),
            .straight(length: 14, grade: 0.00),
            .gap(takeoffLength: 12, gapLength: 14, landingLength: 18, height: 3.4),
            .elevation(length: 24, rise: -3.2),
            .berm(length: 18, height: 1.5),
            .rhythm(count: 5, spacing: 12, amplitude: 1.8),
            .straight(length: 20, grade: 0.00),
            .tabletop(length: 32, height: 3.6, lipSharpness: 0.55),
            .whoops(count: 6, spacing: 4.0, amplitude: 0.60),
            .straight(length: 34, grade: 0.00)
        ],
        goldLapTime: 58.0
    )

    public static let ironworks = TrackDefinition(
        id: "ironworks",
        displayName: "Ironworks",
        location: "Foundry District",
        difficulty: 3,
        laps: 3,
        baseSurface: .softDirt,
        weather: .overcast,
        timeOfDay: .goldenHour,
        seed: 0x5EED_0003,
        features: [
            .straight(length: 28, grade: 0.00),
            .tabletop(length: 22, height: 2.2, lipSharpness: 0.60),
            .rockGarden(length: 20, roughness: 0.42),
            .straight(length: 14, grade: 0.04),
            .gap(takeoffLength: 11, gapLength: 16, landingLength: 16, height: 3.8),
            .berm(length: 15, height: 1.4),
            .rhythm(count: 6, spacing: 10, amplitude: 1.9),
            .elevation(length: 26, rise: 4.5),
            .straight(length: 16, grade: 0.00),
            .stepUp(length: 14, rise: -4.5),
            .rockGarden(length: 16, roughness: 0.36),
            .whoops(count: 8, spacing: 3.9, amplitude: 0.68),
            .tabletop(length: 28, height: 3.0, lipSharpness: 0.50),
            .straight(length: 32, grade: 0.00)
        ],
        goldLapTime: 66.0
    )

    public static let summitRidge = TrackDefinition(
        id: "summit_ridge",
        displayName: "Summit Ridge",
        location: "Alpine Circuit",
        difficulty: 5,
        laps: 3,
        baseSurface: .hardDirt,
        weather: .cloudy,
        timeOfDay: .sunset,
        seed: 0x5EED_0004,
        features: [
            .straight(length: 26, grade: 0.00),
            .gap(takeoffLength: 12, gapLength: 18, landingLength: 18, height: 4.2),
            .straight(length: 12, grade: 0.00),
            .rhythm(count: 7, spacing: 10.5, amplitude: 2.1),
            .elevation(length: 30, rise: 6.0),
            .rockGarden(length: 18, roughness: 0.48),
            .berm(length: 16, height: 1.6),
            .gap(takeoffLength: 13, gapLength: 20, landingLength: 20, height: 4.6),
            .elevation(length: 34, rise: -6.0),
            .whoops(count: 10, spacing: 4.1, amplitude: 0.78),
            .straight(length: 14, grade: 0.00),
            .tabletop(length: 34, height: 4.0, lipSharpness: 0.65),
            .rhythm(count: 4, spacing: 11, amplitude: 1.7),
            .straight(length: 36, grade: 0.00)
        ],
        goldLapTime: 84.0
    )

    public static let builtIn: [TrackDefinition] = [ridgelinePark, copperFlats, ironworks, summitRidge]

    /// Loads the track list, preferring bundled JSON over the built-in defaults
    /// so that new courses can ship as content rather than as a binary update.
    public static func load(from bundle: Bundle = .main) -> [TrackDefinition] {
        guard let url = bundle.url(forResource: "Tracks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tracks = try? JSONDecoder().decode([TrackDefinition].self, from: data),
              !tracks.isEmpty else {
            return builtIn
        }
        return tracks
    }

    public static func track(withID id: String, in list: [TrackDefinition] = builtIn) -> TrackDefinition {
        list.first { $0.id == id } ?? ridgelinePark
    }
}
