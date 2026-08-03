// MotoRush — race session: simulation, field management, camera, effects,
// scoring and replay capture. The UI layer drives this and reads its state.

import { Bike } from './physics.js';
import { AIController } from './ai.js';
import { Camera, Particles } from './render.js';
import { BIKES, AI_PERSONALITIES } from './data.js';
import { generateTrack } from './track.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

const AI_NAMES = ['Karo', 'Vance', 'Rook', 'Sable', 'Dune', 'Trace', 'Nyx', 'Falk', 'Pike',
  'Rhen', 'Voss', 'Aya', 'Kestrel', 'Brix', 'Onyx', 'Juno'];

export class Race {
  constructor(opts) {
    this.opts = opts;
    this.track = opts.track || generateTrack({ seed: opts.seed, biome: opts.biome, difficulty: opts.difficulty });
    this.mode = opts.mode || 'quick';     // quick | championship | timetrial | ranked | ghost
    this.difficulty = opts.difficulty ?? 0.6;
    this.assist = opts.assist || {};

    const spec = opts.playerSpec || BIKES[0];
    this.player = new Bike(spec, this.track, {
      upgrades: opts.upgrades, name: opts.playerName || 'You', tint: opts.tint || spec.color
    });
    this.player.isPlayer = true;

    this.field = [this.player];
    this.ai = [];
    const aiCount = opts.aiCount ?? 5;
    for (let i = 0; i < aiCount; i++) {
      const p = AI_PERSONALITIES[(Math.random() * AI_PERSONALITIES.length) | 0];
      // Field bikes come from the same class band as the player's.
      const pool = BIKES.filter(b => b.cls === spec.cls);
      const aspec = (pool.length ? pool : BIKES)[(Math.random() * (pool.length || BIKES.length)) | 0];
      const bike = new Bike(aspec, this.track, {
        isAI: true, name: AI_NAMES[(i * 3 + ((Math.random() * 5) | 0)) % AI_NAMES.length],
        tint: `hsl(${(i * 61 + 20) % 360} 70% 58%)`
      });
      bike.x = this.track.startX - 1.2 - i * 0.9;
      bike.y = this.track.heightAt(bike.x) + bike.wheelR + aspec.seatHeight;
      bike.number = 10 + i * 7;
      this.field.push(bike);
      this.ai.push(new AIController(bike, p, this.difficulty));
    }
    this.player.number = opts.playerNumber ?? 21;

    this.cam = new Camera();
    this.cam.x = this.player.x; this.cam.y = this.player.y;
    this.particles = new Particles(opts.quality === 'low' ? 260 : 900);

    this.state = 'countdown';   // countdown | racing | finished | crashed
    this.countdown = 3.2;
    this.time = 0;
    this.results = null;
    this.messages = [];
    this.slowmo = 1;
    this.finishCam = 0;

    // Ghost: previous best replay, plus the run we are recording now.
    this.ghost = opts.ghost || null;
    this.ghostIndex = 0;
    this.recording = [];
    this.recordTimer = 0;
    this.replay = [];           // full-fidelity buffer for the replay viewer
    this.stats = { perfects: 0, crashes: 0, airtime: 0, whipdeg: 0, style: 0 };
    this.combo = 0;
    this.comboTimer = 0;
  }

  get finished() { return this.state === 'finished'; }

  message(text, kind = 'info', ttl = 1.6) {
    this.messages.push({ text, kind, ttl, age: 0 });
    if (this.messages.length > 5) this.messages.shift();
  }

  update(dt, input, audio) {
    dt = Math.min(dt, 1 / 30);
    const sdt = dt * this.slowmo;

    if (this.state === 'countdown') {
      const prev = Math.ceil(this.countdown);
      this.countdown -= dt;
      const now = Math.ceil(this.countdown);
      if (now !== prev && now >= 0 && audio) audio.countdown(now);
      // Riders can blip the throttle on the gate but cannot launch early.
      const held = { throttle: input.throttle * 0.25, brake: 1, lean: 0, whip: 0 };
      this.player.update(dt, held, this.envOpts());
      for (const b of this.field) if (b !== this.player) b.update(dt, { throttle: 0, brake: 1, lean: 0, whip: 0 }, this.envOpts());
      this.cam.follow(this.player, dt, { width: 1, height: 1, ...this.canvasSize || {} });
      if (this.countdown <= 0) {
        this.state = 'racing';
        this.message('GO!', 'big', 1.0);
      }
      this.updateEffects(dt, audio);
      return;
    }

    if (this.state === 'racing' || this.state === 'finished') {
      this.time += this.state === 'racing' ? sdt : dt;

      // Player.
      let pin = input;
      if (this.assist.landing && this.player.airborne) pin = this.applyLandingAssist(input);
      if (this.assist.throttle) pin = { ...pin, throttle: this.throttleAssist(pin.throttle) };
      this.player.update(sdt, this.player.finished ? { throttle: 0, brake: 0.4, lean: 0, whip: 0 } : pin, this.envOpts());

      // Field.
      for (let i = 0; i < this.ai.length; i++) {
        const bike = this.ai[i].bike;
        const ain = bike.finished ? { throttle: 0, brake: 0.4, lean: 0, whip: 0 } : this.ai[i].update(sdt, this.track);
        bike.update(sdt, ain, this.envOpts());
        if (bike.crashed && bike.crashTimer > 1.6) bike.respawn();
      }

      // Ghost playback.
      if (this.ghost) {
        this.ghostIndex = clamp(Math.floor(this.time * 10), 0, this.ghost.length - 1);
        this.ghostPose = this.ghost[this.ghostIndex];
      }

      // Ghost recording at 10 Hz.
      this.recordTimer += sdt;
      if (this.recordTimer >= 0.1) {
        this.recordTimer -= 0.1;
        this.recording.push({ x: this.player.x, y: this.player.y, ang: this.player.ang, whip: this.player.whip });
        if (this.replay.length < 12000) {
          this.replay.push(this.field.map(b => [b.x, b.y, b.ang, b.whip]));
        }
      }

      this.handleEvents(audio);
      this.checkFinish(audio);
    }

    if (this.player.crashed && this.player.crashTimer > 1.8 && !this.player.finished) this.player.respawn();

    this.updateEffects(dt, audio);
  }

  envOpts() {
    const b = this.track.biome;
    return {
      gripMul: b.grip ?? 1,
      rollDrag: b.name === 'Sand' ? 2.1 : b.name === 'Mud' ? 1.7 : b.name === 'Snow' ? 1.3 : 1
    };
  }

  // Assists never add grip — they only smooth the rider's own inputs.
  applyLandingAssist(input) {
    const b = this.player;
    let x = b.x, y = b.y, vx = b.vx, vy = b.vy;
    for (let i = 0; i < 60; i++) {
      vy -= 9.81 * 0.05; x += vx * 0.05; y += vy * 0.05;
      if (y <= this.track.heightAt(x) + b.wheelR + 0.3) break;
    }
    const target = Math.atan(this.track.slopeAt(x));
    const err = target - b.ang;
    const auto = clamp(-err * 1.4 - b.angVel * 0.2, -0.6, 0.6);
    return { ...input, lean: clamp(input.lean + auto * 0.7, -1, 1) };
  }

  throttleAssist(t) {
    const b = this.player;
    if (b.wheelie > 0.55 && t > 0.6) return t * 0.65;
    return t;
  }

  handleEvents(audio) {
    for (const bike of this.field) {
      for (const ev of bike.events) {
        const isPlayer = bike === this.player;
        if (ev.type === 'landing') {
          if (isPlayer) {
            if (ev.quality === 'perfect') {
              this.stats.perfects++;
              this.combo++; this.comboTimer = 3;
              this.message(this.combo > 1 ? `PERFECT ×${this.combo}` : 'PERFECT LANDING', 'good');
              this.cam.kick(0.12);
            } else if (ev.quality === 'bad') {
              this.combo = 0;
              this.message('CASED', 'bad');
              this.cam.kick(0.35);
            } else {
              this.cam.kick(0.1);
            }
            if (audio) audio.landing(ev.quality, ev.impact);
          }
          const col = this.track.biome.dust;
          this.particles.burst(ev.x, this.track.heightAt(ev.x) + 0.1,
            Math.min(26, 6 + ev.impact * 1.6),
            { color: col, speed: 1.4 + ev.impact * 0.22, life: 0.75, size: 0.16, glow: !!this.track.biome.glow });
        } else if (ev.type === 'crash') {
          if (isPlayer) {
            this.stats.crashes++;
            this.combo = 0;
            this.message('CRASH', 'bad', 2);
            this.cam.kick(1.2);
            this.slowmo = 0.35;
            setTimeout(() => { this.slowmo = 1; }, 700);
            if (audio) audio.crash();
          }
          this.particles.burst(ev.x, this.track.heightAt(ev.x) + 0.2, 30,
            { color: this.track.biome.dust, speed: 5, life: 1.1, size: 0.2 });
        } else if (ev.type === 'wheelspin') {
          if (Math.random() < 0.5) {
            this.particles.spawn(ev.x, this.track.heightAt(ev.x) + 0.05,
              -2 - Math.random() * 4, 1 + Math.random() * 2,
              { color: this.track.biome.dust, life: 0.6, size: 0.14, glow: !!this.track.biome.glow });
          }
          if (isPlayer && audio && Math.random() < 0.08) audio.chain();
        }
      }
      bike.events.length = 0;
    }
  }

  checkFinish(audio) {
    for (const bike of this.field) {
      if (!bike.finished && bike.x >= this.track.finishX) {
        bike.finished = true;
        bike.finishTime = this.time;
        if (bike === this.player) this.onPlayerFinish(audio);
      }
    }
    if (this.player.finished && this.state !== 'finished') {
      this.state = 'finished';
    }
  }

  onPlayerFinish(audio) {
    const order = this.standings();
    const position = order.findIndex(b => b.bike === this.player) + 1;
    this.stats.airtime = this.player.totalAirTime;
    this.stats.whipdeg = this.player.whipDegrees;
    this.stats.style = Math.round(this.player.style);
    this.results = {
      position,
      fieldSize: this.field.length,
      time: this.player.finishTime,
      stats: { ...this.stats, perfects: this.player.perfects, crashes: this.player.crashes },
      ghost: this.recording,
      track: this.track,
      order
    };
    this.message(position === 1 ? 'WINNER' : `P${position}`, 'big', 3);
    if (audio) { audio.ping(660, 0.2, 'square', 0.14, 220); setTimeout(() => audio.ping(990, 0.3, 'sine', 0.12, 300), 160); }
    this.slowmo = 0.5;
    setTimeout(() => { this.slowmo = 1; }, 900);
  }

  standings() {
    return this.field
      .map(b => ({ bike: b, progress: b.finished ? Infinity - (b.finishTime || 0) : b.x, name: b === this.player ? 'You' : b.name }))
      .sort((a, b) => {
        const af = a.bike.finished, bf = b.bike.finished;
        if (af && bf) return a.bike.finishTime - b.bike.finishTime;
        if (af) return -1;
        if (bf) return 1;
        return b.bike.x - a.bike.x;
      });
  }

  playerPosition() {
    return this.standings().findIndex(s => s.bike === this.player) + 1;
  }

  updateEffects(dt, audio) {
    // Roost from the driven wheel.
    const p = this.player;
    const rear = p.wheels[0];
    if (rear.grounded && p.forwardSpeed > 3 && Math.random() < 0.9) {
      const dust = this.track.biome.dust;
      this.particles.spawn(rear.cx, rear.cy - 0.2,
        -p.forwardSpeed * (0.25 + Math.random() * 0.3), 0.6 + Math.random() * 2.4,
        { color: dust, life: 0.5 + Math.random() * 0.4, size: 0.1 + Math.random() * 0.12, glow: !!this.track.biome.glow });
    }
    this.particles.update(dt);

    for (let i = this.messages.length - 1; i >= 0; i--) {
      const m = this.messages[i];
      m.age += dt;
      if (m.age >= m.ttl) this.messages.splice(i, 1);
    }
    this.comboTimer -= dt;
    if (this.comboTimer <= 0) this.combo = 0;

    if (audio) {
      audio.updateEngine(this.player, {
        crowd: !!this.track.biome.stadium,
        muted: this.state === 'countdown' && this.countdown > 3
      });
      const susAmt = Math.abs(this.player.wheels[0].vel) + Math.abs(this.player.wheels[1].vel);
      if (susAmt > 1.6 && Math.random() < 0.15) audio.suspension(Math.min(1, susAmt / 5));
    }
  }

  draw(renderer, profileGear) {
    const { cam, track } = this;
    this.canvasSize = { width: renderer.canvas.width, height: renderer.canvas.height };
    renderer.drawSky(cam, track, { dayPhase: 0.5 });
    renderer.drawTerrain(cam, track);
    renderer.drawProps(cam, track);

    // Ghost first so live riders draw over it.
    if (this.ghostPose) {
      const g = this.ghostPose;
      const fake = {
        x: g.x, y: g.y, ang: g.ang, whip: g.whip, scrub: 0, lean: 0, tint: '#8fa6c8',
        wheelR: this.player.wheelR, spec: this.player.spec, track,
        airborne: false, crashed: false,
        wheels: this.player.wheels.map(w => ({ ...w, cx: g.x + (w.ax || 0), cy: g.y - 0.6 }))
      };
      renderer.drawBike(cam, fake, { ghost: true });
    }

    for (const b of this.field) {
      if (b === this.player) continue;
      renderer.drawBike(cam, b, { number: b.number });
    }
    this.particles.draw(renderer.ctx, cam, renderer.canvas);
    renderer.drawBike(cam, this.player, { number: this.player.number, gear: profileGear, plate: profileGear && profileGear.plateColor });
    renderer.drawWeather(cam, track, performance.now() / 1000);
    renderer.speedLines(this.player);
    renderer.vignetteAndGrade(track, clamp(Math.abs(this.player.vx) / 50, 0, 1));
  }

  stepCamera(dt, canvas) {
    this.cam.follow(this.player, dt, canvas);
  }
}
