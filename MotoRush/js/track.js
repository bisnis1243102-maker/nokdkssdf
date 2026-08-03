// MotoRush — procedural track generator.
// Produces a 1D heightfield in metres plus feature metadata used by the
// renderer (props, banners, shortcuts) and the AI (lookahead planning).

import { BIOMES } from './data.js';

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const STEP = 0.4; // metres between height samples

const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (t) => t * t * (3 - 2 * t);

// ——— Feature builders ———————————————————————————————————————————————
// Each builder appends samples to `pts` (absolute heights) and returns the
// feature descriptor so the AI/renderer know what is coming.

function pushRamp(pts, base, len, rise, shape = 'smooth') {
  const n = Math.max(2, Math.round(len / STEP));
  for (let i = 1; i <= n; i++) {
    const t = i / n;
    const k = shape === 'smooth' ? smooth(t) : shape === 'kicker' ? Math.pow(t, 1.3) : t;
    pts.push(base + rise * k);
  }
  return base + rise;
}

function pushFlat(pts, base, len) {
  const n = Math.max(1, Math.round(len / STEP));
  for (let i = 0; i < n; i++) pts.push(base);
  return base;
}

function pushWhoops(pts, base, count, amp, spacing) {
  const total = count * spacing;
  const n = Math.round(total / STEP);
  for (let i = 1; i <= n; i++) {
    const x = i * STEP;
    pts.push(base + amp * (1 - Math.cos((x / spacing) * Math.PI * 2)) * 0.5);
  }
  return base;
}

function pushBerm(pts, base, len, depth) {
  // A banked, scooped turn read side-on as a compression the rider can pump.
  const n = Math.round(len / STEP);
  for (let i = 1; i <= n; i++) {
    const t = i / n;
    pts.push(base - depth * Math.sin(t * Math.PI));
  }
  return base;
}

function pushRollers(pts, base, count, amp, spacing) {
  const n = Math.round((count * spacing) / STEP);
  for (let i = 1; i <= n; i++) {
    const x = i * STEP;
    pts.push(base + amp * Math.sin((x / spacing) * Math.PI * 2) * 0.5);
  }
  return base;
}

// ——— Generator ————————————————————————————————————————————————————
export function generateTrack(opts = {}) {
  const seed = opts.seed ?? (Math.random() * 1e9) | 0;
  const rnd = mulberry32(seed);
  const biomeKey = opts.biome && BIOMES[opts.biome] ? opts.biome : 'motocross';
  const biome = BIOMES[biomeKey];
  const difficulty = Math.min(1, Math.max(0, opts.difficulty ?? 0.5));
  const targetLength = opts.length ?? lerp(600, 1200, difficulty) * lerp(0.85, 1.15, rnd());

  const pts = [0];
  const features = [];
  const props = [];
  const shortcuts = [];
  let base = 0;
  let x = 0;

  // Start straight — long enough for a gate drop and first-gear pull.
  base = pushFlat(pts, base, 22);
  x = (pts.length - 1) * STEP;

  const jumpBias = biome.jumpBias * lerp(0.7, 1.35, difficulty);
  const whoopBias = biome.whoopBias * lerp(0.6, 1.3, difficulty);

  const weightedPick = () => {
    const table = [
      ['tabletop', 1.0 * jumpBias],
      ['double', 0.85 * jumpBias],
      ['triple', 0.45 * jumpBias * difficulty * 1.6],
      ['stepup', 0.6 * jumpBias],
      ['stepdown', 0.55 * jumpBias],
      ['whoops', 0.9 * whoopBias],
      ['rollers', 0.8],
      ['berm', 0.9],
      ['rhythm', 0.7 * jumpBias],
      ['straight', 0.5],
      ['hill', 0.7 * biome.rolling]
    ];
    let total = 0; for (const [, w] of table) total += w;
    let r = rnd() * total;
    for (const [k, w] of table) { r -= w; if (r <= 0) return k; }
    return 'straight';
  };

  let lastKind = '';
  while (x < targetLength) {
    let kind = weightedPick();
    if (kind === lastKind && rnd() < 0.7) kind = weightedPick();
    lastKind = kind;
    const startX = x;
    const sev = lerp(0.7, 1.35, difficulty) * lerp(0.85, 1.15, rnd());

    switch (kind) {
      case 'tabletop': {
        const h = lerp(1.1, 2.1, rnd()) * sev;
        const face = lerp(6.5, 9.5, rnd());
        base = pushRamp(pts, base, face, h, 'kicker');
        base = pushFlat(pts, base, lerp(5, 12, rnd()) * sev);
        base = pushRamp(pts, base, face * 2.2, -h, 'smooth');
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, height: h, risk: 0.35 });
        break;
      }
      case 'double': {
        const h = lerp(1.2, 2.0, rnd()) * sev;
        const gap = lerp(6, 10, rnd()) * sev;
        base = pushRamp(pts, base, lerp(6, 8, rnd()), h, 'kicker');
        const top = base;
        base = pushRamp(pts, base, 2.2, -h * 0.95, 'linear');
        base = pushFlat(pts, base, gap);
        base = pushRamp(pts, base, lerp(4, 6, rnd()), h * 0.95, 'smooth');
        base = pushRamp(pts, base, lerp(11, 15, rnd()), -h, 'smooth');
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, height: h, gap, top, risk: 0.65 });
        break;
      }
      case 'triple': {
        const h = lerp(1.5, 2.4, rnd()) * sev;
        base = pushRamp(pts, base, 7.5, h, 'kicker');
        base = pushRamp(pts, base, 2.4, -h, 'linear');
        base = pushFlat(pts, base, lerp(8, 11, rnd()));
        base = pushRamp(pts, base, 4, h * 0.7, 'smooth');
        base = pushRamp(pts, base, 6.5, -h * 0.7, 'smooth');
        base = pushFlat(pts, base, lerp(8, 11, rnd()));
        base = pushRamp(pts, base, 4.5, h * 0.9, 'smooth');
        base = pushRamp(pts, base, 14, -h * 0.9, 'smooth');
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, height: h, risk: 0.9 });
        // Rolling the triple is the safe line; sending it is the shortcut.
        shortcuts.push({ x: startX, len: (pts.length - 1) * STEP - startX, gain: 1.4, hint: 'Send the triple' });
        break;
      }
      case 'stepup': {
        const h = lerp(1.4, 2.6, rnd()) * sev;
        base = pushRamp(pts, base, lerp(6.5, 8.5, rnd()), h * 0.6, 'kicker');
        base = pushRamp(pts, base, 2, -h * 0.15, 'linear');
        base = pushFlat(pts, base, lerp(5, 9, rnd()));
        base = pushRamp(pts, base, 4, h * 0.55, 'smooth');
        base = pushFlat(pts, base, 6);
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, height: h, risk: 0.6 });
        break;
      }
      case 'stepdown': {
        const h = lerp(1.3, 2.4, rnd()) * sev;
        base = pushRamp(pts, base, 7, h * 0.5, 'kicker');
        base = pushRamp(pts, base, 1.6, -h * 0.1, 'linear');
        base = pushFlat(pts, base, lerp(6, 10, rnd()));
        base = pushRamp(pts, base, 11, -h, 'smooth');
        base = pushFlat(pts, base, 5);
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, height: h, risk: 0.6 });
        break;
      }
      case 'whoops': {
        const count = Math.round(lerp(5, 11, rnd()) * lerp(0.8, 1.3, difficulty));
        const amp = lerp(0.5, 1.0, rnd()) * sev;
        const spacing = lerp(3.4, 4.6, rnd());
        pushWhoops(pts, base, count, amp, spacing);
        features.push({ kind, x: startX, len: count * spacing, amp, spacing, risk: 0.7 });
        break;
      }
      case 'rollers': {
        const count = Math.round(lerp(3, 6, rnd()));
        pushRollers(pts, base, count, lerp(0.6, 1.4, rnd()) * sev, lerp(6, 9, rnd()));
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, risk: 0.25 });
        break;
      }
      case 'berm': {
        pushBerm(pts, base, lerp(10, 18, rnd()), lerp(0.8, 1.8, rnd()) * sev);
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, risk: 0.2 });
        break;
      }
      case 'rhythm': {
        const n = Math.round(lerp(3, 5, rnd()));
        const h = lerp(0.8, 1.5, rnd()) * sev;
        for (let i = 0; i < n; i++) {
          base = pushRamp(pts, base, lerp(4.5, 6, rnd()), h, 'kicker');
          base = pushRamp(pts, base, lerp(7, 10, rnd()), -h, 'smooth');
          base = pushFlat(pts, base, lerp(1.5, 4, rnd()));
        }
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, count: n, risk: 0.8 });
        shortcuts.push({ x: startX, len: (pts.length - 1) * STEP - startX, gain: 1.2, hint: 'Blitz the rhythm' });
        break;
      }
      case 'hill': {
        const h = lerp(3, 9, rnd()) * biome.rolling * 0.6;
        const up = rnd() < 0.5 ? 1 : -1;
        base = pushRamp(pts, base, lerp(14, 26, rnd()), h * up, 'smooth');
        features.push({ kind, x: startX, len: (pts.length - 1) * STEP - startX, risk: 0.15 });
        break;
      }
      default: {
        base = pushFlat(pts, base, lerp(10, 22, rnd()));
        features.push({ kind: 'straight', x: startX, len: (pts.length - 1) * STEP - startX, risk: 0.05 });
      }
    }

    // Gentle drift keeps long tracks from becoming a flat ribbon.
    base += (rnd() - 0.5) * 0.6 * biome.rolling;
    base = pushFlat(pts, base, lerp(2, 6, rnd()));
    x = (pts.length - 1) * STEP;
  }

  // Finish straight + landing runoff.
  base = pushFlat(pts, base, 40);

  // Light smoothing pass removes sample-level discontinuities that would
  // otherwise read as invisible curbs to the suspension solver.
  for (let pass = 0; pass < 2; pass++) {
    for (let i = 1; i < pts.length - 1; i++) {
      pts[i] = pts[i] * 0.6 + (pts[i - 1] + pts[i + 1]) * 0.2;
    }
  }

  const length = (pts.length - 1) * STEP;

  // Scenery props (purely decorative, deterministic from the seed).
  for (let i = 0; i < length; i += 6) {
    if (rnd() < 0.35) {
      props.push({
        x: i + rnd() * 4,
        type: biome.trees ? 'tree' : biome.stadium ? 'banner' : rnd() < 0.4 ? 'flag' : 'bale',
        scale: lerp(0.7, 1.4, rnd()),
        layer: rnd() < 0.5 ? 0 : 1
      });
    }
  }

  const startX = 6;
  const finishX = length - 26;

  return {
    seed, biomeKey, biome, difficulty, pts, step: STEP, length,
    features, props, shortcuts, startX, finishX,
    name: trackName(rnd, biome),
    heightAt(px) {
      const f = px / STEP;
      if (f <= 0) return pts[0];
      if (f >= pts.length - 1) return pts[pts.length - 1];
      const i = f | 0;
      return lerp(pts[i], pts[i + 1], f - i);
    },
    slopeAt(px) {
      const h1 = this.heightAt(px - STEP), h2 = this.heightAt(px + STEP);
      return (h2 - h1) / (2 * STEP);
    },
    featureAt(px) {
      for (const f of this.features) if (px >= f.x && px < f.x + f.len) return f;
      return null;
    }
  };
}

const PREFIX = ['Copper', 'Iron', 'Hollow', 'Wild', 'Broken', 'Silver', 'Red', 'Black', 'High',
  'Thunder', 'Dust', 'Sky', 'Storm', 'Cinder', 'Glass', 'Pine', 'Salt', 'Ghost'];
const SUFFIX = ['Ridge', 'Basin', 'Creek', 'Flats', 'Canyon', 'Hollow', 'Bowl', 'Pass', 'Sands',
  'Bluff', 'Gulch', 'Park', 'Valley', 'Point', 'Rise'];

function trackName(rnd, biome) {
  const a = PREFIX[(rnd() * PREFIX.length) | 0];
  const b = SUFFIX[(rnd() * SUFFIX.length) | 0];
  return `${a} ${b}`;
}

// Deterministic "hundreds of tracks" catalogue: a seeded index the career and
// quick-race screens page through. Any seed reproduces the exact same track.
export function trackCatalogue(count = 240) {
  const rnd = mulberry32(0xC0FFEE);
  const keys = Object.keys(BIOMES);
  const list = [];
  for (let i = 0; i < count; i++) {
    const biome = keys[(rnd() * keys.length) | 0];
    const difficulty = Math.min(0.98, 0.15 + (i / count) * 0.8 + (rnd() - 0.5) * 0.12);
    list.push({ id: i, seed: (rnd() * 1e9) | 0, biome, difficulty });
  }
  return list;
}
