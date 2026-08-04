import SwiftUI

/// Live simulation telemetry, shown when Developer Mode is on.
///
/// Everything here is read straight from the solver's published state — no
/// separate instrumentation path — so what the overlay shows is exactly what
/// the physics is doing. It is the first thing to reach for when a handling
/// change does not feel the way it was intended to.
public struct DeveloperOverlayView: View {

    public let session: RaceSession?

    @State private var readout = Readout()
    @State private var frameTimes: [Double] = []
    @State private var lastFrame = Date()

    private let timer = Timer.publish(every: 1.0 / 10.0, on: .main, in: .common).autoconnect()

    private struct Readout {
        var speed: Double = 0
        var pitch: Double = 0
        var angularVelocity: Double = 0
        var rpm: Double = 0
        var throttle: Double = 0
        var frontCompression: Double = 0
        var rearCompression: Double = 0
        var frontLoad: Double = 0
        var rearLoad: Double = 0
        var frontSlip: Double = 0
        var rearSlip: Double = 0
        var frontGrip: Double = 0
        var rearGrip: Double = 0
        var airborne = false
        var surface: String = "—"
        var frameTimeMS: Double = 0
        var fps: Double = 0
    }

    public init(session: RaceSession?) {
        self.session = session
    }

    public var body: some View {
        VStack {
            HStack {
                Spacer()
                panel
                    .padding(Theme.Spacing.md)
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .onReceive(timer) { _ in sample() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("FPS", String(format: "%.0f  (%.1f ms)", readout.fps, readout.frameTimeMS))
            divider
            row("Speed", String(format: "%.2f m/s", readout.speed))
            row("Pitch", String(format: "%+.3f rad", readout.pitch))
            row("Pitch rate", String(format: "%+.3f rad/s", readout.angularVelocity))
            row("Airborne", readout.airborne ? "yes" : "no")
            divider
            row("RPM", String(format: "%.0f", readout.rpm))
            row("Throttle", String(format: "%.2f", readout.throttle))
            divider
            row("Susp F/R", String(format: "%.3f / %.3f m",
                                   readout.frontCompression, readout.rearCompression))
            row("Load F/R", String(format: "%.0f / %.0f N", readout.frontLoad, readout.rearLoad))
            row("Slip F/R", String(format: "%+.2f / %+.2f", readout.frontSlip, readout.rearSlip))
            row("Grip F/R", String(format: "%.2f / %.2f", readout.frontGrip, readout.rearGrip))
            divider
            row("Surface", readout.surface)
            row("Timestep", "1/240 s fixed")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Color.black.opacity(0.68))
        )
        .frame(width: 250)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1).padding(.vertical, 2)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
        }
    }

    private func sample() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFrame)
        lastFrame = now

        // A short rolling window smooths the reading without hiding a stall.
        frameTimes.append(elapsed)
        if frameTimes.count > 12 { frameTimes.removeFirst() }
        let average = frameTimes.reduce(0, +) / Double(max(frameTimes.count, 1))

        guard let bike = session?.player?.bike else { return }
        var next = Readout()
        next.speed = bike.forwardSpeed
        next.pitch = bike.angle
        next.angularVelocity = bike.angularVelocity
        next.rpm = bike.engineRPM
        next.throttle = bike.appliedThrottle
        next.frontCompression = bike.frontWheel.compression
        next.rearCompression = bike.rearWheel.compression
        next.frontLoad = bike.frontWheel.normalLoad
        next.rearLoad = bike.rearWheel.normalLoad
        next.frontSlip = bike.frontWheel.slipRatio
        next.rearSlip = bike.rearWheel.slipRatio
        next.frontGrip = bike.frontWheel.gripUtilisation
        next.rearGrip = bike.rearWheel.gripUtilisation
        next.airborne = bike.isAirborne
        next.surface = bike.rearWheel.surface.displayName
        next.frameTimeMS = average * 1000
        next.fps = average > 0 ? 1 / average : 0
        readout = next
    }
}
