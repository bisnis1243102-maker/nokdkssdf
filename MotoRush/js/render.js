// MotoRush — 2.5D renderer. Canvas 2D, no external assets. Everything is
// drawn procedurally from the biome palette so a new biome is a data change.

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;

export class Camera {
  constructor() {
    this.x = 0; this.y = 0; this.zoom = 26; this.targetZoom = 26;
    this.shake = 0; this.shakeX = 0; this.shakeY = 0;
    this.slowmo = 1;
  }
  follow(bike, dt, canvas) {
    const lead = clamp(bike.vx * 0.42, -6, 14);
    const tx = bike.x + lead;
    const ty = bike.y + 1.2 + clamp(bike.vy * 0.1, -2, 3);
    const k = clamp(dt * 6.5, 0, 1);
    this.x = lerp(this.x, tx, k);
    this.y = lerp(this.y, ty, k);
    const speedNorm = clamp(Math.abs(bike.vx) / 45, 0, 1);
    const base = Math.min(canvas.width, canvas.height * 1.7) / 34;
    this.targetZoom = base * lerp(1.15, 0.82, speedNorm) * (bike.airborne ? 0.94 : 1);
    this.zoom = lerp(this.zoom, this.targetZoom, clamp(dt * 3, 0, 1));
    this.shake *= Math.pow(0.02, dt);
    this.shakeX = (Math.random() - 0.5) * this.shake;
    this.shakeY = (Math.random() - 0.5) * this.shake;
  }
  kick(amount) { this.shake = Math.min(1.6, this.shake + amount); }
  toScreen(wx, wy, canvas) {
    return {
      x: (wx - this.x + this.shakeX) * this.zoom + canvas.width / 2,
      y: canvas.height * 0.62 - (wy - this.y + this.shakeY) * this.zoom
    };
  }
}

export class Particles {
  constructor(max = 900) { this.pool = []; this.max = max; }
  spawn(x, y, vx, vy, opts = {}) {
    if (this.pool.length >= this.max) this.pool.shift();
    this.pool.push({
      x, y, vx, vy,
      life: opts.life ?? 0.6, age: 0,
      size: opts.size ?? 0.18,
      color: opts.color ?? '#c9a97e',
      grav: opts.grav ?? -2.2,
      drag: opts.drag ?? 1.4,
      glow: opts.glow ?? false,
      spin: (Math.random() - 0.5) * 6
    });
  }
  burst(x, y, n, opts = {}) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const sp = (opts.speed ?? 3) * (0.3 + Math.random());
      this.spawn(x, y, Math.cos(a) * sp + (opts.vx || 0), Math.abs(Math.sin(a)) * sp + (opts.vy || 0), opts);
    }
  }
  update(dt) {
    for (let i = this.pool.length - 1; i >= 0; i--) {
      const p = this.pool[i];
      p.age += dt;
      if (p.age >= p.life) { this.pool.splice(i, 1); continue; }
      p.vy += p.grav * dt;
      p.vx -= p.vx * p.drag * dt;
      p.vy -= p.vy * p.drag * 0.4 * dt;
      p.x += p.vx * dt; p.y += p.vy * dt;
    }
  }
  draw(ctx, cam, canvas) {
    for (const p of this.pool) {
      const t = p.age / p.life;
      const s = cam.toScreen(p.x, p.y, canvas);
      const r = p.size * cam.zoom * (1 + t * 1.4);
      if (s.x < -60 || s.x > canvas.width + 60) continue;
      ctx.globalAlpha = (1 - t) * (p.glow ? 0.9 : 0.55);
      ctx.fillStyle = p.color;
      if (p.glow) { ctx.shadowBlur = 12; ctx.shadowColor = p.color; }
      ctx.beginPath(); ctx.arc(s.x, s.y, Math.max(0.6, r), 0, Math.PI * 2); ctx.fill();
      ctx.shadowBlur = 0;
    }
    ctx.globalAlpha = 1;
  }
}

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.quality = 'high';
    this.motionBlur = true;
    this.colorblind = 'none';
    this.weatherSeed = Math.random() * 1000;
    this.trail = [];
  }

  resize(w, h, dpr) {
    const c = this.canvas;
    c.width = Math.round(w * dpr); c.height = Math.round(h * dpr);
    c.style.width = w + 'px'; c.style.height = h + 'px';
  }

  // ——— Background —————————————————————————————————————————————
  drawSky(cam, track, time) {
    const { ctx, canvas } = this;
    const b = track.biome;
    const dayT = time.dayPhase ?? 0.5; // 0 dawn → 1 dusk
    const g = ctx.createLinearGradient(0, 0, 0, canvas.height);
    const top = shade(b.sky[0], b.night ? 0 : (dayT - 0.5) * -0.18);
    const bot = shade(b.sky[1], b.night ? 0 : (dayT - 0.5) * -0.1);
    g.addColorStop(0, top); g.addColorStop(1, bot);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    if (b.night) {
      ctx.fillStyle = '#ffffff';
      for (let i = 0; i < 90; i++) {
        const sx = ((i * 733.7 + this.weatherSeed) % canvas.width);
        const sy = ((i * 419.3) % (canvas.height * 0.55));
        ctx.globalAlpha = 0.25 + ((i * 37) % 60) / 160;
        ctx.fillRect(sx, sy, 1.6, 1.6);
      }
      ctx.globalAlpha = 1;
    } else {
      // Sun + soft bloom.
      const sx = canvas.width * (0.18 + dayT * 0.6), sy = canvas.height * (0.34 - Math.sin(dayT * Math.PI) * 0.2);
      const rg = ctx.createRadialGradient(sx, sy, 0, sx, sy, canvas.height * 0.4);
      rg.addColorStop(0, 'rgba(255,246,214,0.85)');
      rg.addColorStop(0.25, 'rgba(255,236,190,0.25)');
      rg.addColorStop(1, 'rgba(255,236,190,0)');
      ctx.fillStyle = rg; ctx.fillRect(0, 0, canvas.width, canvas.height);
    }

    // Parallax hills — three layers, deterministic from the track seed.
    for (let layer = 0; layer < 3; layer++) {
      const par = 0.04 + layer * 0.07;
      const amp = canvas.height * (0.05 + layer * 0.035);
      const baseY = canvas.height * (0.52 + layer * 0.045);
      ctx.fillStyle = shade(b.ground, 0.62 - layer * 0.16);
      ctx.globalAlpha = 0.5 + layer * 0.13;
      ctx.beginPath();
      ctx.moveTo(0, canvas.height);
      const off = cam.x * cam.zoom * par;
      for (let px = 0; px <= canvas.width; px += 12) {
        const w = (px + off) * 0.004 + layer * 3.1 + track.seed * 0.0001;
        const y = baseY - (Math.sin(w) * 0.6 + Math.sin(w * 2.3 + 1.7) * 0.3 + Math.sin(w * 0.6) * 0.5) * amp;
        ctx.lineTo(px, y);
      }
      ctx.lineTo(canvas.width, canvas.height);
      ctx.closePath(); ctx.fill();
    }
    ctx.globalAlpha = 1;

    if (b.stadium) this.drawStadium(cam);
  }

  drawStadium(cam) {
    const { ctx, canvas } = this;
    const y = canvas.height * 0.5;
    ctx.fillStyle = 'rgba(20,24,44,0.9)';
    ctx.fillRect(0, y - canvas.height * 0.18, canvas.width, canvas.height * 0.22);
    // Crowd speckle. Stepping i through two constants and taking the modulus
    // lands on a regular lattice, which reads as diagonal scratches rather
    // than people, so the positions come from a hash instead.
    const hash = (n) => {
      const v = Math.sin(n * 127.1 + 311.7) * 43758.5453;
      return v - Math.floor(v);
    };
    const standTop = y - canvas.height * 0.18;
    for (let i = 0; i < 500; i++) {
      const x = ((hash(i) * canvas.width * 1.4 + cam.x * 1.5) % canvas.width + canvas.width) % canvas.width;
      const yy = standTop + hash(i + 0.5) * canvas.height * 0.2;
      ctx.fillStyle = `hsla(${Math.floor(hash(i + 0.25) * 360)},55%,${45 + hash(i + 0.75) * 25}%,0.55)`;
      ctx.fillRect(x, yy, 2.6, 2.6);
    }
    // Light rigs.
    for (let i = 0; i < 5; i++) {
      const x = canvas.width * (0.1 + i * 0.2);
      const ly = y - canvas.height * 0.24;
      ctx.fillStyle = '#e9f3ff';
      ctx.globalAlpha = 0.9; ctx.fillRect(x - 26, ly, 52, 10);
      const rg = ctx.createRadialGradient(x, ly + 8, 0, x, ly + 8, canvas.height * 0.5);
      rg.addColorStop(0, 'rgba(220,238,255,0.22)'); rg.addColorStop(1, 'rgba(220,238,255,0)');
      ctx.fillStyle = rg; ctx.globalAlpha = 1;
      ctx.fillRect(x - canvas.height * 0.5, ly, canvas.height, canvas.height);
    }
    ctx.globalAlpha = 1;
  }

  // ——— Terrain ————————————————————————————————————————————————
  drawTerrain(cam, track) {
    const { ctx, canvas } = this;
    const b = track.biome;
    const left = cam.x - canvas.width / (2 * cam.zoom) - 4;
    const right = cam.x + canvas.width / (2 * cam.zoom) + 4;
    const stepPx = 3;
    const stepW = stepPx / cam.zoom;

    ctx.beginPath();
    let first = true;
    for (let x = left; x <= right; x += stepW) {
      const p = cam.toScreen(x, track.heightAt(x), canvas);
      if (first) { ctx.moveTo(p.x, p.y); first = false; } else ctx.lineTo(p.x, p.y);
    }
    ctx.lineTo(canvas.width + 10, canvas.height + 10);
    ctx.lineTo(-10, canvas.height + 10);
    ctx.closePath();

    const g = ctx.createLinearGradient(0, canvas.height * 0.2, 0, canvas.height);
    g.addColorStop(0, b.ground);
    g.addColorStop(1, b.groundDeep);
    ctx.fillStyle = g; ctx.fill();

    // Top-soil band: a darker strip just under the surface. Without it the
    // ground reads as one flat mass and the jump profiles disappear against
    // the parallax hills behind them.
    ctx.beginPath(); first = true;
    for (let x = left; x <= right; x += stepW) {
      const p = cam.toScreen(x, track.heightAt(x), canvas);
      if (first) { ctx.moveTo(p.x, p.y); first = false; } else ctx.lineTo(p.x, p.y);
    }
    for (let x = right; x >= left; x -= stepW) {
      const p = cam.toScreen(x, track.heightAt(x) - 0.55, canvas);
      ctx.lineTo(p.x, p.y);
    }
    ctx.closePath();
    ctx.fillStyle = shade(b.groundDeep, -0.25);
    ctx.globalAlpha = 0.85;
    ctx.fill();
    ctx.globalAlpha = 1;

    // Surface highlight line (loam lip / snow crust / lava crust).
    ctx.beginPath(); first = true;
    for (let x = left; x <= right; x += stepW) {
      const p = cam.toScreen(x, track.heightAt(x), canvas);
      if (first) { ctx.moveTo(p.x, p.y); first = false; } else ctx.lineTo(p.x, p.y);
    }
    ctx.strokeStyle = shade(b.accent, 0.25);
    ctx.lineWidth = Math.max(2.5, cam.zoom * 0.13);
    ctx.globalAlpha = b.glow ? 0.95 : 0.9;
    if (b.glow) { ctx.shadowBlur = 14; ctx.shadowColor = b.accent; }
    ctx.stroke();
    ctx.shadowBlur = 0; ctx.globalAlpha = 1;

    // Ruts / texture strokes.
    if (this.quality !== 'low') {
      ctx.strokeStyle = shade(b.groundDeep, 0.12);
      ctx.globalAlpha = 0.35;
      ctx.lineWidth = 1;
      for (let x = Math.floor(left); x <= right; x += 1.6) {
        const h = track.heightAt(x);
        const p1 = cam.toScreen(x, h - 0.25, canvas);
        const p2 = cam.toScreen(x + 0.9, h - 0.55, canvas);
        ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.stroke();
      }
      ctx.globalAlpha = 1;
    }
  }

  drawProps(cam, track) {
    const { ctx, canvas } = this;
    const b = track.biome;
    const left = cam.x - canvas.width / (2 * cam.zoom) - 8;
    const right = cam.x + canvas.width / (2 * cam.zoom) + 8;
    for (const pr of track.props) {
      if (pr.x < left || pr.x > right) continue;
      const gy = track.heightAt(pr.x);
      const p = cam.toScreen(pr.x, gy, canvas);
      const s = cam.zoom * pr.scale * (pr.layer ? 0.8 : 1);
      ctx.globalAlpha = pr.layer ? 0.6 : 1;
      switch (pr.type) {
        case 'tree':
          ctx.fillStyle = '#3b2a1c'; ctx.fillRect(p.x - s * 0.08, p.y - s * 1.6, s * 0.16, s * 1.6);
          ctx.fillStyle = shade('#3f7a45', pr.layer ? -0.15 : 0.05);
          for (let i = 0; i < 3; i++) {
            ctx.beginPath();
            ctx.moveTo(p.x, p.y - s * (2.4 - i * 0.35));
            ctx.lineTo(p.x - s * (0.45 + i * 0.12), p.y - s * (1.4 - i * 0.32));
            ctx.lineTo(p.x + s * (0.45 + i * 0.12), p.y - s * (1.4 - i * 0.32));
            ctx.closePath(); ctx.fill();
          }
          break;
        case 'banner':
          ctx.fillStyle = shade(b.accent, 0.2);
          ctx.fillRect(p.x - s * 0.5, p.y - s * 1.5, s, s * 0.42);
          ctx.fillStyle = '#1a1f30';
          ctx.fillRect(p.x - s * 0.06, p.y - s * 1.5, s * 0.12, s * 1.5);
          break;
        case 'flag':
          ctx.strokeStyle = '#e8e8e8'; ctx.lineWidth = Math.max(1, s * 0.05);
          ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x, p.y - s * 1.1); ctx.stroke();
          ctx.fillStyle = pr.layer ? '#d9534f' : '#f0c419';
          ctx.beginPath();
          ctx.moveTo(p.x, p.y - s * 1.1);
          ctx.lineTo(p.x + s * 0.5, p.y - s * 0.92);
          ctx.lineTo(p.x, p.y - s * 0.74);
          ctx.closePath(); ctx.fill();
          break;
        default:
          ctx.fillStyle = shade(b.accent, -0.1);
          ctx.fillRect(p.x - s * 0.32, p.y - s * 0.42, s * 0.64, s * 0.42);
          ctx.strokeStyle = 'rgba(0,0,0,0.25)';
          ctx.strokeRect(p.x - s * 0.32, p.y - s * 0.42, s * 0.64, s * 0.42);
      }
      ctx.globalAlpha = 1;
    }

    // Start / finish gates.
    for (const [wx, label, col] of [[track.startX, 'START', '#7fe08a'], [track.finishX, 'FINISH', '#ffd166']]) {
      if (wx < left || wx > right) continue;
      const p = cam.toScreen(wx, track.heightAt(wx), canvas);
      const s = cam.zoom;
      ctx.strokeStyle = col; ctx.lineWidth = Math.max(2, s * 0.09);
      ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x, p.y - s * 3.2); ctx.stroke();
      ctx.fillStyle = col;
      ctx.fillRect(p.x, p.y - s * 3.4, s * 2.6, s * 0.6);
      ctx.fillStyle = '#0d1220';
      ctx.font = `700 ${Math.max(9, s * 0.42)}px system-ui, sans-serif`;
      ctx.fillText(label, p.x + s * 0.2, p.y - s * 2.96);
    }
  }

  // ——— Bike + rider ————————————————————————————————————————
  drawBike(cam, bike, opts = {}) {
    const { ctx, canvas } = this;
    const s = cam.zoom;
    const ghost = !!opts.ghost;
    const body = cam.toScreen(bike.x, bike.y, canvas);
    if (body.x < -200 || body.x > canvas.width + 200) return;

    // Whip is a fake-3D yaw: squash horizontally and skew the silhouette.
    const whipCos = Math.cos(bike.whip);
    const whipSkew = Math.sin(bike.whip);

    ctx.save();
    ctx.translate(body.x, body.y);
    ctx.rotate(-bike.ang + bike.scrub * 0.3);
    ctx.globalAlpha = ghost ? 0.32 : 1;

    // Shadow on the ground (projected, softened by air height).
    ctx.restore();
    const gh = bike.track.heightAt(bike.x);
    const sh = cam.toScreen(bike.x, gh, canvas);
    const airH = clamp(bike.y - gh, 0, 8);
    ctx.globalAlpha = (ghost ? 0.1 : 0.32) * clamp(1 - airH / 8, 0.12, 1);
    ctx.fillStyle = '#000';
    ctx.beginPath();
    ctx.ellipse(sh.x, sh.y, s * (0.9 + airH * 0.09), s * 0.16, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;

    ctx.save();
    ctx.translate(body.x, body.y);
    ctx.rotate(-bike.ang + bike.scrub * 0.3);
    ctx.scale(1, 1);
    ctx.globalAlpha = ghost ? 0.32 : 1;

    const col = ghost ? '#8fa6c8' : (opts.tint || bike.tint);
    const dark = shade(col, -0.35);

    // Wheels sit at their solved suspension positions, so the swingarm and
    // fork visibly work over every bump.
    const wheelLocal = bike.wheels.map(w => {
      const c = Math.cos(bike.ang), sn = Math.sin(bike.ang);
      const dx = w.cx - bike.x, dy = w.cy - bike.y;
      return { lx: dx * c + dy * sn, ly: -(-dx * sn + dy * c) };
    });

    const drawWheel = (wl, w, i) => {
      const px = wl.lx * s * (0.35 + 0.65 * Math.abs(whipCos)), py = wl.ly * s;
      const r = bike.wheelR * s;
      ctx.save(); ctx.translate(px, py);
      // Tyre.
      ctx.fillStyle = ghost ? '#5a6a80' : '#16181d';
      ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fill();
      // Knobbies.
      if (this.quality === 'high' && !ghost) {
        ctx.strokeStyle = '#2a2d34'; ctx.lineWidth = Math.max(1, r * 0.14);
        for (let k = 0; k < 10; k++) {
          const a = w.spin * 0.35 + (k / 10) * Math.PI * 2;
          ctx.beginPath();
          ctx.moveTo(Math.cos(a) * r * 0.82, Math.sin(a) * r * 0.82);
          ctx.lineTo(Math.cos(a) * r * 1.02, Math.sin(a) * r * 1.02);
          ctx.stroke();
        }
      }
      // Rim + spokes.
      ctx.strokeStyle = ghost ? '#8fa6c8' : (opts.rim || '#cfd6e0');
      ctx.lineWidth = Math.max(1, r * 0.1);
      ctx.beginPath(); ctx.arc(0, 0, r * 0.62, 0, Math.PI * 2); ctx.stroke();
      ctx.lineWidth = Math.max(0.6, r * 0.05);
      for (let k = 0; k < 6; k++) {
        const a = w.spin * 0.35 + (k / 6) * Math.PI * 2;
        ctx.beginPath(); ctx.moveTo(0, 0);
        ctx.lineTo(Math.cos(a) * r * 0.6, Math.sin(a) * r * 0.6); ctx.stroke();
      }
      // Brake disc.
      ctx.fillStyle = '#9aa3b1'; ctx.globalAlpha *= 0.8;
      ctx.beginPath(); ctx.arc(0, 0, r * 0.26, 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = ghost ? 0.32 : 1;
      ctx.restore();
    };

    const rear = wheelLocal[0], front = wheelLocal[1];
    const sx = (v) => v * s * (0.35 + 0.65 * Math.abs(whipCos));

    // Swingarm.
    ctx.strokeStyle = dark; ctx.lineWidth = s * 0.11; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(sx(-0.12), s * 0.06); ctx.lineTo(sx(rear.lx), rear.ly * s); ctx.stroke();
    // Fork legs.
    ctx.strokeStyle = '#b9c2cf'; ctx.lineWidth = s * 0.09;
    ctx.beginPath(); ctx.moveTo(sx(front.lx * 0.55), -s * 0.3); ctx.lineTo(sx(front.lx), front.ly * s); ctx.stroke();
    // Rear shock.
    ctx.strokeStyle = '#e05a5a'; ctx.lineWidth = s * 0.06;
    ctx.beginPath(); ctx.moveTo(sx(-0.1), -s * 0.22); ctx.lineTo(sx(rear.lx * 0.55), rear.ly * s * 0.6); ctx.stroke();

    drawWheel(rear, bike.wheels[0], 0);
    drawWheel(front, bike.wheels[1], 1);

    // Frame + plastics.
    ctx.fillStyle = col;
    ctx.beginPath();
    ctx.moveTo(sx(-0.55), -s * 0.02);
    ctx.lineTo(sx(-0.30), -s * 0.30);
    ctx.lineTo(sx(0.18), -s * 0.34);
    ctx.lineTo(sx(0.52), -s * 0.16);
    ctx.lineTo(sx(0.40), s * 0.02);
    ctx.lineTo(sx(-0.18), s * 0.10);
    ctx.closePath(); ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.lineWidth = Math.max(1, s * 0.03); ctx.stroke();

    // Seat + tank.
    ctx.fillStyle = '#1b1e26';
    ctx.fillRect(sx(-0.52), -s * 0.34, sx(0.42) - sx(-0.52) || s * 0.5, s * 0.1);
    // Number plate.
    ctx.fillStyle = opts.plate || '#f2f4f7';
    ctx.beginPath();
    ctx.moveTo(sx(0.34), -s * 0.34); ctx.lineTo(sx(0.6), -s * 0.2);
    ctx.lineTo(sx(0.5), -s * 0.02); ctx.lineTo(sx(0.3), -s * 0.1);
    ctx.closePath(); ctx.fill();
    if (!ghost && opts.number != null && s > 14) {
      ctx.fillStyle = '#20242e';
      ctx.font = `800 ${s * 0.26}px system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.fillText(String(opts.number), sx(0.44), -s * 0.14);
      ctx.textAlign = 'left';
    }
    // Exhaust.
    ctx.strokeStyle = '#8e97a5'; ctx.lineWidth = s * 0.08;
    ctx.beginPath(); ctx.moveTo(sx(0.1), s * 0.0); ctx.lineTo(sx(-0.62), -s * 0.12); ctx.stroke();
    // Handlebar.
    ctx.strokeStyle = '#2b3038'; ctx.lineWidth = s * 0.055;
    ctx.beginPath(); ctx.moveTo(sx(front.lx * 0.55), -s * 0.3); ctx.lineTo(sx(front.lx * 0.5), -s * 0.66); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(sx(front.lx * 0.5 - 0.16), -s * 0.7); ctx.lineTo(sx(front.lx * 0.5 + 0.16), -s * 0.62); ctx.stroke();

    if (bike.spec.glow && !ghost) {
      ctx.shadowBlur = 18; ctx.shadowColor = col;
      ctx.strokeStyle = col; ctx.lineWidth = s * 0.03;
      ctx.beginPath(); ctx.moveTo(sx(-0.55), 0); ctx.lineTo(sx(0.5), -s * 0.16); ctx.stroke();
      ctx.shadowBlur = 0;
    }

    if (!bike.crashed) this.drawRider(ctx, bike, s, whipCos, ghost, opts);
    ctx.restore();

    if (bike.crashed && bike.ragdoll) this.drawRagdoll(cam, bike, ghost);
  }

  drawRider(ctx, bike, s, whipCos, ghost, opts) {
    const sx = (v) => v * s * (0.35 + 0.65 * Math.abs(whipCos));
    const lean = bike.lean;
    const stand = clamp(Math.abs(lean) * 0.6 + (bike.airborne ? 0.35 : 0.15), 0, 1);
    const hipX = -0.12 - lean * 0.34;
    const hipY = -0.46 - stand * 0.16;
    const chestX = hipX + 0.16 + lean * 0.24;
    const chestY = hipY - 0.36 - stand * 0.1;
    const headX = chestX + 0.06 + lean * 0.12;
    const headY = chestY - 0.30;
    const handX = 0.48, handY = -0.72 - stand * 0.05;
    const footX = -0.14, footY = -0.06;

    const gear = opts.gear || {};
    const jersey = ghost ? '#8fa6c8' : (gear.jerseyColor || '#f0f3f8');
    const pants = ghost ? '#7d90ad' : (gear.pantsColor || '#232a36');
    const helmet = ghost ? '#a8bcd8' : (gear.helmetColor || '#ff5d73');

    ctx.lineCap = 'round';
    // Legs.
    ctx.strokeStyle = pants; ctx.lineWidth = s * 0.13;
    ctx.beginPath(); ctx.moveTo(sx(hipX), hipY * s); ctx.lineTo(sx(footX), footY * s); ctx.stroke();
    // Torso.
    ctx.strokeStyle = jersey; ctx.lineWidth = s * 0.17;
    ctx.beginPath(); ctx.moveTo(sx(hipX), hipY * s); ctx.lineTo(sx(chestX), chestY * s); ctx.stroke();
    // Arms.
    ctx.lineWidth = s * 0.09;
    ctx.beginPath(); ctx.moveTo(sx(chestX), chestY * s); ctx.lineTo(sx(handX), handY * s); ctx.stroke();
    // Boots.
    ctx.strokeStyle = '#14171d'; ctx.lineWidth = s * 0.1;
    ctx.beginPath(); ctx.moveTo(sx(footX), footY * s); ctx.lineTo(sx(footX + 0.14), footY * s + s * 0.02); ctx.stroke();
    // Helmet.
    ctx.fillStyle = helmet;
    ctx.beginPath(); ctx.arc(sx(headX), headY * s, s * 0.19, 0, Math.PI * 2); ctx.fill();
    // Visor / goggles.
    ctx.fillStyle = ghost ? '#c8d6ea' : '#1c2230';
    ctx.beginPath();
    ctx.ellipse(sx(headX + 0.08), headY * s - s * 0.02, s * 0.1, s * 0.055, -0.25, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = helmet;
    ctx.beginPath();
    ctx.moveTo(sx(headX + 0.02), headY * s - s * 0.12);
    ctx.lineTo(sx(headX + 0.28), headY * s - s * 0.14);
    ctx.lineTo(sx(headX + 0.14), headY * s - s * 0.03);
    ctx.closePath(); ctx.fill();
  }

  drawRagdoll(cam, bike, ghost) {
    const { ctx, canvas } = this;
    const r = bike.ragdoll; if (!r) return;
    const s = cam.zoom;
    ctx.globalAlpha = ghost ? 0.3 : 1;
    ctx.strokeStyle = '#f0f3f8'; ctx.lineWidth = s * 0.13; ctx.lineCap = 'round';
    for (const l of r.links) {
      const a = cam.toScreen(r.pts[l.a].x, r.pts[l.a].y, canvas);
      const b = cam.toScreen(r.pts[l.b].x, r.pts[l.b].y, canvas);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
    const h = cam.toScreen(r.pts.head.x, r.pts.head.y, canvas);
    ctx.fillStyle = '#ff5d73';
    ctx.beginPath(); ctx.arc(h.x, h.y, s * 0.19, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
  }

  // ——— Weather & post ————————————————————————————————————————
  drawWeather(cam, track, t) {
    const { ctx, canvas } = this;
    const b = track.biome;
    if (b.rain) {
      ctx.strokeStyle = 'rgba(190,215,240,0.45)'; ctx.lineWidth = 1.2;
      for (let i = 0; i < 260; i++) {
        const x = ((i * 137.5 + t * 900) % (canvas.width + 200)) - 100;
        const y = ((i * 311.7 + t * 1800) % canvas.height);
        ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - 6, y + 18); ctx.stroke();
      }
    }
    if (b.snowing) {
      ctx.fillStyle = 'rgba(255,255,255,0.75)';
      for (let i = 0; i < 180; i++) {
        const x = ((i * 173.3 + t * 60 + Math.sin(t + i) * 30) % (canvas.width + 60)) - 30;
        const y = ((i * 271.9 + t * 130) % canvas.height);
        ctx.beginPath(); ctx.arc(x, y, 1.6 + (i % 3) * 0.7, 0, Math.PI * 2); ctx.fill();
      }
    }
    if (b.embers) {
      for (let i = 0; i < 70; i++) {
        const x = ((i * 233.1 - t * 40) % (canvas.width + 60) + canvas.width + 60) % (canvas.width + 60) - 30;
        const y = canvas.height - ((i * 197.3 + t * 190) % canvas.height);
        ctx.fillStyle = `rgba(255,${120 + (i % 60)},60,${0.35 + (i % 5) / 12})`;
        ctx.beginPath(); ctx.arc(x, y, 1.4 + (i % 3) * 0.6, 0, Math.PI * 2); ctx.fill();
      }
    }
    if (b.heat && this.quality === 'high') {
      // Cheap heat distortion: translucent warm bands drifting upward.
      ctx.globalAlpha = 0.06; ctx.fillStyle = '#ffd7a0';
      for (let i = 0; i < 8; i++) {
        const y = canvas.height * 0.55 + Math.sin(t * 1.4 + i) * 12 + i * 9;
        ctx.fillRect(0, y, canvas.width, 5);
      }
      ctx.globalAlpha = 1;
    }
  }

  vignetteAndGrade(track, intensity) {
    const { ctx, canvas } = this;
    const rg = ctx.createRadialGradient(
      canvas.width / 2, canvas.height / 2, canvas.height * 0.35,
      canvas.width / 2, canvas.height / 2, canvas.height * 0.95);
    rg.addColorStop(0, 'rgba(0,0,0,0)');
    rg.addColorStop(1, `rgba(0,0,0,${0.32 + intensity * 0.18})`);
    ctx.fillStyle = rg; ctx.fillRect(0, 0, canvas.width, canvas.height);
    if (this.colorblind !== 'none') this.applyColorblind();
  }

  applyColorblind() {
    // Accessibility tint pass: shifts the palette away from the confusable
    // axis rather than attempting a full LMS simulation (cheap enough to
    // leave on at 120 FPS).
    const { ctx, canvas } = this;
    const map = {
      protanopia: 'rgba(60,110,255,0.06)',
      deuteranopia: 'rgba(255,160,60,0.06)',
      tritanopia: 'rgba(255,60,140,0.06)'
    };
    const c = map[this.colorblind];
    if (!c) return;
    ctx.fillStyle = c; ctx.fillRect(0, 0, canvas.width, canvas.height);
  }

  speedLines(bike) {
    if (!this.motionBlur || this.quality === 'low') return;
    const { ctx, canvas } = this;
    const sp = Math.abs(bike.vx);
    const a = clamp((sp - 22) / 30, 0, 0.5);
    if (a <= 0.01) return;
    ctx.globalAlpha = a;
    ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    for (let i = 0; i < 16; i++) {
      const y = (i * 97.3 % canvas.height);
      const len = 40 + (i % 5) * 40;
      const x = canvas.width - ((i * 53 + performance.now() * 0.6) % (canvas.width + 200));
      ctx.lineWidth = 1.4;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + len, y); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }
}

export function shade(hex, amt) {
  const c = hex.replace('#', '');
  const n = parseInt(c.length === 3 ? c.split('').map(x => x + x).join('') : c, 16);
  let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  if (amt >= 0) { r += (255 - r) * amt; g += (255 - g) * amt; b += (255 - b) * amt; }
  else { r *= 1 + amt; g *= 1 + amt; b *= 1 + amt; }
  return `rgb(${r | 0},${g | 0},${b | 0})`;
}
