// MotoRush — racing AI.
//
// The AI drives the exact same physics model as the player through the same
// input struct: throttle, brake, lean, whip. It has no special traction and
// no rubber-band forces — difficulty comes from how well it reads the track
// and how often it makes mistakes.

import { wrapAngle } from './physics.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

export class AIController {
  constructor(bike, personality, difficulty = 0.7) {
    this.bike = bike;
    this.p = personality;
    this.skill = clamp(personality.skill * (0.65 + difficulty * 0.45), 0.3, 1.0);
    this.mistakeTimer = 0;
    this.mistake = null;
    this.reaction = 0;
    this.cached = { throttle: 0, brake: 0, lean: 0, whip: 0 };
  }

  // Ballistic projection to find where and on what slope we will touch down.
  predictLanding(track) {
    const b = this.bike;
    let x = b.x, y = b.y, vx = b.vx, vy = b.vy;
    const dt = 0.05;
    for (let i = 0; i < 90; i++) {
      vy -= 9.81 * dt;
      x += vx * dt; y += vy * dt;
      if (y <= track.heightAt(x) + b.wheelR + 0.3) {
        return { x, y, slope: track.slopeAt(x), t: i * dt, vy };
      }
    }
    return null;
  }

  update(dt, track) {
    const b = this.bike;
    this.reaction -= dt;
    if (this.reaction > 0) return this.cached;
    // Lower-skill riders think less often — that lag is most of the gap.
    this.reaction = (1 - this.skill) * 0.16 + 0.02;

    // Occasional genuine mistakes: a missed shift, a grabbed brake, a
    // hopelessly over-rotated jump. They cost real time.
    this.mistakeTimer -= dt;
    if (!this.mistake && this.mistakeTimer <= 0 && Math.random() < this.p.mistake) {
      const kinds = ['chop', 'grab', 'overlean', 'late'];
      this.mistake = { kind: kinds[(Math.random() * kinds.length) | 0], t: 0.25 + Math.random() * 0.7 };
      this.mistakeTimer = 2.5;
    }
    if (this.mistake) {
      this.mistake.t -= dt;
      if (this.mistake.t <= 0) this.mistake = null;
    }

    let throttle = 0, brake = 0, lean = 0, whip = 0;
    const speed = Math.max(0, b.forwardSpeed);

    if (b.crashed) {
      this.cached = { throttle: 0, brake: 0, lean: 0, whip: 0 };
      return this.cached;
    }

    if (b.airborne) {
      const land = this.predictLanding(track);
      if (land) {
        const targetAng = Math.atan(land.slope);
        const err = wrapAngle(targetAng - b.ang);
        // Positive lean pitches the nose down; sign follows the error.
        lean = clamp(-err * (2.2 + this.skill * 2.0) - b.angVel * 0.28, -1, 1);
        // Stay on the gas mid-air to keep rear-wheel gyro unless very nose-high.
        throttle = err < -0.25 ? 0.15 : 0.55 + this.skill * 0.4;
        // Style riders whip when there is time, and always bring it back.
        const timeLeft = land.t;
        if (b.airTime > 0.35 && timeLeft > 0.55 && this.p.risk > 0.5) {
          whip = (this.p.risk - 0.4) * (b.id2 || 1);
          whip = clamp(whip, -1, 1) * (this.skill > 0.75 ? 1 : 0.4);
        } else if (timeLeft < 0.5) {
          whip = clamp(-b.whip * 3, -1, 1);
        }
      } else {
        lean = clamp(-b.angVel * 0.3, -1, 1);
        throttle = 0.6;
      }
    } else {
      // On the ground: read the next 25 m for faces and holes.
      let steepUp = 0, steepDown = 0, roughness = 0;
      const ahead = 6 + speed * 0.9;
      let prev = track.heightAt(b.x);
      for (let d = 1; d < ahead; d += 1.5) {
        const h = track.heightAt(b.x + d);
        const s = (h - prev) / 1.5;
        prev = h;
        const w = 1 - d / ahead;
        if (s > 0.25) steepUp = Math.max(steepUp, s * w);
        if (s < -0.25) steepDown = Math.max(steepDown, -s * w);
        roughness += Math.abs(s) * w;
      }

      const feature = track.featureAt(b.x + 4);
      const risky = feature && feature.risk > 0.6;

      // Base pace: skill sets how close to the limit they run.
      throttle = 0.55 + this.skill * 0.45;

      if (risky && this.p.risk < feature.risk && speed > 14) {
        // Cautious personalities roll the big stuff.
        throttle *= 0.7;
        brake = 0.25 * (1 - this.p.risk);
      }
      if (roughness > 3.2 && this.skill < 0.85) throttle *= 0.85;

      // Preload the suspension into a face, then lean back over the lip.
      if (steepUp > 0.2) lean = -0.5 - this.skill * 0.35;
      else if (steepDown > 0.25) lean = 0.35 + this.skill * 0.3;
      else lean = clamp(-b.angVel * 0.25 + (b.wheelie > 0.35 ? 0.55 : 0), -1, 1);

      // Do not loop it out under power.
      if (b.wheelie > 0.5) { throttle *= 0.6; lean = 0.8; }
      // Aggression sets willingness to brake late into compressions.
      if (speed > b.topSpeed * (0.85 + this.p.aggression * 0.15) && roughness > 2.5) brake = 0.2;
    }

    if (this.mistake) {
      switch (this.mistake.kind) {
        case 'chop': throttle *= 0.15; break;
        case 'grab': brake = 0.8; throttle = 0; break;
        case 'overlean': lean = clamp(lean + (Math.random() < 0.5 ? -1.2 : 1.2), -1, 1); break;
        case 'late': /* reacts a beat late */ this.reaction = 0.25; break;
      }
    }

    this.cached = {
      throttle: clamp(throttle, 0, 1),
      brake: clamp(brake, 0, 1),
      lean: clamp(lean, -1, 1),
      whip: clamp(whip, -1, 1)
    };
    return this.cached;
  }
}

// Adaptive difficulty: nudges the field's difficulty scalar toward keeping
// races close without ever touching in-race physics.
export class AdaptiveDifficulty {
  constructor(initial = 0.6) { this.value = initial; this.history = []; }
  record(finishPosition, fieldSize) {
    const norm = 1 - (finishPosition - 1) / Math.max(1, fieldSize - 1); // 1 = win
    this.history.push(norm);
    if (this.history.length > 6) this.history.shift();
    const avg = this.history.reduce((a, b) => a + b, 0) / this.history.length;
    this.value = clamp(this.value + (avg - 0.62) * 0.12, 0.25, 1);
    return this.value;
  }
}
