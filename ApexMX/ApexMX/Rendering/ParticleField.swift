import SpriteKit
import UIKit

/// A pooled particle system for roost, dust, mud and landing debris.
///
/// Particles are the single highest-frequency allocation in a racing game, so
/// none are allocated during play: a fixed pool of sprites is created up front,
/// recycled on expiry, and simply hidden when idle. Peak particle count is a
/// hard budget rather than a hope.
public final class ParticleField: SKNode {

    private struct Particle {
        var node: SKSpriteNode
        var velocity: CGVector
        var life: CGFloat
        var maximumLife: CGFloat
        var spin: CGFloat
        var startScale: CGFloat
        var active: Bool
    }

    /// Hard cap on simultaneous particles. Chosen so the whole field fits
    /// comfortably in one draw call's worth of work on the oldest supported
    /// device while still reading as a dense roost at speed.
    private let capacity: Int
    private var particles: [Particle] = []
    private var nextIndex = 0
    private let texture: SKTexture
    /// Effects use their own random stream so that varying them can never
    /// perturb the simulation's sequence.
    private var random = DeterministicRandom(seed: 0x9E3779B97F4A7C15)

    public init(capacity: Int = 220) {
        self.capacity = capacity
        self.texture = ParticleField.makeSoftDotTexture()
        super.init()
        zPosition = 40

        particles.reserveCapacity(capacity)
        for _ in 0..<capacity {
            let node = SKSpriteNode(texture: texture)
            node.isHidden = true
            node.blendMode = .alpha
            addChild(node)
            particles.append(Particle(node: node,
                                      velocity: .zero,
                                      life: 0,
                                      maximumLife: 1,
                                      spin: 0,
                                      startScale: 1,
                                      active: false))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ParticleField is created in code only") }

    /// Emits a burst of particles from a world position.
    ///
    /// - Parameters:
    ///   - worldPosition: Emission point, in simulation metres.
    ///   - direction: Bias for the initial velocity, in metres per second.
    ///   - spread: Random angular spread applied to `direction`, in radians.
    ///   - count: Number of particles requested. Fewer may be emitted if the
    ///     pool is saturated, which is the correct behaviour under load.
    ///   - surface: Determines colour and how long the particles hang.
    ///   - intensity: Scales size, speed and lifetime, `0...1`.
    public func emit(at worldPosition: Vector2,
                     direction: Vector2,
                     spread: Double,
                     count: Int,
                     surface: SurfaceType,
                     intensity: Double) {
        guard count > 0, intensity > 0.01 else { return }
        let properties = surface.properties
        let color = SKColor(red: CGFloat(properties.particleColor.r),
                            green: CGFloat(properties.particleColor.g),
                            blue: CGFloat(properties.particleColor.b),
                            alpha: 1)
        let origin = RenderScale.point(worldPosition)

        for _ in 0..<count {
            guard let index = acquire() else { return }
            let angle = atan2(direction.y, direction.x) + random.range(-spread, spread)
            let speed = direction.length * random.range(0.5, 1.35) * (0.5 + intensity)
            let lifetime = CGFloat(random.range(0.35, 0.95)
                                   * (0.6 + properties.deformability * 0.8))
            let scale = CGFloat(random.range(0.35, 1.0)) * CGFloat(0.5 + intensity)

            particles[index].node.isHidden = false
            particles[index].node.position = CGPoint(
                x: origin.x + CGFloat(random.range(-6, 6)),
                y: origin.y + CGFloat(random.range(-4, 8))
            )
            particles[index].node.color = color
            particles[index].node.colorBlendFactor = 1
            particles[index].node.alpha = 0.85
            particles[index].node.setScale(scale)
            particles[index].node.zRotation = CGFloat(random.range(0, .pi * 2))
            particles[index].velocity = CGVector(
                dx: RenderScale.length(cos(angle) * speed),
                dy: RenderScale.length(sin(angle) * speed)
            )
            particles[index].life = lifetime
            particles[index].maximumLife = lifetime
            particles[index].spin = CGFloat(random.range(-4, 4))
            particles[index].startScale = scale
            particles[index].active = true
        }
    }

    /// Advances every live particle. Dead particles are hidden, not removed.
    public func update(dt: CGFloat) {
        guard dt > 0 else { return }
        let gravity: CGFloat = -RenderScale.length(9.81) * 0.55
        let drag: CGFloat = 1 - min(dt * 2.4, 0.9)

        for index in particles.indices where particles[index].active {
            particles[index].life -= dt
            if particles[index].life <= 0 {
                particles[index].active = false
                particles[index].node.isHidden = true
                continue
            }

            particles[index].velocity.dy += gravity * dt
            particles[index].velocity.dx *= drag
            particles[index].velocity.dy *= drag

            let node = particles[index].node
            node.position.x += particles[index].velocity.dx * dt
            node.position.y += particles[index].velocity.dy * dt
            node.zRotation += particles[index].spin * dt

            // Particles fade and swell as they die, which reads as dust
            // dispersing rather than blinking out.
            let t = particles[index].life / particles[index].maximumLife
            node.alpha = t * 0.85
            node.setScale(particles[index].startScale * (1 + (1 - t) * 0.6))
        }
    }

    /// Hides every particle. Used on restart so debris from the previous run
    /// does not survive into the new one.
    public func clear() {
        for index in particles.indices {
            particles[index].active = false
            particles[index].node.isHidden = true
        }
    }

    /// Finds a free slot, or recycles the oldest if the pool is saturated.
    private func acquire() -> Int? {
        for _ in 0..<capacity {
            let index = nextIndex
            nextIndex = (nextIndex + 1) % capacity
            if !particles[index].active { return index }
        }
        // Every slot is busy: steal one so a burst still reads, rather than
        // silently dropping the whole effect.
        let index = nextIndex
        nextIndex = (nextIndex + 1) % capacity
        return index
    }

    /// A small radial-gradient dot, generated once and shared by every particle.
    private static func makeSoftDotTexture() -> SKTexture {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [SKColor.white.cgColor,
                         SKColor.white.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            ) else { return }
            cg.drawRadialGradient(gradient,
                                  startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                                  endCenter: CGPoint(x: 8, y: 8), endRadius: 8,
                                  options: [])
        }
        return SKTexture(image: image)
    }
}
