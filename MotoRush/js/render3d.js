// MotoRush — the 3D renderer. Real WebGL geometry: the track is an extruded
// ribbon, the bike is an assembled set of parts posed from the solved
// suspension, and the rider is a jointed figure. Nothing here is a sprite.
//
// It deliberately presents the same surface as the 2D renderer in render.js —
// drawSky / drawTerrain / drawProps / drawBike / drawWeather / speedLines /
// vignetteAndGrade plus a `ctx` and a `canvas` — so game.js draws a race
// without knowing which renderer it has. Effects that are genuinely
// screen-space (particles, rain, vignette) stay 2D and are composited from a
// transparent overlay canvas by the 2D renderer, which already does them well.

import { Renderer as Renderer2D, shade } from './render.js';
import {
  mat4, multiply, perspective, lookAt, compose, project,
  createProgram, MeshBuilder, rgb, mix, scaleRGB
} from './gl.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;

// Shared bike anchors, in metres, in bike-local space. These are the same
// numbers the iOS build's `Rig` uses, so a change to the silhouette is made
// once and both renderers agree.
export const RIG = {
  wheelbase: 1.34,
  axleY: -0.30,
  rearAxle: [-0.67, -0.30],
  frontAxle: [0.67, -0.30],
  swingPivot: [-0.10, -0.16],
  get swingRest() {
    return Math.atan2(this.rearAxle[1] - this.swingPivot[1],
                      this.rearAxle[0] - this.swingPivot[0]);
  }
};

// The track's lateral profile: (z offset, height offset). Centre is flat, the
// lip rises just outside the racing line, then the ground falls away.
//
// It is deliberately asymmetric. The camera always sits on the +z side, and a
// skirt as wide there as on the far side fills the bottom third of the frame
// with a lit brown cliff between the viewer and the racing line. The near side
// therefore falls away sooner and steeper, where the lip itself hides it.
// The far side runs out further than it needs to for its own sake: it is the
// ground the two rows of scenery stand on.
const SECTION = [
  [-9.0, -4.2], [-6.2, -2.6], [-3.6, 0.55], [-2.9, 0], [0, 0], [2.9, 0], [3.6, 0.55], [4.4, -3.4]
];

// Where the scenery rows sit, and how far the skirt has dropped by then. Both
// rows are kept close to track level: further down the slope they disappear
// behind the ribbon entirely from a near-level camera, which is how the first
// pass ended up with scenery nobody could see.
const PROP_ROWS = [
  { z: -4.4, drop: -0.42 },   // close row, just outside the lip
  { z: -6.6, drop: -2.83 }    // back row, down the slope
];

// ——— Shaders ————————————————————————————————————————————————

const SCENE_VS = `
precision highp float;
attribute vec3 aPos;
attribute vec3 aNormal;
attribute vec3 aColor;
uniform mat4 uViewProj;
uniform mat4 uModel;
varying vec3 vNormal;
varying vec3 vColor;
varying float vDepth;
varying float vHeight;
void main() {
  vec4 world = uModel * vec4(aPos, 1.0);
  gl_Position = uViewProj * world;
  vNormal = mat3(uModel) * aNormal;
  vColor = aColor;
  vDepth = gl_Position.w;
  vHeight = world.y;
}`;

const SCENE_FS = `
precision highp float;
varying vec3 vNormal;
varying vec3 vColor;
varying float vDepth;
varying float vHeight;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uAmbient;
uniform vec3 uFogColor;
uniform float uFogNear;
uniform float uFogFar;
uniform float uAlpha;
void main() {
  vec3 N = normalize(vNormal);
  // Two-sided: the meshes are built from primitives whose winding is not
  // guaranteed, so face culling is off and the normal is flipped to face the
  // camera instead. Cheaper than auditing every primitive's winding.
  if (!gl_FrontFacing) N = -N;
  float d = max(dot(N, uSunDir), 0.0);
  // A dim bounce off the ground keeps undersides from going flat black.
  float bounce = max(-N.y, 0.0) * 0.18;
  vec3 lit = vColor * (uAmbient + uSunColor * d + uSunColor * bounce);
  // Rim light along the silhouette; this is what stops the bike from reading
  // as a dark blob against dark dirt.
  float rim = pow(1.0 - abs(N.z), 3.0) * 0.12;
  lit += uSunColor * rim;
  float fog = clamp((vDepth - uFogNear) / (uFogFar - uFogNear), 0.0, 1.0);
  fog *= fog;
  gl_FragColor = vec4(mix(lit, uFogColor, fog), uAlpha);
}`;

const SKY_VS = `
precision highp float;
attribute vec3 aPos;
varying vec2 vUV;
void main() { vUV = aPos.xy * 0.5 + 0.5; gl_Position = vec4(aPos.xy, 0.999, 1.0); }`;

const SKY_FS = `
precision highp float;
varying vec2 vUV;
uniform vec3 uTop;
uniform vec3 uBottom;
uniform vec2 uSun;
uniform float uSunStrength;
void main() {
  vec3 col = mix(uBottom, uTop, pow(vUV.y, 0.85));
  float d = distance(vUV * vec2(1.0, 0.62), uSun * vec2(1.0, 0.62));
  col += uSunStrength * vec3(1.0, 0.92, 0.75) * exp(-d * 16.0) * 0.30;
  col += uSunStrength * vec3(1.0, 0.97, 0.9) * smoothstep(0.030, 0.012, d) * 0.7;
  gl_FragColor = vec4(col, 1.0);
}`;

// ——— Renderer ————————————————————————————————————————————————

export class Renderer3D {
  constructor(canvas) {
    this.canvas = canvas;
    const opts = { antialias: true, alpha: false, depth: true, powerPreference: 'high-performance' };
    const gl = canvas.getContext('webgl2', opts) || canvas.getContext('webgl', opts);
    if (!gl) throw new Error('WebGL unavailable');
    this.gl = gl;
    this.isGL2 = typeof WebGL2RenderingContext !== 'undefined' &&
                 gl instanceof WebGL2RenderingContext;
    if (!this.isGL2) gl.getExtension('OES_element_index_uint');

    this.scene = createProgram(gl, SCENE_VS, SCENE_FS);
    this.sky = createProgram(gl, SKY_VS, SKY_FS);

    // Fullscreen triangle for the sky pass.
    this.skyBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.skyBuf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), gl.STATIC_DRAW);

    gl.enable(gl.DEPTH_TEST);
    gl.disable(gl.CULL_FACE);
    gl.clearColor(0.1, 0.12, 0.16, 1);

    // The screen-space half of the picture: particles, rain, vignette and
    // speed lines run on a transparent 2D canvas stacked over the GL one.
    this.overlay = document.createElement('canvas');
    this.overlay.id = 'overlay';
    canvas.parentNode.insertBefore(this.overlay, canvas.nextSibling);
    this.hud = new Renderer2D(this.overlay);
    this.ctx = this.hud.ctx;

    this._quality = 'high';
    this._motionBlur = true;
    this._colorblind = 'none';

    this.viewProj = mat4();
    this.model = mat4();
    this.terrain = null;      // { seed, mesh }
    this.propsMesh = null;    // { seed, mesh }
    this.bikeCache = new Map();
    this.shadowMesh = null;
    this.is3D = true;
  }

  // The overlay runs the screen-space passes, so every display setting has to
  // reach it too — otherwise turning motion blur off would only half work.
  set colorblind(v) { this._colorblind = v; this.hud.colorblind = v; }
  get colorblind() { return this._colorblind; }
  set quality(v) { this._quality = v; this.hud.quality = v; }
  get quality() { return this._quality; }
  set motionBlur(v) { this._motionBlur = v; this.hud.motionBlur = v; }
  get motionBlur() { return this._motionBlur; }

  resize(w, h, dpr) {
    const c = this.canvas;
    c.width = Math.round(w * dpr); c.height = Math.round(h * dpr);
    c.style.width = w + 'px'; c.style.height = h + 'px';
    this.hud.resize(w, h, dpr);
    this.gl.viewport(0, 0, c.width, c.height);
  }

  // ——— Camera ————————————————————————————————————————————————

  /** Derive a perspective camera that frames the scene exactly as the 2D
   *  camera's metres-per-pixel zoom did, so the follow logic, the HUD and the
   *  particle projection all keep working untouched. */
  setCamera(cam, canvas) {
    const H = canvas.height, W = canvas.width;
    const fov = 0.87;                                  // ~50°
    const zoom = Math.max(4, cam.zoom);
    // At the plane z = 0 this distance gives exactly `zoom` pixels per metre.
    const dist = (H / 2) / (Math.tan(fov / 2) * zoom);
    // The 2D camera put the focus at 62% down the screen rather than centred.
    const targetY = cam.y + (0.12 * H) / zoom;
    const tx = cam.x + cam.shakeX, ty = targetY + cam.shakeY;

    // A few degrees of elevation and yaw: enough for the ribbon and the props
    // to read as solid without leaving the side-on framing the game is built
    // around. Keep the elevation small — looking down on the ribbon puts its
    // near skirt between the camera and the racing line, which is the same
    // mistake the first Blender track preview made.
    const pitch = 0.145, yaw = 0.10;
    const eye = [
      tx - Math.sin(yaw) * Math.cos(pitch) * dist,
      ty + Math.sin(pitch) * dist,
      Math.cos(yaw) * Math.cos(pitch) * dist
    ];
    const view = lookAt(mat4(), eye, [tx, ty, 0], [0, 1, 0]);
    const proj = perspective(mat4(), fov, W / H, 0.25, Math.max(400, dist * 8));
    multiply(this.viewProj, proj, view);
    this.eye = eye;
    this.fogNear = dist * 1.1;
    this.fogFar = dist * 1.1 + 190;

    // Particles and any other world-anchored 2D effect project through the
    // real matrix rather than the old flat mapping. `scale` is the pixels per
    // metre at that point's depth, so a dust cloud thrown out ahead of the
    // bike shrinks with distance instead of staying screen-sized.
    const k = (H / 2) / Math.tan(fov / 2);
    cam.projector = (wx, wy, cv) => {
      const p = project(this.viewProj, wx, wy, 0, cv.width, cv.height);
      p.scale = k / Math.max(0.5, p.w);
      return p;
    };
  }

  // ——— Sky ————————————————————————————————————————————————

  drawSky(cam, track, time) {
    const gl = this.gl;
    this.setCamera(cam, this.canvas);
    const b = track.biome;
    const dayT = time.dayPhase ?? 0.5;

    const top = rgb(shade(b.sky[0], b.night ? 0 : (dayT - 0.5) * -0.18));
    const bottom = rgb(shade(b.sky[1], b.night ? 0 : (dayT - 0.5) * -0.1));
    this.fogColor = mix(bottom, top, 0.25);
    this.night = !!b.night;

    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.depthMask(true);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    gl.useProgram(this.sky.prog);
    gl.disable(gl.DEPTH_TEST);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.skyBuf);
    gl.enableVertexAttribArray(this.sky.attribs.aPos);
    gl.vertexAttribPointer(this.sky.attribs.aPos, 3, gl.FLOAT, false, 0, 0);
    gl.uniform3fv(this.sky.uniforms.uTop, top);
    gl.uniform3fv(this.sky.uniforms.uBottom, bottom);
    gl.uniform2f(this.sky.uniforms.uSun, 0.72, 0.80);
    gl.uniform1f(this.sky.uniforms.uSunStrength, b.night ? 0.12 : 1.0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.enable(gl.DEPTH_TEST);

    // The overlay is redrawn from scratch every frame; clearing it here keeps
    // the two canvases in lockstep with one call site.
    this.ctx.setTransform(1, 0, 0, 1, 0, 0);
    this.ctx.clearRect(0, 0, this.overlay.width, this.overlay.height);

    this.beginScene(b);
  }

  /** Bind the lit program and set the per-frame lighting for this biome. */
  beginScene(biome) {
    const gl = this.gl, u = this.scene.uniforms;
    gl.useProgram(this.scene.prog);
    gl.uniformMatrix4fv(u.uViewProj, false, this.viewProj);
    const sun = biome.night ? [-0.25, 0.86, 0.44] : [-0.42, 0.78, 0.46];
    const l = Math.hypot(sun[0], sun[1], sun[2]);
    gl.uniform3f(u.uSunDir, sun[0] / l, sun[1] / l, sun[2] / l);
    if (biome.night) {
      gl.uniform3f(u.uSunColor, 0.55, 0.60, 0.78);
      gl.uniform3f(u.uAmbient, 0.34, 0.36, 0.46);
    } else {
      gl.uniform3f(u.uSunColor, 0.92, 0.88, 0.78);
      gl.uniform3f(u.uAmbient, 0.42, 0.45, 0.52);
    }
    gl.uniform3fv(u.uFogColor, this.fogColor);
    gl.uniform1f(u.uFogNear, this.fogNear);
    gl.uniform1f(u.uFogFar, this.fogFar);
    gl.uniform1f(u.uAlpha, 1);
  }

  drawMesh(mesh, model, alpha = 1) {
    const gl = this.gl, u = this.scene.uniforms;
    gl.uniformMatrix4fv(u.uModel, false, model);
    gl.uniform1f(u.uAlpha, alpha);
    if (alpha < 1) {
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      gl.depthMask(false);
    }
    mesh.draw(this.scene.attribs);
    if (alpha < 1) { gl.disable(gl.BLEND); gl.depthMask(true); }
  }

  // ——— Terrain ————————————————————————————————————————————————

  drawTerrain(cam, track) {
    if (!this.terrain || this.terrain.seed !== track.seed) {
      if (this.terrain) this.terrain.mesh.dispose();
      this.terrain = { seed: track.seed, mesh: this.buildTerrain(track) };
    }
    this.drawMesh(this.terrain.mesh, compose(this.model, 0, 0, 0, 0, 0, 0, 1));
  }

  buildTerrain(track) {
    const b = track.biome;
    const surface = rgb(b.ground);
    const deep = rgb(b.groundDeep);
    const accent = rgb(b.accent);
    const mb = new MeshBuilder();
    const step = 0.4;
    const rows = Math.ceil(track.length / step) + 1;
    const cols = SECTION.length;

    // A cheap deterministic hash so the dirt has tonal variation instead of
    // reading as one flat wash — the same complaint the 2D pass had.
    const hash = (n) => {
      const v = Math.sin(n * 127.1 + 311.7) * 43758.5453;
      return v - Math.floor(v);
    };

    // Vertical gradient of the lateral profile at each section vertex, needed
    // for the normal.
    const grad = SECTION.map((p, i) => {
      const a = SECTION[Math.max(0, i - 1)], c = SECTION[Math.min(cols - 1, i + 1)];
      return c[0] === a[0] ? 0 : (c[1] - a[1]) / (c[0] - a[0]);
    });

    for (let r = 0; r < rows; r++) {
      const x = r * step;
      const h = track.heightAt(x);
      const s = track.slopeAt(x);
      for (let c = 0; c < cols; c++) {
        const [z, dy] = SECTION[c];
        const g = grad[c];
        const nl = Math.hypot(-s, 1, -g);
        // Racing line reads lighter and slightly polished; the lip catches the
        // accent colour; the outer skirt falls off into shadow.
        const az = Math.abs(z);
        let col;
        if (az <= 2.6) col = mix(surface, deep, 0.08 + 0.16 * (az / 2.6));
        else if (az <= 2.9) col = scaleRGB(mix(surface, deep, 0.55), 0.80);  // rut edge
        else if (az <= 3.6) col = scaleRGB(accent, 1.10);                    // lip catches light
        else col = mix(deep, accent, 0.25 * (1 - (az - 3.6) / 2.6));
        const n = hash(r * 0.37 + c * 5.13);
        col = scaleRGB(col, 0.90 + n * 0.20);
        // The pair of ruts the field wears either side of centre. Without them
        // the ribbon reads as a smooth dune rather than a racing line.
        if (az > 0.7 && az < 1.7) col = scaleRGB(col, 0.86);
        mb.verts.push(x, h + dy, z, -s / nl, 1 / nl, -g / nl, col[0], col[1], col[2]);
      }
    }
    for (let r = 0; r < rows - 1; r++) {
      for (let c = 0; c < cols - 1; c++) {
        const a = r * cols + c, d = (r + 1) * cols + c;
        mb.idx.push(a, d, d + 1, a, d + 1, a + 1);
      }
    }
    return mb.upload(this.gl);
  }

  // ——— Scenery ————————————————————————————————————————————————

  drawProps(cam, track) {
    if (!this.propsMesh || this.propsMesh.seed !== track.seed ||
        this.propsMesh.quality !== this.quality) {
      if (this.propsMesh) this.propsMesh.mesh.dispose();
      this.propsMesh = {
        seed: track.seed, quality: this.quality, mesh: this.buildProps(track)
      };
    }
    if (this.propsMesh.mesh.count) {
      this.drawMesh(this.propsMesh.mesh, compose(this.model, 0, 0, 0, 0, 0, 0, 1));
    }
  }

  buildProps(track) {
    const mb = new MeshBuilder();
    const b = track.biome;
    const low = this.quality === 'low';

    // Everything stands on the far side. The camera sits out on +z, so a prop
    // on the near side is a prop between the viewer and the race.
    for (const p of track.props) {
      const row = PROP_ROWS[p.layer ? 1 : 0];
      const gy = track.heightAt(p.x) + row.drop;
      const z = row.z;
      const s = p.scale;
      mb.push();
      mb.translate(p.x, gy, z);
      switch (p.type) {
        case 'tree': {
          const trunk = rgb('#4a3524');
          const leaf = rgb(b.snowing ? '#c9dcd2' : '#3f6b3a');
          mb.push(); mb.translate(0, 1.4 * s, 0);
          mb.cylinder(0.16 * s, 2.8 * s, trunk, low ? 5 : 8, false, 0.11 * s); mb.pop();
          for (let i = 0; i < (low ? 2 : 3); i++) {
            mb.push();
            mb.translate(0, (2.6 + i * 1.05) * s, 0);
            mb.cylinder((1.25 - i * 0.32) * s, 1.5 * s,
                        scaleRGB(leaf, 1 - i * 0.06), low ? 6 : 9, true, 0.05);
            mb.pop();
          }
          break;
        }
        case 'bale': {
          // Straw bales lie on their side, axis across the track.
          mb.push();
          mb.translate(0, 0.42 * s, 0);
          mb.rotate(Math.PI / 2, 0, 0);
          mb.cylinder(0.42 * s, 1.1 * s, rgb('#d8c274'), low ? 6 : 10);
          mb.pop();
          break;
        }
        case 'flag': {
          mb.push(); mb.translate(0, 1.1 * s, 0);
          mb.cylinder(0.05, 2.2 * s, rgb('#c9ced6'), 5); mb.pop();
          // No yaw on the panel: plane() builds it facing +z, which is where
          // the camera is. Turning it broadside to the track makes it edge-on
          // and it vanishes.
          mb.push();
          mb.translate(0.45 * s, 1.85 * s, 0);
          mb.plane(0.9 * s, 0.6 * s, rgb(p.x % 2 < 1 ? '#e2503f' : '#f5d03a'));
          mb.pop();
          break;
        }
        default: {   // 'banner' — a gantry arching over the track
          const post = rgb('#3b4250');
          const h = 5.4 * s;
          for (const px of [-0.6, 0.6]) {
            mb.push(); mb.translate(px, h / 2, 0);
            mb.cylinder(0.13, h, post, 6); mb.pop();
          }
          mb.push(); mb.translate(0, h, 0);
          mb.rotate(0, 0, Math.PI / 2);
          mb.cylinder(0.11, 1.4, post, 6); mb.pop();
          mb.push(); mb.translate(0, h * 0.72, 0);
          mb.plane(2.6 * s, 1.1 * s, rgb('#2b6cb0'));
          mb.pop();
          break;
        }
      }
      mb.pop();
    }

    if (b.stadium && !low) this.buildStands(mb, track);
    return mb.upload(this.gl);
  }

  /** Raked stands behind the far scenery row for the indoor biomes. Stands on
   *  the near side would sit between the camera and the track, so there are
   *  none — the same reason the props are one-sided. The crowd is a field
   *  of small quads scattered by a hash — stepping a modulus over the rake
   *  lines every head up into a visible lattice, which is exactly the moiré
   *  the 2D stadium used to have. */
  buildStands(mb, track) {
    const hash = (n) => {
      const v = Math.sin(n * 127.1 + 311.7) * 43758.5453;
      return v - Math.floor(v);
    };
    const crowdCols = ['#e2503f', '#f5d03a', '#5ef2d6', '#8fd9ff', '#f0f3f8',
                       '#c88bff', '#8bf05a', '#ff9a3b'];
    const concrete = rgb('#4a5160');
    const stepD = 12, tiers = 7;
    for (let x = 0; x < track.length; x += stepD) {
      const base = track.heightAt(x) - 4.4;
      for (const side of [-1]) {
        mb.push();
        mb.translate(x + stepD / 2, 0, side * 9.5);
        // Back wall closing off the top of the rake.
        mb.push();
        mb.translate(0, base + 1.4 + tiers * 0.78, side * ((tiers - 1) * 0.95 + 0.8));
        mb.box(stepD, 2.4, 0.3, scaleRGB(concrete, 0.5));
        mb.pop();
        for (let t = 0; t < tiers; t++) {
          const y = base + 0.9 + t * 0.78;
          const z = side * (t * 0.95);
          // Fill from the ground up to this step, so the rake is a solid
          // staircase. One box enclosing the whole bank would swallow the
          // seats standing on it.
          const fillTop = y - 0.25;
          mb.push(); mb.translate(0, (base + fillTop) / 2, z);
          mb.box(stepD, Math.max(0.1, fillTop - base), 0.95, scaleRGB(concrete, 0.62));
          mb.pop();
          mb.push(); mb.translate(0, y, z);
          mb.box(stepD, 0.5, 0.95, scaleRGB(concrete, 0.8 + t * 0.03));
          mb.pop();
          const n = Math.max(2, Math.round(stepD / 1.1));
          for (let i = 0; i < n; i++) {
            const seed = x * 13.7 + t * 7.3 + i * 3.1;
            if (hash(seed) < 0.22) continue;      // empty seats
            const cx = -stepD / 2 + (i + hash(seed + 91) * 0.8) * (stepD / n);
            const col = rgb(crowdCols[(hash(seed + 17) * crowdCols.length) | 0]);
            mb.push();
            mb.translate(cx, y + 0.52, z + side * 0.1);
            mb.box(0.32, 0.5, 0.28, col);
            mb.pop();
          }
        }
        mb.pop();
      }
    }
  }

  // ——— Bike ————————————————————————————————————————————————

  drawBike(cam, bike, opts = {}) {
    const gl = this.gl;
    const ghost = !!opts.ghost;
    // Cheap horizontal cull; the ribbon still draws behind it.
    if (Math.abs(bike.x - cam.x) > 90) return;

    const tint = ghost ? '#8fa6c8' : (opts.tint || bike.tint || '#ff5d3b');
    const rim = opts.rim || '#cfd6e0';
    const gear = opts.gear || null;
    const parts = this.bikeParts(tint, rim, gear);
    const alpha = ghost ? 0.35 : 1;

    const ang = bike.ang + (bike.scrub || 0) * 0.3;
    const c = Math.cos(bike.ang), s = Math.sin(bike.ang);

    // Ground shadow first, so the bike's own geometry composites over it.
    this.drawShadow(bike, ghost);

    // Whip is a genuine yaw here rather than the 2D silhouette squash.
    const root = compose(mat4(), bike.x, bike.y, 0, 0, bike.whip || 0, ang);

    const local = bike.wheels.map((w) => {
      const dx = w.cx - bike.x, dy = w.cy - bike.y;
      return { x: dx * c + dy * s, y: -dx * s + dy * c, spin: w.spin || 0 };
    });
    const rear = local[0], front = local[1];

    const put = (mesh, lx, ly, rz = 0, ry = 0) => {
      const m = multiply(mat4(), root, compose(mat4(), lx, ly, 0, 0, ry, rz));
      this.drawMesh(mesh, m, alpha);
    };

    // Swingarm pivots to wherever the rear wheel actually solved to, so the
    // suspension visibly works over every bump.
    const swingAng = Math.atan2(rear.y - RIG.swingPivot[1], rear.x - RIG.swingPivot[0]);
    put(parts.swingarm, RIG.swingPivot[0], RIG.swingPivot[1], swingAng - RIG.swingRest);
    put(parts.fork, front.x, front.y);
    put(parts.frame, 0, 0);
    put(parts.wheel, rear.x, rear.y, rear.spin * 0.35);
    put(parts.wheel, front.x, front.y, front.spin * 0.35);

    if (bike.crashed && bike.ragdoll) this.drawRagdoll(cam, bike, ghost);
    else this.poseRider(root, parts, bike, alpha);
  }

  /** The rider leans with the bike: weight back under power, forward over the
   *  bars on the brakes. Drawn as a second pass so the lean does not have to
   *  be baked into the cached mesh. */
  poseRider(root, parts, bike, alpha) {
    const lean = clamp(bike.lean || 0, -1, 1);
    const m = multiply(mat4(), root,
      compose(mat4(), lean * 0.16, 0.02 * Math.abs(lean), 0, 0, 0, -lean * 0.30));
    this.drawMesh(parts.rider, m, alpha);
  }

  drawShadow(bike, ghost) {
    if (!this.shadowMesh) {
      // A flat disc rather than a quad — a square shadow under a bike reads as
      // a bug immediately. Two rings at different radii give it a soft edge
      // without needing per-vertex alpha.
      const mb = new MeshBuilder();
      mb.rotate(-Math.PI / 2, 0, 0);
      const col = [0.03, 0.03, 0.05];
      const seg = 20;
      for (const [r, y] of [[0.5, 0], [0.34, 0.004]]) {
        const centre = mb.vertex(0, 0, y, 0, 0, 1, col);
        const ring = [];
        for (let i = 0; i <= seg; i++) {
          const a = (i / seg) * Math.PI * 2;
          ring.push(mb.vertex(Math.cos(a) * r, Math.sin(a) * r, y, 0, 0, 1, col));
        }
        for (let i = 0; i < seg; i++) mb.idx.push(centre, ring[i], ring[i + 1]);
      }
      this.shadowMesh = mb.upload(this.gl);
    }
    const gh = bike.track.heightAt(bike.x);
    const air = clamp(bike.y - gh, 0, 10);
    // A shadow that spreads and fades with height is most of what sells the
    // altitude read; without it, big air looks like the bike is standing still.
    const size = 1.7 + air * 0.20;
    const a = (ghost ? 0.12 : 0.38) * clamp(1 - air / 10, 0.10, 1);
    const m = compose(mat4(), bike.x, gh + 0.03, 0, 0, 0, 0, size, 1, size * 0.5);
    this.drawMesh(this.shadowMesh, m, a);
  }

  drawRagdoll(cam, bike, ghost) {
    const r = bike.ragdoll; if (!r) return;
    if (!this.limbMesh) {
      const mb = new MeshBuilder();
      mb.cylinder(0.5, 1, rgb('#e9edf4'), 7);   // unit limb, scaled per link
      this.limbMesh = mb.upload(this.gl);
      const hb = new MeshBuilder();
      hb.sphere(0.16, rgb('#ff5d73'), 10, 7);
      this.headMesh = hb.upload(this.gl);
    }
    const alpha = ghost ? 0.3 : 1;
    for (const l of r.links) {
      const a = r.pts[l.a], b = r.pts[l.b];
      const dx = b.x - a.x, dy = b.y - a.y;
      const len = Math.hypot(dx, dy) || 0.01;
      const m = compose(mat4(), (a.x + b.x) / 2, (a.y + b.y) / 2, 0,
                        0, 0, Math.atan2(dy, dx) - Math.PI / 2, 0.13, len, 0.13);
      this.drawMesh(this.limbMesh, m, alpha);
    }
    const h = r.pts.head;
    this.drawMesh(this.headMesh, compose(mat4(), h.x, h.y, 0, 0, 0, 0, 1.2), alpha);
  }

  /** Bike part meshes, cached per colourway. A race has a handful of distinct
   *  liveries, so this settles after the first lap of draws. */
  bikeParts(tint, rim, gear) {
    const key = `${tint}|${rim}|${gear ? gear.jersey || '' : ''}|${this.quality}`;
    let parts = this.bikeCache.get(key);
    if (parts) return parts;
    const gl = this.gl;
    const low = this.quality === 'low';
    const col = rgb(tint);
    const dark = rgb(shade(tint, -0.42));
    const metal = rgb('#b9c2cf');
    const black = rgb('#1b1e24');

    // — frame, tank, seat, plastics —
    const f = new MeshBuilder();
    // Backbone and downtube, run as tubes between real points rather than
    // stacked boxes, which is what made the early iOS models look like debris.
    f.tube([-0.42, 0.16, 0.05], [0.34, 0.30, 0.05], 0.035, metal);
    f.tube([-0.42, 0.16, -0.05], [0.34, 0.30, -0.05], 0.035, metal);
    f.tube([0.34, 0.30, 0.05], [0.30, -0.12, 0.03], 0.034, metal);
    f.tube([0.34, 0.30, -0.05], [0.30, -0.12, -0.03], 0.034, metal);
    f.tube([-0.42, 0.16, 0], [-0.10, -0.16, 0], 0.038, metal);
    f.tube([0.30, -0.12, 0], [-0.10, -0.16, 0], 0.040, metal);
    // Engine mass slung in the cradle.
    f.push(); f.translate(0.06, -0.06, 0); f.box(0.42, 0.30, 0.26, rgb('#2c313a')); f.pop();
    f.push(); f.translate(0.20, 0.06, 0); f.box(0.16, 0.22, 0.22, rgb('#3a4049')); f.pop();
    // Tank, narrowing towards the seat, then the seat itself.
    f.push(); f.translate(0.14, 0.31, 0); f.box(0.30, 0.19, 0.24, col); f.pop();
    f.push(); f.translate(-0.06, 0.30, 0); f.box(0.24, 0.15, 0.17, col); f.pop();
    f.push(); f.translate(-0.34, 0.29, 0); f.box(0.52, 0.11, 0.19, black); f.pop();
    // Rear fender: kicked up and tapered. A flat horizontal slab here reads as
    // a shelf bolted to the back of the bike, which is what the first pass did.
    f.push(); f.translate(-0.62, 0.33, 0); f.rotate(0, 0, 0.20);
    f.box(0.26, 0.05, 0.20, col); f.pop();
    f.push(); f.translate(-0.80, 0.40, 0); f.rotate(0, 0, 0.30);
    f.box(0.18, 0.04, 0.14, col); f.pop();
    // Side plates carrying the number, tucked against the subframe with enough
    // thickness that they are not paper from a three-quarter angle.
    for (const z of [0.105, -0.105]) {
      f.push(); f.translate(-0.46, 0.21, z); f.rotate(0, 0, 0.12);
      f.box(0.26, 0.19, 0.035, rgb('#f0f3f8')); f.pop();
    }
    // Radiator shrouds, raked in towards the tank.
    for (const z of [0.135, -0.135]) {
      f.push(); f.translate(0.24, 0.25, z);
      f.rotate(0, 0, 0.18); f.transform(0, 0, 0, z > 0 ? -0.22 : 0.22, 0, 0);
      f.box(0.24, 0.24, 0.045, col); f.pop();
    }
    // Front number plate, raked back, and a fender that follows the tyre's arc
    // instead of sitting out flat like a shelf.
    f.push(); f.translate(0.59, 0.31, 0); f.rotate(0, 0, 0.32);
    f.box(0.05, 0.22, 0.24, col); f.pop();
    f.push(); f.translate(0.68, 0.17, 0); f.rotate(0, 0, 0.16);
    f.box(0.20, 0.035, 0.21, col); f.pop();
    f.push(); f.translate(0.85, 0.11, 0); f.rotate(0, 0, -0.10);
    f.box(0.18, 0.03, 0.18, col); f.pop();
    // Bars.
    f.push(); f.translate(0.52, 0.52, 0); f.rotate(Math.PI / 2, 0, 0);
    f.cylinder(0.018, 0.62, metal, 6); f.pop();
    f.tube([0.52, 0.40, 0], [0.52, 0.52, 0], 0.022, metal);
    // Exhaust.
    f.tube([0.24, 0.02, 0.08], [-0.30, 0.20, 0.14], 0.035, rgb('#8d939d'));
    f.tube([-0.30, 0.20, 0.14], [-0.62, 0.24, 0.15], 0.055, rgb('#9aa3b1'));
    // Rear shock.
    f.tube([-0.14, 0.20, 0], [-0.24, -0.14, 0], 0.030, rgb('#e05a5a'));
    // Footpegs.
    for (const z of [0.16, -0.16]) {
      f.push(); f.translate(-0.06, -0.20, z); f.box(0.14, 0.03, 0.10, metal); f.pop();
    }

    // — fork, origin at the front axle —
    const fk = new MeshBuilder();
    for (const z of [0.09, -0.09]) {
      fk.tube([0, 0, z], [-0.10, 0.44, z], 0.033, rgb('#d8dee7'));
      fk.tube([-0.10, 0.44, z], [-0.16, 0.72, z], 0.040, metal);
    }
    fk.push(); fk.translate(-0.16, 0.70, 0); fk.box(0.10, 0.06, 0.26, rgb('#606874')); fk.pop();
    fk.push(); fk.translate(0.02, 0.02, 0); fk.rotate(Math.PI / 2, 0, 0);
    fk.cylinder(0.055, 0.20, rgb('#9aa3b1'), 8); fk.pop();

    // — swingarm, origin at the pivot, running back along -X —
    const sw = new MeshBuilder();
    const swLen = Math.hypot(RIG.rearAxle[0] - RIG.swingPivot[0],
                             RIG.rearAxle[1] - RIG.swingPivot[1]);
    for (const z of [0.085, -0.085]) {
      sw.tube([0, 0, z], [-swLen * Math.cos(0), RIG.rearAxle[1] - RIG.swingPivot[1], z],
              0.036, rgb('#a7afbb'));
    }
    sw.push(); sw.translate(-0.30, -0.07, 0); sw.box(0.30, 0.05, 0.20, rgb('#98a1ad')); sw.pop();
    // Chain run.
    sw.tube([-0.02, 0.05, 0.10], [-0.55, -0.09, 0.10], 0.014, rgb('#6f7681'));

    // — wheel: tyre, rim, spokes, hub, disc —
    const wh = new MeshBuilder();
    const R = 0.33;
    wh.torus(R - 0.055, 0.055, black, low ? 12 : 22, low ? 5 : 9);
    if (!low) {
      // Knobbies, so the tyre reads as a dirt tyre when it is close to camera.
      for (let i = 0; i < 18; i++) {
        const a = (i / 18) * Math.PI * 2;
        for (const z of [0.045, -0.045]) {
          wh.push();
          wh.translate(Math.cos(a) * (R - 0.02), Math.sin(a) * (R - 0.02), z);
          wh.rotate(0, 0, a);
          wh.box(0.05, 0.07, 0.03, rgb('#2a2d34'));
          wh.pop();
        }
      }
    }
    wh.push(); wh.rotate(Math.PI / 2, 0, 0);
    wh.cylinder(R - 0.10, 0.035, rgb(rim), low ? 10 : 20); wh.pop();
    wh.push(); wh.rotate(Math.PI / 2, 0, 0);
    wh.cylinder(0.055, 0.14, rgb('#8d939d'), 8); wh.pop();
    for (let i = 0; i < (low ? 4 : 8); i++) {
      const a = (i / (low ? 4 : 8)) * Math.PI * 2;
      wh.tube([0, 0, 0], [Math.cos(a) * (R - 0.10), Math.sin(a) * (R - 0.10), 0.01],
              0.008, rgb('#cfd6e0'), 4);
    }
    wh.push(); wh.rotate(Math.PI / 2, 0, 0);
    wh.cylinder(0.11, 0.012, rgb('#9aa3b1'), 10); wh.pop();

    // — rider, in the attack position —
    const jersey = rgb(gear && gear.jersey ? gear.jersey : shade(tint, 0.18));
    const pants = rgb('#20242e');
    const boot = rgb('#31363f');
    const rd = new MeshBuilder();
    // Torso, pitched forward over the bars, tapered to shoulders rather than
    // left as one slab.
    rd.push(); rd.translate(-0.02, 0.56, 0); rd.rotate(0, 0, -0.42);
    rd.box(0.26, 0.34, 0.26, jersey);
    rd.push(); rd.translate(0, 0.18, 0); rd.box(0.22, 0.12, 0.30, jersey); rd.pop();
    rd.pop();
    for (const z of [0.15, -0.15]) {
      rd.push(); rd.translate(0.06, 0.72, z); rd.sphere(0.075, jersey, 8, 6); rd.pop();
    }
    // Helmet with a visor and peak.
    rd.push(); rd.translate(0.20, 0.86, 0);
    rd.sphere(0.15, rgb(gear && gear.helmet ? gear.helmet : '#f0f3f8'), low ? 8 : 14, low ? 6 : 10);
    rd.push(); rd.translate(0.10, -0.01, 0); rd.box(0.09, 0.11, 0.20, rgb('#2b3340')); rd.pop();
    rd.push(); rd.translate(0.13, 0.09, 0); rd.rotate(0, 0, 0.25);
    rd.box(0.20, 0.02, 0.22, rgb('#2b3340')); rd.pop();
    rd.pop();
    // Arms reaching the bars.
    for (const z of [0.15, -0.15]) {
      rd.tube([0.06, 0.72, z], [0.30, 0.58, z * 1.2], 0.055, jersey, 6);
      rd.tube([0.30, 0.58, z * 1.2], [0.50, 0.50, z * 1.3], 0.048, jersey, 6);
      rd.push(); rd.translate(0.52, 0.50, z * 1.3); rd.sphere(0.055, rgb('#2b3340'), 6, 5); rd.pop();
    }
    // Legs gripping the tank, boots on the pegs.
    for (const z of [0.16, -0.16]) {
      rd.tube([-0.10, 0.42, z], [0.02, 0.10, z * 1.1], 0.075, pants, 6);
      rd.tube([0.02, 0.10, z * 1.1], [-0.06, -0.17, z * 1.0], 0.062, boot, 6);
      rd.push(); rd.translate(-0.02, -0.20, z); rd.box(0.20, 0.06, 0.10, boot); rd.pop();
    }

    parts = {
      frame: f.upload(gl), fork: fk.upload(gl), swingarm: sw.upload(gl),
      wheel: wh.upload(gl), rider: rd.upload(gl)
    };
    // Liveries are bounded in practice, but a long session with many opponents
    // should not grow this without limit.
    if (this.bikeCache.size > 24) {
      const oldest = this.bikeCache.keys().next().value;
      for (const m of Object.values(this.bikeCache.get(oldest))) m.dispose();
      this.bikeCache.delete(oldest);
    }
    this.bikeCache.set(key, parts);
    return parts;
  }

  // ——— Screen-space passes, handed to the 2D overlay ————————————

  drawWeather(cam, track, t) { this.hud.drawWeather(cam, track, t); }
  speedLines(bike) { this.hud.speedLines(bike); }
  vignetteAndGrade(track, intensity) { this.hud.vignetteAndGrade(track, intensity); }
  applyColorblind() { this.hud.applyColorblind(); }
}

/** Build the best renderer this browser can run, falling back to the 2D one
 *  rather than failing to start. */
export function createRenderer(canvas) {
  try {
    return new Renderer3D(canvas);
  } catch (err) {
    console.warn('MotoRush: falling back to the 2D renderer —', err.message);
    const r = new Renderer2D(canvas);
    r.is3D = false;
    return r;
  }
}
