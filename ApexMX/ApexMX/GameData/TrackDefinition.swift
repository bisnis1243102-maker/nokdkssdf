import Foundation

/// A designed track feature. Tracks are authored as an ordered list of these
/// rather than as raw height data, so a track is a few dozen bytes, is readable
/// in a diff, and can be retuned without regenerating art.
public enum TrackFeature: Codable, Sendable, Equatable {
    /// Flat or gently graded ground.
    case straight(length: Double, grade: Double)
    /// A jump with a takeoff ramp, a flat deck and a downslope landing.
    case tabletop(length: Double, height: Double, lipSharpness: Double)
    /// Takeoff and landing separated by a gap. Requires committed speed.
    case gap(takeoffLength: Double, gapLength: Double, landingLength: Double, height: Double)
    /// A run of evenly spaced bumps that must be skimmed or absorbed.
    case whoops(count: Int, spacing: Double, amplitude: Double)
    /// A rolling series of jumps at a fixed rhythm.
    case rhythm(count: Int, spacing: Double, amplitude: Double)
    /// A banked turn, modelled in 2D as a rise-and-fall that scrubs speed if
    /// entered too hot.
    case berm(length: Double, height: Double)
    /// Broken, high-grip ground that punishes a stiff suspension setup.
    case rockGarden(length: Double, roughness: Double)
    /// A sustained climb or descent.
    case elevation(length: Double, rise: Double)
    /// A step up or step down between two levels.
    case stepUp(length: Double, rise: Double)

    /// Horizontal distance the feature occupies.
    public var length: Double {
        switch self {
        case let .straight(length, _): return length
        case let .tabletop(length, _, _): return length
        case let .gap(takeoff, gap, landing, _): return takeoff + gap + landing
        case let .whoops(count, spacing, _): return Double(count) * spacing
        case let .rhythm(count, spacing, _): return Double(count) * spacing
        case let .berm(length, _): return length
        case let .rockGarden(length, _): return length
        case let .elevation(length, _): return length
        case let .stepUp(length, _): return length
        }
    }
}

/// Weather affects lighting, particles and — through the surface — grip.
public enum WeatherPreset: String, Codable, CaseIterable, Sendable {
    case sunny, cloudy, overcast, rain, storm, fog

    /// Multiplier applied to every surface's grip.
    public var gripMultiplier: Double {
        switch self {
        case .sunny: return 1.00
        case .cloudy: return 0.99
        case .overcast: return 0.97
        case .rain: return 0.86
        case .storm: return 0.79
        case .fog: return 0.94
        }
    }

    public var displayName: String {
        switch self {
        case .sunny: return "Sunny"
        case .cloudy: return "Partly Cloudy"
        case .overcast: return "Overcast"
        case .rain: return "Rain"
        case .storm: return "Storm"
        case .fog: return "Fog"
        }
    }
}

/// Time of day, driving the sky gradient and light direction.
public enum TimeOfDay: String, Codable, CaseIterable, Sendable {
    case sunrise, morning, midday, afternoon, goldenHour, sunset, night

    public var displayName: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .morning: return "Morning"
        case .midday: return "Midday"
        case .afternoon: return "Afternoon"
        case .goldenHour: return "Golden Hour"
        case .sunset: return "Sunset"
        case .night: return "Night"
        }
    }
}

/// A complete, self-contained track.
public struct TrackDefinition: Codable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var location: String
    public var difficulty: Int          // 1...5
    public var laps: Int
    public var baseSurface: SurfaceType
    public var weather: WeatherPreset
    public var timeOfDay: TimeOfDay
    /// Seed for the deterministic micro-detail applied on top of the features.
    public var seed: UInt64
    public var features: [TrackFeature]
    /// Target time in seconds for a gold medal, per lap.
    public var goldLapTime: Double

    public init(id: String,
                displayName: String,
                location: String,
                difficulty: Int,
                laps: Int,
                baseSurface: SurfaceType,
                weather: WeatherPreset,
                timeOfDay: TimeOfDay,
                seed: UInt64,
                features: [TrackFeature],
                goldLapTime: Double) {
        self.id = id
        self.displayName = displayName
        self.location = location
        self.difficulty = difficulty
        self.laps = laps
        self.baseSurface = baseSurface
        self.weather = weather
        self.timeOfDay = timeOfDay
        self.seed = seed
        self.features = features
        self.goldLapTime = goldLapTime
    }

    /// Total lap distance in metres.
    public var lapLength: Double {
        features.reduce(0) { $0 + $1.length }
    }

    public var difficultyLabel: String {
        switch difficulty {
        case ...1: return "Novice"
        case 2: return "Intermediate"
        case 3: return "Advanced"
        case 4: return "Expert"
        default: return "Pro"
        }
    }
}
