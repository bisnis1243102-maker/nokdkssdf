import UIKit
import SceneKit

/// Weather drives more than a particle system: `wetness` feeds the road shader
/// modifier and the screen-space reflection pass, so a downpour genuinely
/// changes how the city looks rather than just adding sprites.
final class WeatherSystem {

    enum Condition: CaseIterable {
        case clear, overcast, drizzle, storm

        var label: String {
            switch self {
            case .clear:    return "Clear"
            case .overcast: return "Overcast"
            case .drizzle:  return "Drizzle"
            case .storm:    return "Downpour"
            }
        }

        /// Target surface wetness, 0...1.
        var wetness: Float {
            switch self {
            case .clear:    return 0.05
            case .overcast: return 0.20
            case .drizzle:  return 0.65
            case .storm:    return 1.00
            }
        }

        var rainRate: CGFloat {
            switch self {
            case .clear:    return 0
            case .overcast: return 0
            case .drizzle:  return 900
            case .storm:    return 3200
            }
        }

        var fogEnd: CGFloat {
            switch self {
            case .clear:    return 900
            case .overcast: return 620
            case .drizzle:  return 460
            case .storm:    return 300
            }
        }
    }

    private(set) var condition: Condition = .clear
    /// Eases toward the condition's target so transitions aren't a hard cut.
    private(set) var wetness: Float = 0.05

    private var timer: Float = 0
    private var rainNode: SCNNode?
    private var sprayNode: SCNNode?

    /// Materials that read the `wetness` uniform, refreshed as it eases.
    private var wetMaterials: [SCNMaterial] = []

    func register(wetMaterial m: SCNMaterial) {
        wetMaterials.append(m)
    }

    // MARK: Rain

    /// Attaches rain to a node that follows the player, so the volume of
    /// particles stays small no matter how big the map is.
    func attachRain(to node: SCNNode) {
        let rain = SCNParticleSystem()
        rain.particleColor = UIColor(white: 0.78, alpha: 0.55)
        rain.particleSize = 0.035
        rain.particleSizeVariation = 0.02
        rain.birthRate = 0
        rain.emissionDuration = 1
        rain.particleLifeSpan = 1.1
        rain.particleVelocity = 46
        rain.particleVelocityVariation = 8
        rain.spreadingAngle = 3
        rain.emitterShape = SCNBox(width: 44, height: 0.1, length: 44, chamferRadius: 0)
        rain.birthLocation = .volume
        rain.emittingDirection = SCNVector3(0, -1, 0)
        rain.isAffectedByGravity = true
        rain.blendMode = .additive
        rain.isLightingEnabled = false
        rain.stretchFactor = 0.14

        let n = SCNNode()
        n.position = SCNVector3(0, 22, 0)
        n.addParticleSystem(rain)
        node.addChildNode(n)
        rainNode = n

        // Road spray kicked up behind the car.
        let spray = SCNParticleSystem()
        spray.particleColor = UIColor(white: 0.85, alpha: 0.22)
        spray.particleSize = 0.22
        spray.particleSizeVariation = 0.12
        spray.birthRate = 0
        spray.particleLifeSpan = 0.6
        spray.particleVelocity = 3
        spray.spreadingAngle = 40
        spray.emittingDirection = SCNVector3(0, 1, 0)
        spray.blendMode = .alpha
        spray.isLightingEnabled = false

        let s = SCNNode()
        s.position = SCNVector3(0, 0.2, 1.6)
        s.addParticleSystem(spray)
        node.addChildNode(s)
        sprayNode = s
    }

    // MARK: Tick

    /// Advances the weather clock and eases every dependent value.
    /// - Returns: true when the condition changed this frame.
    @discardableResult
    func update(dt: Float, scene: SCNScene, speed: Float) -> Bool {
        timer += dt
        var changed = false
        if timer > 95 {
            timer = 0
            var next = Condition.allCases.randomElement() ?? .clear
            // Avoid picking the same condition twice in a row.
            if next == condition {
                next = Condition.allCases.first { $0 != condition } ?? .clear
            }
            condition = next
            changed = true
        }

        // Wetness rises fast in rain and dries slowly afterwards.
        let target = condition.wetness
        let rate: Float = target > wetness ? 0.28 : 0.05
        wetness += (target - wetness) * min(1, rate * dt * 6)

        for m in wetMaterials {
            m.setValue(NSNumber(value: wetness), forKey: "wetness")
        }

        if let r = rainNode?.particleSystems?.first {
            r.birthRate = condition.rainRate
        }
        if let s = sprayNode?.particleSystems?.first {
            // Spray only when moving on a wet road.
            s.birthRate = wetness > 0.35 ? CGFloat(min(1, abs(speed) / 18)) * 260 : 0
        }

        if changed {
            scene.fogEndDistance = condition.fogEnd
            scene.fogStartDistance = condition.fogEnd * 0.25
        }

        return changed
    }
}
