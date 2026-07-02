import Foundation
import CoreGraphics

/// A place the player has to reach.
struct Waypoint {
    let point: CGPoint
    let label: String
    var radius: CGFloat = 95
    /// When true, the waypoint only completes while driving the mission car.
    var needsMissionCar = false
}

/// One step of a mission, evaluated in order.
enum Objective {
    /// Reach a waypoint (on foot or driving).
    case reach(Waypoint)
    /// Hit every waypoint, in order, before the timer runs out.
    case reachTimed([Waypoint], seconds: TimeInterval)
    /// A specific car is parked at `at`; get in it. Destroying it fails the mission.
    case stealCar(at: CGPoint, kind: CarKind, hint: String)
    /// The heat is on: gain `stars` and stay alive for `seconds`.
    case survive(seconds: TimeInterval, stars: Int)
}

struct Mission {
    let title: String
    let giver: Protagonist
    let brief: String
    let objectives: [Objective]
    let reward: Int
}

/// The VI-mission story of Port Leon, alternating between the two leads.
enum Story {
    static func missions(in city: City) -> [Mission] {
        [
            Mission(
                title: "Shore Thing",
                giver: .mia,
                brief: "Mia: \"New town, same hustle. Grab any ride and meet my contact at the Palm Shores marina.\"",
                objectives: [
                    .reach(Waypoint(point: city.marina, label: "the marina")),
                ],
                reward: 200),

            Mission(
                title: "Special Delivery",
                giver: .jax,
                brief: "Jax: \"A crate came in at the docks. No questions. Run it to the safehouse in Casa Vieja.\"",
                objectives: [
                    .reach(Waypoint(point: city.airport, label: "the docks airstrip")),
                    .reach(Waypoint(point: city.hideout, label: "the safehouse")),
                ],
                reward: 350),

            Mission(
                title: "Hot Wheels",
                giver: .mia,
                brief: "Mia: \"A collector in Grove Heights parks his Vipera GT outside. It's ours now. Bring it to Rusty's garage — in one piece.\"",
                objectives: [
                    .stealCar(at: City.blockCenter(4, 8), kind: CarCatalog.sports,
                              hint: "the Vipera GT in Grove Heights"),
                    .reach(Waypoint(point: city.garage, label: "Rusty's garage",
                                    needsMissionCar: true)),
                ],
                reward: 500),

            Mission(
                title: "Rush Hour",
                giver: .jax,
                brief: "Jax: \"Three drops across town, one ticking clock. Drive like you mean it.\"",
                objectives: [
                    .reachTimed([
                        Waypoint(point: City.blockCenter(7, 3), label: "drop 1 — Ironside"),
                        Waypoint(point: City.blockCenter(8, 6), label: "drop 2 — Palm Shores"),
                        Waypoint(point: City.blockCenter(1, 6), label: "drop 3 — Casa Vieja"),
                    ], seconds: 95),
                ],
                reward: 650),

            Mission(
                title: "Withdrawal",
                giver: .mia,
                brief: "Mia: \"Leon Savings has been holding my money for years. Time for a withdrawal. Get to the bank, then lose the heat and get to the safehouse.\"",
                objectives: [
                    .reach(Waypoint(point: city.bank, label: "Leon Savings bank")),
                    .survive(seconds: 40, stars: 3),
                    .reach(Waypoint(point: city.hideout, label: "the safehouse")),
                ],
                reward: 1200),

            Mission(
                title: "Leon Departure",
                giver: .jax,
                brief: "Jax: \"Last job. Pick up the case on the Neon Mile, then burn rubber to the airstrip before the whole VCPD lands on us.\"",
                objectives: [
                    .reach(Waypoint(point: City.blockCenter(6, 5), label: "the case — Neon Mile")),
                    .survive(seconds: 30, stars: 2),
                    .reach(Waypoint(point: city.airport, label: "the airstrip")),
                ],
                reward: 2000),
        ]
    }
}
