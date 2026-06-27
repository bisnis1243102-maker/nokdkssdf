import UIKit

enum CarStyle: String, Codable {
    case supercar, muscle, suv, offroad, drift, classic, hatch, ev
}

/// An original (brand-free) car. Stats are normalized 0...1 and mapped to
/// physics in the scene.
struct CarSpec: Identifiable {
    let id: String
    let name: String
    let category: String
    let style: CarStyle
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let price: Int
    let topSpeed: Float     // 0...1
    let accel: Float        // 0...1
    let handling: Float     // 0...1

    var baseColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
}

enum CarShop {
    static let all: [CarSpec] = [
        CarSpec(id: "hatch",   name: "Civic Spark",  category: "Hatchback", style: .hatch,
                r: 0.30, g: 0.62, b: 0.85, price: 0,      topSpeed: 0.30, accel: 0.40, handling: 0.62),
        CarSpec(id: "classic", name: "Vintage 60",   category: "Classic",   style: .classic,
                r: 0.86, g: 0.74, b: 0.36, price: 38000,  topSpeed: 0.45, accel: 0.42, handling: 0.50),
        CarSpec(id: "drift",   name: "Sideways S",   category: "Drift",     style: .drift,
                r: 0.95, g: 0.35, b: 0.55, price: 60000,  topSpeed: 0.66, accel: 0.62, handling: 0.92),
        CarSpec(id: "suv",     name: "Summit XL",    category: "SUV",       style: .suv,
                r: 0.30, g: 0.34, b: 0.40, price: 55000,  topSpeed: 0.48, accel: 0.46, handling: 0.42),
        CarSpec(id: "offroad", name: "Trail 4x4",    category: "Off-road",  style: .offroad,
                r: 0.55, g: 0.50, b: 0.28, price: 72000,  topSpeed: 0.50, accel: 0.55, handling: 0.55),
        CarSpec(id: "muscle",  name: "Stallion GT",  category: "Muscle",    style: .muscle,
                r: 0.85, g: 0.16, b: 0.18, price: 95000,  topSpeed: 0.80, accel: 0.78, handling: 0.55),
        CarSpec(id: "ev",      name: "Volt One",     category: "Electric",  style: .ev,
                r: 0.20, g: 0.80, b: 0.70, price: 120000, topSpeed: 0.78, accel: 0.96, handling: 0.70),
        CarSpec(id: "super",   name: "Apex R",       category: "Supercar",  style: .supercar,
                r: 0.95, g: 0.78, b: 0.16, price: 260000, topSpeed: 0.92, accel: 0.90, handling: 0.82),
        CarSpec(id: "hyper",   name: "Veloce X",     category: "Hypercar",  style: .supercar,
                r: 0.10, g: 0.12, b: 0.16, price: 650000, topSpeed: 1.00, accel: 0.98, handling: 0.88),
    ]

    static func spec(_ id: String) -> CarSpec {
        all.first { $0.id == id } ?? all[0]
    }
}
