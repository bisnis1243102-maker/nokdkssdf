import Foundation

/// One step of a mission. The scene drives every objective through the same
/// small set of kinds, so adding a mission is pure data.
enum Objective {
    /// Reach a point in any way you like.
    case goTo(place: String, hint: String)
    /// Reach a point before the clock runs out.
    case goToTimed(place: String, seconds: Double, hint: String)
    /// Leave the car and reach a point on foot.
    case onFootTo(place: String, hint: String)
    /// Stay inside the radius of a point for a while.
    case waitAt(place: String, seconds: Double, hint: String)
    /// Keep a moving target within range without touching it.
    case tail(place: String, seconds: Double, hint: String)
    /// Catch and ram a fleeing car.
    case ram(place: String, hint: String)
    /// Shake the police; heat must fall to zero.
    case loseCops(hint: String)

    var hint: String {
        switch self {
        case .goTo(_, let h), .goToTimed(_, _, let h), .onFootTo(_, let h),
             .waitAt(_, _, let h), .tail(_, _, let h), .ram(_, let h), .loseCops(let h):
            return h
        }
    }

    /// Destination for the waypoint arrow, when the objective has a fixed one.
    var place: String? {
        switch self {
        case .goTo(let p, _), .goToTimed(let p, _, _), .onFootTo(let p, _),
             .waitAt(let p, _, _), .tail(let p, _, _), .ram(let p, _):
            return p
        case .loseCops:
            return nil
        }
    }

    /// Countdown attached to this objective, if any.
    var timeLimit: Double? {
        switch self {
        case .goToTimed(_, let s, _), .waitAt(_, let s, _), .tail(_, let s, _): return s
        default: return nil
        }
    }

    /// Objectives you must be out of the car for.
    var requiresOnFoot: Bool {
        if case .onFootTo = self { return true }
        return false
    }

    /// Objectives that put the police on you the moment they begin.
    var raisesHeat: Int {
        switch self {
        case .ram: return 2
        case .loseCops: return 3
        default: return 0
        }
    }
}

struct Mission: Identifiable {
    let id: Int
    let title: String
    let brief: String
    let payout: Int
    let objectives: [Objective]
    /// Where the glowing start marker sits in free roam.
    let startPlace: String
}

enum Campaign {

    static let missions: [Mission] = [
        Mission(id: 0,
                title: "Cold Start",
                brief: "Your cousin left a car at the lockup and a favour to collect. Get moving.",
                payout: 400,
                objectives: [
                    .goTo(place: "Pier 9", hint: "Drive down to Pier 9"),
                    .waitAt(place: "Pier 9", seconds: 5, hint: "Hold here while he loads up"),
                ],
                startPlace: "Your lockup"),

        Mission(id: 1,
                title: "Short Fuse",
                brief: "A crate needs to be across town before anyone notices it moved.",
                payout: 900,
                objectives: [
                    .goToTimed(place: "Glasshouse Mall", seconds: 75,
                               hint: "Deliver to Glasshouse Mall before the clock dies"),
                ],
                startPlace: "Pier 9"),

        Mission(id: 2,
                title: "Walk-In",
                brief: "The handoff is inside. Cars don't fit through doors.",
                payout: 1_200,
                objectives: [
                    .goTo(place: "Lantern Row", hint: "Park up on Lantern Row"),
                    .onFootTo(place: "Lantern Row", hint: "Get out and walk to the marker"),
                    .waitAt(place: "Lantern Row", seconds: 6, hint: "Wait for the handoff"),
                ],
                startPlace: "Glasshouse Mall"),

        Mission(id: 3,
                title: "Heat",
                brief: "Somebody talked. Blue lights, and they're for you.",
                payout: 1_800,
                objectives: [
                    .loseCops(hint: "Lose the police"),
                    .goTo(place: "Your lockup", hint: "Get back to the lockup"),
                ],
                startPlace: "Lantern Row"),

        Mission(id: 4,
                title: "Long Shadow",
                brief: "Follow the courier. Close enough to see, far enough to keep breathing.",
                payout: 2_100,
                objectives: [
                    .tail(place: "Spire Plaza", seconds: 40,
                          hint: "Tail the courier — stay close, don't hit them"),
                ],
                startPlace: "Your lockup"),

        Mission(id: 5,
                title: "Hard Stop",
                brief: "Talking is over. Put the courier's car into a wall.",
                payout: 2_600,
                objectives: [
                    .ram(place: "Spire Plaza", hint: "Run the courier off the road"),
                    .loseCops(hint: "Lose the police"),
                ],
                startPlace: "Spire Plaza"),

        Mission(id: 6,
                title: "The Saltworks",
                brief: "In on foot, out on four wheels, and don't stop for anyone.",
                payout: 3_400,
                objectives: [
                    .goTo(place: "The Saltworks", hint: "Drive out to the Saltworks"),
                    .onFootTo(place: "The Saltworks", hint: "Go in on foot"),
                    .waitAt(place: "The Saltworks", seconds: 8, hint: "Crack the office"),
                    .loseCops(hint: "Get out and lose them"),
                ],
                startPlace: "The Saltworks"),

        Mission(id: 7,
                title: "Citywide",
                brief: "Every unit in the city has your plate. Run the whole map.",
                payout: 4_500,
                objectives: [
                    .goToTimed(place: "Ridgewater Bridge", seconds: 110,
                               hint: "Cross to Ridgewater Bridge"),
                    .loseCops(hint: "Shake them for good"),
                ],
                startPlace: "Cannery Yard"),

        Mission(id: 8,
                title: "Neon Reign",
                brief: "One last drive to the top of the hill, and the city is yours.",
                payout: 8_000,
                objectives: [
                    .goTo(place: "Vermillion Depot", hint: "Meet at the Vermillion Depot"),
                    .ram(place: "Marrow Heights", hint: "End it — take out the last car"),
                    .loseCops(hint: "Disappear"),
                    .goTo(place: "Spire Plaza", hint: "Spire Plaza. Take the city."),
                ],
                startPlace: "Cannery Yard"),
    ]

    static func mission(_ id: Int) -> Mission? {
        missions.first { $0.id == id }
    }
}
