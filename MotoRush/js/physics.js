// MotoRush — bike physics.
//
// Model: a rigid chassis (mass, inertia) carrying two raycast suspension
// units. Each unit casts from its chassis anchor along the chassis "down"
// axis, finds the terrain, and applies a spring/damper normal force plus a
// friction-limited longitudinal tyre force at the contact patch. Rider weight
// transfer moves the centre of mass, which is what actually produces
// wheelies, stoppies, nose-dive under braking and squat under power.
//
// Units: metres, kilograms, seconds. +Y is up.

const GRAV = 9.81;
// Bounds that keep the suspension solver from injecting energy. Neither binds
// during normal riding; they only cut off the numerical blow-ups.
const SHAFT_V_MAX = 6;    // m/s of shock shaft travel
const MAX_WHEEL_G = 8;    // peak normal force per wheel, in g
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;

export class Bike {
  constructor(spec, track, opts = {}) {
    this.spec = spec;
    this.track = track;
    this.isAI = !!opts.isAI;
    this.tint = opts.tint || spec.color;
    this.name = opts.name || 'Rider';

    const up = opts.upgrades || {};
    const lv = (k) => up[k] || 0;
    this.mass = spec.mass * (1 - 0.03 * lv('weight'));
    this.power = spec.power * (1 + 0.07 * lv('engine'));
    this.topSpeed = spec.topSpeed * (1 + 0.04 * lv('transmission'));
    this.brakeForce = spec.brake * (1 + 0.08 * lv('brakes'));
    this.gripMul = spec.grip * (1 + 0.05 * lv('tires'));
    this.susDamp = spec.susDamp * (1 + 0.06 * lv('suspension'));
    this.susStiff = spec.susStiff;

    this.wheelR = 0.33;
    this.wb = spec.wheelbase;
    this.inertia = this.mass * (this.wb * this.wb * 0.55 + 0.18);

    // Chassis state.
    this.x = track.startX;
    this.y = track.heightAt(track.startX) + this.wheelR + spec.seatHeight;
    this.vx = 0; this.vy = 0;
    this.ang = Math.atan(track.slopeAt(track.startX));
    this.angVel = 0;

    // Suspension units: [rear, front].
    this.rest = 0.34 + spec.travel * 0.5;
    this.wheels = [
      { ax: -this.wb * 0.5, ay: 0.02, len: this.rest, vel: 0, grounded: false, load: 0, spin: 0, cx: 0, cy: 0, drive: true },
      { ax: this.wb * 0.5, ay: 0.02, len: this.rest, vel: 0, grounded: false, load: 0, spin: 0, cx: 0, cy: 0, drive: false }
    ];

    // Rider.
    this.lean = 0;          // -1 back … +1 forward, smoothed
    this.leanTarget = 0;
    this.whip = 0;          // fake-3D yaw in radians (visual + landing penalty)
    this.whipVel = 0;
    this.scrub = 0;         // low-flying roll bias off a jump face

    this.airborne = false;
    this.airTime = 0;
    this.totalAirTime = 0;
    this.groundTime = 0;
    this.crashed = false;
    this.crashTimer = 0;
    this.ragdoll = null;
    this.rpm = 0.1;
    this.gear = 1;
    this.wheelie = 0;
    this.stoppie = 0;
    this.distance = 0;
    this.finished = false;
    this.finishTime = 0;
    this.lap = 1;

    // Scoring / feedback.
    this.perfects = 0;
    this.crashes = 0;
    this.whipDegrees = 0;
    this.style = 0;
    this.momentum = 1;      // multiplier applied to drive force after landings
    this.lastLanding = null;
    this.events = [];       // consumed by the game layer each frame

    this.stuckTimer = 0;
  }

  emit(type, data) { this.events.push({ type, ...data }); }

  // ——— helpers ————————————————————————————————————————————————
  get speed() { return Math.hypot(this.vx, this.vy); }
  get forwardSpeed() { return this.vx * Math.cos(this.ang) + this.vy * Math.sin(this.ang); }

  worldPoint(lx, ly) {
    const c = Math.cos(this.ang), s = Math.sin(this.ang);
    return { x: this.x + lx * c - ly * s, y: this.y + lx * s + ly * c };
  }

  applyForce(fx, fy, px, py) {
    this.fx += fx; this.fy += fy;
    this.torque += (px - this.x) * fy - (py - this.y) * fx;
  }

  // ——— main step ————————————————————————————————————————————————
  update(dt, input, opts = {}) {
    if (this.finished) { this.coast(dt); return; }
    const sub = 4;
    const h = dt / sub;
    for (let i = 0; i < sub; i++) this.step(h, input, opts);
  }

  coast(dt) {
    // Post-finish roll-out: physics keeps running, inputs are ignored.
    this.step(dt, { throttle: 0, brake: 0.35, lean: 0, whip: 0 }, {});
  }

  /** The height the tyre actually rides at over `px`.
   *
   *  A tyre is not a point. Sampling the terrain at a single x lets the wheel
   *  drop into the notch between two whoops and then get slammed by the next
   *  face, which is where the solver was finding the energy to throw the bike
   *  20 m into the air. Taking the highest ground across the contact patch
   *  makes the wheel ride the crests, which is what a real 21-inch front does. */
  groundUnder(px) {
    const r = this.wheelR * 0.75;
    const t = this.track;
    const a = t.heightAt(px - r), b = t.heightAt(px), c = t.heightAt(px + r);
    return a > b ? (a > c ? a : c) : (b > c ? b : c);
  }

  step(dt, input, opts) {
    const track = this.track;
    this.fx = 0; this.fy = -this.mass * GRAV; this.torque = 0;

    const crashLock = this.crashed;
    const throttle = crashLock ? 0 : clamp(input.throttle || 0, 0, 1);
    const brake = crashLock ? 0.85 : clamp(input.brake || 0, 0, 1);
    const leanIn = crashLock ? 0 : clamp(input.lean || 0, -1, 1);
    const whipIn = crashLock ? 0 : clamp(input.whip || 0, -1, 1);

    // Rider lean is a physical mass shift, not a magic torque.
    this.leanTarget = leanIn;
    this.lean += (this.leanTarget - this.lean) * clamp(dt * 9, 0, 1);
    const comShift = this.lean * 0.30;                 // metres fore/aft
    const comLift = 0.06 * Math.abs(this.lean);        // rider stands up

    // ——— Suspension + tyre forces ————————————————————————————
    const c = Math.cos(this.ang), s = Math.sin(this.ang);
    const downX = s, downY = -c;                       // chassis-down in world
    let anyGround = false;
    let driveAvail = 0;

    for (const w of this.wheels) {
      const ax = this.x + w.ax * c - w.ay * s;
      const ay = this.y + w.ax * s + w.ay * c;

      // Raycast from the anchor along chassis-down for the ground surface.
      const maxLen = this.rest + this.spec.travel * 0.5;
      let hit = -1;
      const N = 12;
      for (let i = 1; i <= N; i++) {
        const t = (maxLen * i) / N;
        const px = ax + downX * t, py = ay + downY * t;
        if (py - this.wheelR <= this.groundUnder(px)) {
          // Bisect for a smooth contact length — coarse steps make the
          // suspension chatter on steep faces.
          let lo = (maxLen * (i - 1)) / N, hi = t;
          for (let k = 0; k < 8; k++) {
            const m = (lo + hi) * 0.5;
            const my = ay + downY * m, mx = ax + downX * m;
            if (my - this.wheelR <= this.groundUnder(mx)) hi = m; else lo = m;
          }
          hit = hi;
          break;
        }
      }

      const prevLen = w.len;
      if (hit < 0) {
        // Wheel in the air: droop back to full extension.
        w.len = Math.min(maxLen, w.len + this.rest * 3 * dt);
        w.vel = 0;
        w.grounded = false;
        w.load = 0;
        w.cx = ax + downX * w.len; w.cy = ay + downY * w.len;
        // Free-rolling wheel slowly bleeds spin.
        w.spin *= Math.pow(0.6, dt);
        w.spin += (throttle * 40 - w.spin) * (w.drive ? clamp(dt * 3, 0, 1) : 0);
        continue;
      }

      const wasGrounded = w.grounded;
      anyGround = true;
      w.grounded = true;
      w.len = hit;
      // Shaft speed. Differencing the length is correct while the wheel stays
      // planted, but on the first frame of contact `prevLen` is the free-droop
      // length, so the difference is a fictitious hundred-metres-per-second of
      // compression. Fed to the damper that became the force spike that fired
      // the bike out of whoops backwards at 20 m/s. On touchdown, use the
      // chassis's actual closing speed along the suspension axis instead.
      const closing = -(this.vx * downX + this.vy * downY);
      w.vel = wasGrounded ? (w.len - prevLen) / dt : closing;
      // A real shock shaft does not move faster than this either way, and the
      // cap keeps a single steep sample from dominating the damper.
      w.vel = clamp(w.vel, -SHAFT_V_MAX, SHAFT_V_MAX);
      w.cx = ax + downX * w.len; w.cy = ay + downY * w.len;

      const compression = clamp(this.rest - w.len, -this.spec.travel, this.spec.travel * 1.2);
      const bottomOut = compression > this.spec.travel * 0.95 ? (compression - this.spec.travel * 0.95) * 90000 : 0;
      // Damping is asymmetric: stiffer in rebound, like a real shock.
      const damp = w.vel > 0 ? this.susDamp * 0.7 : this.susDamp * 1.25;
      let normalF = this.susStiff * compression - damp * w.vel + bottomOut;
      // Ceiling expressed in g rather than as a flat newton figure: 60 kN on a
      // ~100 kg bike is 60 g through one wheel, and a few substeps of that is
      // an ejection, not a landing. A violent-but-real landing is a handful of
      // g, so this bounds the solver without touching normal riding.
      normalF = clamp(normalF, 0, this.mass * GRAV * MAX_WHEEL_G);
      w.load = normalF;

      // Weight transfer: shifting the rider's mass biases the static load.
      const bias = w.drive ? 1 - this.lean * 0.55 : 1 + this.lean * 0.55;
      normalF *= clamp(bias, 0.15, 1.9);

      // Contact tangent and normal from the terrain slope.
      const slope = track.slopeAt(w.cx);
      const tl = Math.hypot(1, slope);
      const tx = 1 / tl, ty = slope / tl;

      // The spring force goes along the *ground's* normal, not the chassis's
      // own down-axis. Ground can only push away from itself. Using the
      // chassis axis meant that once the bike pitched past vertical the "down"
      // axis was nearly horizontal, the ray fired into the hillside ahead, and
      // the spring catapulted a looped-out bike backwards uphill at 18 m/s.
      this.applyForce(-ty * normalF, tx * normalF, w.cx, w.cy);

      // Velocity of the contact point.
      const rx = w.cx - this.x, ry = w.cy - this.y;
      const pvx = this.vx - this.angVel * ry;
      const pvy = this.vy + this.angVel * rx;
      const vT = pvx * tx + pvy * ty;

      const mu = this.gripMul * (this.track.biome.grip ?? 1) * (opts.gripMul ?? 1);
      // The friction circle uses a load that is capped at a physically sane
      // multiple of static weight: without this, a single stiff suspension
      // spike would hand the tyre several g of grip for one frame.
      const maxTraction = mu * Math.min(normalF, this.mass * GRAV * 1.6);

      let longF = 0;
      if (w.drive) {
        const sp = Math.max(0, vT);
        const fade = clamp(1 - sp / this.topSpeed, 0, 1);
        const curve = Math.pow(fade, 1 / this.spec.torqueCurve);
        // Thrust falls to nothing as the bike approaches its top speed, so
        // gearing — not tyre grip — is what caps outright pace.
        const target = throttle * this.power * curve * this.momentum;
        // Wheelspin: demanded force above the friction circle just spins up.
        const slipLimit = maxTraction;
        if (target > slipLimit) {
          w.spin += (target - slipLimit) / (this.mass * 0.4) * dt;
          longF = slipLimit * 0.92;                 // sliding friction
          if (throttle > 0.4 && sp > 1) this.emit('wheelspin', { x: w.cx, y: w.cy, amount: (target - slipLimit) / slipLimit });
        } else {
          longF = target;
          w.spin += (vT / this.wheelR - w.spin) * clamp(dt * 12, 0, 1);
        }
        driveAvail += normalF;
      } else {
        w.spin += (vT / this.wheelR - w.spin) * clamp(dt * 14, 0, 1);
      }

      // Braking: front bias, always friction-limited.
      if (brake > 0.01) {
        const bf = this.brakeForce * brake * (w.drive ? 0.45 : 1.0);
        const stop = Math.min(bf, maxTraction);
        longF -= Math.sign(vT || 1) * stop;
      }

      // Rolling resistance + soft-surface drag (sand and mud eat momentum).
      const roll = normalF * 0.012 * (opts.rollDrag ?? 1) + 0.32 * vT * Math.abs(vT) / this.wheels.length;
      longF -= Math.sign(vT || 0) * roll;

      longF = clamp(longF, -maxTraction, maxTraction);
      this.applyForce(tx * longF, ty * longF, w.cx, w.cy);
    }

    // ——— Air control ————————————————————————————————————————
    const wasAir = this.airborne;
    this.airborne = !anyGround;

    if (this.airborne) {
      this.airTime += dt;
      this.totalAirTime += dt;
      // Leaning in the air is rider mass rotating the bike about the CoM.
      const airTorque = -this.lean * 620 - this.angVel * 90;
      this.torque += airTorque;
      // Whip: yaw the bike out sideways. It must be brought back before
      // landing — a crossed-up landing costs traction and can end in a crash.
      this.whipVel += (whipIn * 7.0 - this.whipVel * 3.2) * dt * 6;
      this.whip += this.whipVel * dt;
      this.whip = clamp(this.whip, -1.5, 1.5);
      if (Math.abs(whipIn) < 0.05) {
        // Auto-correct, but only slowly: the rider still has to time it.
        this.whip -= this.whip * clamp(dt * 2.2, 0, 1);
        this.whipVel *= Math.pow(0.2, dt);
      }
      this.whipDegrees += Math.abs(this.whipVel) * dt * (180 / Math.PI);
      // Scrub: throttle chop + forward lean off the face flattens the jump.
      if (this.airTime < 0.45) this.scrub = lerp(this.scrub, (1 - throttle) * Math.max(0, this.lean) * -0.5, dt * 8);
      else this.scrub = lerp(this.scrub, 0, dt * 2);
      // Air drag.
      this.fx -= this.vx * Math.abs(this.vx) * 0.32;
      this.fy -= this.vy * Math.abs(this.vy) * 0.22;
    } else {
      this.groundTime += dt;
      if (wasAir) this.onLanding();
      this.airTime = 0;
      this.whip -= this.whip * clamp(dt * 9, 0, 1);
      this.whipVel *= Math.pow(0.01, dt);
      this.scrub = lerp(this.scrub, 0, dt * 6);
    }

    // Rider CoM shift torque (weight transfer on the ground) plus the rider's
    // passive balance: a real rider is constantly resisting pitch, which is
    // why a wheelie has to be provoked rather than being the default state.
    if (!this.airborne) {
      const shiftF = this.mass * GRAV * 0.55;
      this.torque += -comShift * shiftF * Math.cos(this.ang);
      const groundAng = Math.atan(track.slopeAt(this.x));
      this.torque -= wrapAngle(this.ang - groundAng) * this.mass * 4.5;
      this.torque -= this.angVel * 26;
    }

    // ——— Integrate ————————————————————————————————————————
    const ax = this.fx / this.mass, ay = this.fy / this.mass;
    this.vx += ax * dt; this.vy += ay * dt;
    const alpha = this.torque / this.inertia;
    this.angVel += alpha * dt;
    this.angVel = clamp(this.angVel, -12, 12);

    const dx = this.vx * dt;
    this.x += dx; this.y += this.vy * dt;
    this.ang = wrapAngle(this.ang + this.angVel * dt);
    if (this.x > this.distance) this.distance = this.x;

    // Safety: never let the chassis sink through the world.
    const gh = track.heightAt(this.x);
    if (this.y < gh + 0.08) {
      this.y = gh + 0.08;
      if (this.vy < 0) this.vy *= -0.05;
      if (!this.crashed && this.speed > 4) this.registerCrash('chassis');
    }

    // Engine feel.
    const spd = Math.max(0, this.forwardSpeed);
    const norm = clamp(spd / this.topSpeed, 0, 1.2);
    this.gear = this.spec.electric ? 1 : clamp(1 + Math.floor(norm * 4.2), 1, 5);
    const gearBand = this.spec.electric ? norm : (norm * 4.2) % 1;
    const target = this.airborne
      ? clamp(0.15 + throttle * 0.95, 0, 1.1)
      : clamp(0.12 + gearBand * 0.85 + throttle * 0.2, 0, 1.1);
    this.rpm += (target - this.rpm) * clamp(dt * 7, 0, 1);

    // Wheelie / stoppie tracking for scoring and HUD feedback.
    const rearDown = this.wheels[0].grounded, frontDown = this.wheels[1].grounded;
    this.wheelie = rearDown && !frontDown ? this.wheelie + dt : 0;
    this.stoppie = frontDown && !rearDown && brake > 0.3 ? this.stoppie + dt : 0;
    if (this.wheelie > 0.6) this.style += dt * 12;
    if (this.stoppie > 0.4) this.style += dt * 10;

    // Loop-out / endo / tumble detection.
    if (!this.crashed) {
      const groundAng = Math.atan(track.slopeAt(this.x));
      const rel = wrapAngle(this.ang - groundAng);
      if (!this.airborne && Math.abs(rel) > 1.6 && this.groundTime > 0.15) this.registerCrash('pitch');
      if (Math.abs(this.angVel) > 11 && this.airborne && this.airTime > 1.0) this.registerCrash('tumble');
    }

    if (this.crashed) {
      this.crashTimer += dt;
      this.updateRagdoll(dt);
    }

    // Stuck detection: a rider parked against a face or facing the wrong way
    // gets picked up rather than left to grind the track down.
    if (!this.finished && !this.crashed && Math.abs(this.forwardSpeed) < 1.2) this.stuckTimer += dt;
    else if (!this.crashed) this.stuckTimer = 0;
    if (this.stuckTimer > 2.5) { this.stuckTimer = 0; this.respawn(); }

    // Momentum multiplier bleeds back to neutral over time.
    this.momentum += (1 - this.momentum) * clamp(dt * 0.6, 0, 1);
  }

  // ——— Landings ————————————————————————————————————————————
  onLanding() {
    const track = this.track;
    const groundAng = Math.atan(track.slopeAt(this.x));
    const rel = wrapAngle(this.ang - groundAng);
    // Impact is the closing speed along the surface normal, not raw vertical
    // speed: touching down on a steep face at a matched angle is a landing,
    // dropping flat onto the same face is not.
    const nx = -Math.sin(groundAng), ny = Math.cos(groundAng);
    const impact = Math.max(0, -(this.vx * nx + this.vy * ny));
    const crossed = Math.abs(this.whip);
    const air = this.airTime;

    // Quality: 1 = perfect (matched to the landing face, wheels square).
    const angleScore = clamp(1 - Math.abs(rel) / 0.55, 0, 1);
    const whipScore = clamp(1 - crossed / 0.7, 0, 1);
    const impactScore = clamp(1 - Math.max(0, impact - 4) / 10, 0, 1);
    const quality = angleScore * 0.5 + whipScore * 0.2 + impactScore * 0.3;

    // Crashes are reserved for genuine wipeouts: everything short of that is
    // punished with lost drive instead, which keeps races flowing.
    const hardCrash = impact > 16 || (Math.abs(rel) > 1.45 && impact > 7) || (crossed > 1.3 && impact > 10);
    if (hardCrash && air > 0.25) {
      this.registerCrash('landing');
      return;
    }

    if (air > 0.22) {
      if (quality > 0.86) {
        this.perfects++;
        this.momentum = 1.14;                        // carry the drive
        this.vx *= 1.03;
        this.style += 40 + air * 25;
        this.emit('landing', { quality: 'perfect', x: this.x, y: this.y, impact, air });
      } else if (quality > 0.55) {
        this.momentum = 1.0;
        this.vx *= lerp(0.93, 1.0, (quality - 0.55) / 0.31);
        this.style += 12;
        this.emit('landing', { quality: 'good', x: this.x, y: this.y, impact, air });
      } else {
        this.momentum = 0.86;
        this.vx *= lerp(0.62, 0.9, quality / 0.55);   // case it, lose drive
        this.angVel *= 0.4;
        this.emit('landing', { quality: 'bad', x: this.x, y: this.y, impact, air });
      }
      this.lastLanding = { quality, impact, air, t: performance.now() };

      // Optional terrain deformation: heavy landings dig a rut.
      if (impact > 9 && track.pts) {
        const i = Math.round(this.x / track.step);
        const depth = Math.min(0.09, (impact - 9) * 0.006);
        for (let k = -3; k <= 3; k++) {
          const j = i + k;
          if (j > 1 && j < track.pts.length - 1) track.pts[j] -= depth * (1 - Math.abs(k) / 4);
        }
      }
    }
  }

  registerCrash(reason) {
    if (this.crashed) return;
    this.crashed = true;
    this.crashes++;
    this.crashTimer = 0;
    this.momentum = 0.8;
    this.style = Math.max(0, this.style - 60);
    this.spawnRagdoll();
    this.emit('crash', { reason, x: this.x, y: this.y, speed: this.speed });
  }

  // Simple verlet ragdoll: 6 points, distance constraints, ground collision.
  spawnRagdoll() {
    const p = (lx, ly) => {
      const w = this.worldPoint(lx, ly);
      return { x: w.x, y: w.y, px: w.x - this.vx * 0.016, py: w.y - this.vy * 0.016 };
    };
    const pts = {
      head: p(0.05, 1.05), chest: p(0.02, 0.72), hip: p(-0.05, 0.38),
      hand: p(0.42, 0.85), footR: p(-0.2, 0.05), footF: p(0.18, 0.05)
    };
    const link = (a, b) => ({ a, b, len: Math.hypot(pts[a].x - pts[b].x, pts[a].y - pts[b].y) });
    this.ragdoll = {
      pts,
      links: [link('head', 'chest'), link('chest', 'hip'), link('chest', 'hand'),
        link('hip', 'footR'), link('hip', 'footF'), link('head', 'hip')]
    };
  }

  updateRagdoll(dt) {
    const r = this.ragdoll;
    if (!r) return;
    for (const k in r.pts) {
      const p = r.pts[k];
      const vx = (p.x - p.px) * 0.985, vy = (p.y - p.py) * 0.985;
      p.px = p.x; p.py = p.y;
      p.x += vx; p.y += vy - GRAV * dt * dt;
      const g = this.track.heightAt(p.x) + 0.08;
      if (p.y < g) {
        p.y = g;
        p.px = p.x + (p.x - p.px) * 0.4;               // ground friction
      }
    }
    for (let it = 0; it < 4; it++) {
      for (const l of r.links) {
        const a = r.pts[l.a], b = r.pts[l.b];
        const dx = b.x - a.x, dy = b.y - a.y;
        const d = Math.hypot(dx, dy) || 1e-4;
        const diff = (d - l.len) / d * 0.5;
        a.x += dx * diff; a.y += dy * diff;
        b.x -= dx * diff; b.y -= dy * diff;
      }
    }
  }

  respawn() {
    const back = Math.max(this.track.startX, this.x - 10);
    this.x = back;
    this.y = this.track.heightAt(back) + this.wheelR + this.spec.seatHeight + 0.2;
    this.vx = Math.max(4, this.forwardSpeed * 0.35); this.vy = 0;
    this.ang = Math.atan(this.track.slopeAt(back));
    this.angVel = 0;
    this.whip = 0; this.whipVel = 0; this.lean = 0;
    this.crashed = false; this.ragdoll = null; this.crashTimer = 0;
    this.momentum = 0.9;
    for (const w of this.wheels) { w.len = this.rest; w.vel = 0; }
  }
}

export function wrapAngle(a) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}
