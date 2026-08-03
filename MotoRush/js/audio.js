// MotoRush — procedural audio. Everything is synthesised at runtime with the
// Web Audio API, so there are no sample assets to ship or license.

export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.enabled = true;
    this.masterVol = 0.8;
    this.sfxVol = 0.9;
    this.musicVol = 0.35;
    this.ready = false;
  }

  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) { this.enabled = false; return; }
    const ctx = this.ctx = new AC();

    this.master = ctx.createGain();
    this.master.gain.value = this.masterVol;
    this.master.connect(ctx.destination);

    this.sfxBus = ctx.createGain(); this.sfxBus.gain.value = this.sfxVol;
    this.musicBus = ctx.createGain(); this.musicBus.gain.value = this.musicVol;
    this.sfxBus.connect(this.master); this.musicBus.connect(this.master);

    this.noiseBuf = this.makeNoise(2);
    this.buildEngine();
    this.buildAmbience();
    this.ready = true;
  }

  resume() { if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume(); }

  makeNoise(seconds) {
    const ctx = this.ctx;
    const buf = ctx.createBuffer(1, ctx.sampleRate * seconds, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    return buf;
  }

  // Engine: two detuned saws through a resonant lowpass + a noise "intake"
  // layer. Frequency follows rpm; filter follows load.
  buildEngine() {
    const ctx = this.ctx;
    const g = this.engineGain = ctx.createGain(); g.gain.value = 0;
    const filt = this.engineFilter = ctx.createBiquadFilter();
    filt.type = 'lowpass'; filt.frequency.value = 900; filt.Q.value = 6;

    const shaper = ctx.createWaveShaper();
    const curve = new Float32Array(1024);
    for (let i = 0; i < 1024; i++) {
      const x = (i / 1023) * 2 - 1;
      curve[i] = Math.tanh(x * 2.6);
    }
    shaper.curve = curve;

    this.osc = [];
    for (let i = 0; i < 3; i++) {
      const o = ctx.createOscillator();
      o.type = i === 2 ? 'square' : 'sawtooth';
      o.frequency.value = 60;
      o.detune.value = (i - 1) * 14;
      const og = ctx.createGain(); og.gain.value = i === 2 ? 0.25 : 0.5;
      o.connect(og); og.connect(shaper);
      o.start();
      this.osc.push(o);
    }

    const intake = ctx.createBufferSource();
    intake.buffer = this.noiseBuf; intake.loop = true;
    const ig = this.intakeGain = ctx.createGain(); ig.gain.value = 0.05;
    const ibp = ctx.createBiquadFilter(); ibp.type = 'bandpass'; ibp.frequency.value = 1400; ibp.Q.value = 1.2;
    intake.connect(ibp); ibp.connect(ig); ig.connect(g);
    intake.start();

    shaper.connect(filt); filt.connect(g); g.connect(this.sfxBus);
  }

  buildAmbience() {
    const ctx = this.ctx;
    // Wind: filtered noise whose brightness tracks speed.
    const wind = ctx.createBufferSource(); wind.buffer = this.noiseBuf; wind.loop = true;
    const wf = this.windFilter = ctx.createBiquadFilter();
    wf.type = 'bandpass'; wf.frequency.value = 500; wf.Q.value = 0.7;
    const wg = this.windGain = ctx.createGain(); wg.gain.value = 0;
    wind.connect(wf); wf.connect(wg); wg.connect(this.sfxBus); wind.start();

    // Crowd: heavily lowpassed noise with slow amplitude drift.
    const crowd = ctx.createBufferSource(); crowd.buffer = this.noiseBuf; crowd.loop = true;
    const cf = ctx.createBiquadFilter(); cf.type = 'lowpass'; cf.frequency.value = 700;
    const cg = this.crowdGain = ctx.createGain(); cg.gain.value = 0;
    const lfo = ctx.createOscillator(); lfo.frequency.value = 0.13;
    const lg = ctx.createGain(); lg.gain.value = 0.35;
    lfo.connect(lg); lg.connect(cg.gain); lfo.start();
    crowd.connect(cf); cf.connect(cg); cg.connect(this.sfxBus); crowd.start();
  }

  setBuses() {
    if (!this.ready) return;
    this.master.gain.value = this.masterVol;
    this.sfxBus.gain.value = this.sfxVol;
    this.musicBus.gain.value = this.musicVol;
  }

  // Called every frame with the player's bike state.
  updateEngine(bike, opts = {}) {
    if (!this.ready || !this.enabled) return;
    const t = this.ctx.currentTime;
    const rpm = Math.max(0.05, bike.rpm);
    const base = (bike.spec.electric ? 120 : 58) + rpm * (bike.spec.electric ? 620 : 300);
    for (let i = 0; i < this.osc.length; i++) {
      this.osc[i].frequency.setTargetAtTime(base * (i === 2 ? 2 : 1), t, 0.03);
    }
    this.engineFilter.frequency.setTargetAtTime(500 + rpm * 3200, t, 0.05);
    const load = bike.airborne ? 0.5 : 1;
    this.engineGain.gain.setTargetAtTime(0.16 * load * (opts.muted ? 0 : 1), t, 0.05);
    this.intakeGain.gain.setTargetAtTime(0.03 + rpm * 0.07, t, 0.08);

    const spd = Math.max(0, bike.forwardSpeed);
    this.windGain.gain.setTargetAtTime(Math.min(0.12, spd / 60 * 0.12), t, 0.15);
    this.windFilter.frequency.setTargetAtTime(400 + spd * 26, t, 0.2);
    this.crowdGain.gain.setTargetAtTime(opts.crowd ? 0.05 : 0.0, t, 0.6);
  }

  ping(freq, dur, type = 'sine', gain = 0.2, sweep = 0) {
    if (!this.ready || !this.enabled) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const o = ctx.createOscillator(); o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (sweep) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq + sweep), t + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(gain, t + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(this.sfxBus);
    o.start(t); o.stop(t + dur + 0.02);
  }

  thud(intensity = 1) {
    if (!this.ready || !this.enabled) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const src = ctx.createBufferSource(); src.buffer = this.noiseBuf;
    const f = ctx.createBiquadFilter(); f.type = 'lowpass';
    f.frequency.setValueAtTime(900 * intensity, t);
    f.frequency.exponentialRampToValueAtTime(80, t + 0.25);
    const g = ctx.createGain();
    g.gain.setValueAtTime(Math.min(0.55, 0.18 * intensity), t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.3);
    src.connect(f); f.connect(g); g.connect(this.sfxBus);
    src.start(t); src.stop(t + 0.35);
    this.ping(70 * intensity, 0.18, 'sine', 0.22 * intensity, -40);
  }

  suspension(amount) {
    if (amount < 0.25) return;
    this.ping(220 + amount * 120, 0.07, 'triangle', 0.03 * amount, -120);
  }

  chain() { this.ping(2400 + Math.random() * 600, 0.03, 'square', 0.012, -400); }

  landing(quality, impact) {
    this.thud(0.6 + Math.min(1.4, impact / 10));
    if (quality === 'perfect') { this.ping(880, 0.1, 'sine', 0.12, 320); this.ping(1320, 0.14, 'sine', 0.08, 200); }
    else if (quality === 'bad') this.ping(160, 0.2, 'sawtooth', 0.09, -60);
  }

  crash() {
    this.thud(2.0);
    for (let i = 0; i < 5; i++) {
      setTimeout(() => this.ping(300 + Math.random() * 900, 0.06, 'square', 0.05, -200), i * 45);
    }
  }

  ui(kind = 'tap') {
    const map = { tap: [520, 0.05, 0.06], back: [320, 0.06, 0.06], buy: [700, 0.14, 0.09], deny: [180, 0.15, 0.08] };
    const [f, d, g] = map[kind] || map.tap;
    this.ping(f, d, 'triangle', g, kind === 'buy' ? 300 : 0);
  }

  countdown(step) {
    if (step > 0) this.ping(440, 0.16, 'square', 0.14);
    else { this.ping(880, 0.4, 'square', 0.18); this.ping(1320, 0.4, 'sine', 0.1); }
  }

  // Dynamic soundtrack: a simple layered arpeggio whose density follows race
  // intensity. Starts on demand so it never blocks the first frame.
  startMusic(intensityFn) {
    if (!this.ready || this.musicTimer) return;
    const ctx = this.ctx;
    const scale = [0, 3, 5, 7, 10, 12, 15];
    let step = 0;
    const tick = () => {
      const intensity = Math.min(1, Math.max(0, intensityFn ? intensityFn() : 0.5));
      const root = 110;
      const n = scale[step % scale.length];
      const f = root * Math.pow(2, n / 12);
      const t = ctx.currentTime;
      const o = ctx.createOscillator();
      o.type = intensity > 0.6 ? 'sawtooth' : 'triangle';
      o.frequency.value = f * (step % 8 === 0 ? 1 : 2);
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.05 + intensity * 0.07, t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.28);
      const filt = ctx.createBiquadFilter();
      filt.type = 'lowpass'; filt.frequency.value = 600 + intensity * 3000;
      o.connect(filt); filt.connect(g); g.connect(this.musicBus);
      o.start(t); o.stop(t + 0.32);
      if (step % 4 === 0) {
        // Kick.
        const k = ctx.createOscillator(); const kg = ctx.createGain();
        k.frequency.setValueAtTime(120, t); k.frequency.exponentialRampToValueAtTime(45, t + 0.12);
        kg.gain.setValueAtTime(0.16, t); kg.gain.exponentialRampToValueAtTime(0.0001, t + 0.2);
        k.connect(kg); kg.connect(this.musicBus); k.start(t); k.stop(t + 0.22);
      }
      step++;
      this.musicTimer = setTimeout(tick, 240 - intensity * 60);
    };
    tick();
  }

  stopMusic() { if (this.musicTimer) { clearTimeout(this.musicTimer); this.musicTimer = null; } }
}
