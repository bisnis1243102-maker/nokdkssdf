import AVFoundation

/// All audio is synthesized — engine, tyres, sirens, horn, rain, impacts —
/// so the game ships zero audio assets. A single AVAudioSourceNode renders
/// the whole mix sample-by-sample; the game thread just pokes level and
/// pitch controls, which the render thread reads.
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private var started = false

    // Control surface (main thread writes, render thread reads).
    private var master: Float = 0
    private var motorLevel: Float = 0
    private var motorHz: Float = 70
    private var screechLevel: Float = 0
    private var sirenLevel: Float = 0
    private var rainLevel: Float = 0
    private var hornRemaining: Float = 0
    private var burstRemaining: Float = 0
    private var burstDull = true

    // Render-thread state.
    private var pMotor: Float = 0
    private var pMotorSub: Float = 0
    private var pSiren: Float = 0
    private var pSirenLFO: Float = 0
    private var pHornA: Float = 0
    private var pHornB: Float = 0
    private var lpMotor: Float = 0
    private var lpRain: Float = 0
    private var lpBurst: Float = 0
    private var hpNoise: Float = 0
    private var noiseState: UInt32 = 0x2545F491

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let hardwareRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 44100
        let sr = Float(rate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            return
        }
        let source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = self.renderSample(sr: sr)
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        try? engine.start()
    }

    // MARK: Controls

    func setMaster(_ v: Float) { master = v }
    func setEngine(level: Float, hz: Float) { motorLevel = level; motorHz = hz }
    func setScreech(_ v: Float) { screechLevel = v }
    func setSiren(_ v: Float) { sirenLevel = v }
    func setRain(_ v: Float) { rainLevel = v }
    func horn(_ seconds: Float = 0.45) { hornRemaining = max(hornRemaining, seconds) }
    func shot() { burstDull = false; burstRemaining = 0.09 }
    func crash(_ strength: Float) { burstDull = true; burstRemaining = 0.18 + 0.14 * strength }
    func thud() { burstDull = true; burstRemaining = max(burstRemaining, 0.08) }

    // MARK: Render

    private func renderSample(sr: Float) -> Float {
        let dt = 1 / sr

        // xorshift white noise, shared by several voices.
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        let n = Float(Int32(bitPattern: noiseState)) / Float(Int32.max)

        var out: Float = 0

        // Engine: two detuned saws through a soft low-pass, a hint of grit.
        if motorLevel > 0.001 {
            pMotor += motorHz * dt
            if pMotor >= 1 { pMotor -= 1 }
            pMotorSub += motorHz * 0.501 * dt
            if pMotorSub >= 1 { pMotorSub -= 1 }
            let raw = (pMotor * 2 - 1) * 0.6 + (pMotorSub * 2 - 1) * 0.45 + n * 0.05
            lpMotor += (raw - lpMotor) * 0.10
            out += lpMotor * motorLevel * 0.30
        }

        // Tyre screech: high-passed noise.
        if screechLevel > 0.001 {
            hpNoise += (n - hpNoise) * 0.35
            out += (n - hpNoise) * screechLevel * 0.22
        }

        // Siren wail.
        if sirenLevel > 0.001 {
            pSirenLFO += 0.5 * dt
            if pSirenLFO >= 1 { pSirenLFO -= 1 }
            let f = 700 + 420 * sinf(pSirenLFO * 2 * .pi)
            pSiren += f * dt
            if pSiren >= 1 { pSiren -= 1 }
            out += sinf(pSiren * 2 * .pi) * sirenLevel * 0.15
        }

        // Rain: a hushed low-passed noise bed.
        if rainLevel > 0.001 {
            lpRain += (n - lpRain) * 0.06
            out += lpRain * rainLevel * 0.35
        }

        // Horn: a slightly sour two-note chord, squared off.
        if hornRemaining > 0 {
            hornRemaining -= dt
            pHornA += 415 * dt
            if pHornA >= 1 { pHornA -= 1 }
            pHornB += 523 * dt
            if pHornB >= 1 { pHornB -= 1 }
            let a: Float = pHornA < 0.5 ? 1 : -1
            let b: Float = pHornB < 0.5 ? 1 : -1
            out += (a + b) * 0.06
        }

        // Impacts (dull, low-passed) and gunshots (bright, sharp).
        if burstRemaining > 0 {
            burstRemaining -= dt
            let env = min(1, burstRemaining * (burstDull ? 6 : 14))
            lpBurst += (n - lpBurst) * (burstDull ? 0.08 : 0.55)
            out += lpBurst * env * (burstDull ? 0.9 : 0.7)
        }

        return max(-1, min(1, out * master))
    }
}
