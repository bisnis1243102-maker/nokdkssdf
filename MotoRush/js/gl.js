// MotoRush — the small WebGL layer the 3D renderer sits on: 4x4 matrices, a
// shader wrapper, and a mesh builder that bakes procedural primitives into a
// single interleaved buffer.
//
// There is no external library here for the same reason the rest of the game
// has none: every triangle in the build should be something the repository can
// account for. The maths is only what the renderer actually calls.

// ——— Matrices ————————————————————————————————————————————————
// Column-major, the layout WebGL expects, so uniformMatrix4fv never transposes.

export function mat4() {
  return new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
}

export function identity(m) {
  m[0] = 1; m[1] = 0; m[2] = 0; m[3] = 0;
  m[4] = 0; m[5] = 1; m[6] = 0; m[7] = 0;
  m[8] = 0; m[9] = 0; m[10] = 1; m[11] = 0;
  m[12] = 0; m[13] = 0; m[14] = 0; m[15] = 1;
  return m;
}

export function multiply(out, a, b) {
  // out = a * b. Written out rather than looped: this is the hottest maths in
  // the frame and the unrolled form measurably wins.
  const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
  const a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
  const a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  const a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
  for (let i = 0; i < 4; i++) {
    const b0 = b[i * 4], b1 = b[i * 4 + 1], b2 = b[i * 4 + 2], b3 = b[i * 4 + 3];
    out[i * 4] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
    out[i * 4 + 1] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
    out[i * 4 + 2] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
    out[i * 4 + 3] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;
  }
  return out;
}

export function perspective(out, fovY, aspect, near, far) {
  const f = 1 / Math.tan(fovY / 2);
  identity(out);
  out[0] = f / aspect; out[5] = f;
  out[10] = (far + near) / (near - far); out[11] = -1;
  out[14] = (2 * far * near) / (near - far); out[15] = 0;
  return out;
}

export function lookAt(out, eye, target, up) {
  let zx = eye[0] - target[0], zy = eye[1] - target[1], zz = eye[2] - target[2];
  let l = Math.hypot(zx, zy, zz) || 1;
  zx /= l; zy /= l; zz /= l;
  let xx = up[1] * zz - up[2] * zy;
  let xy = up[2] * zx - up[0] * zz;
  let xz = up[0] * zy - up[1] * zx;
  l = Math.hypot(xx, xy, xz) || 1;
  xx /= l; xy /= l; xz /= l;
  const yx = zy * xz - zz * xy;
  const yy = zz * xx - zx * xz;
  const yz = zx * xy - zy * xx;
  out[0] = xx; out[1] = yx; out[2] = zx; out[3] = 0;
  out[4] = xy; out[5] = yy; out[6] = zy; out[7] = 0;
  out[8] = xz; out[9] = yz; out[10] = zz; out[11] = 0;
  out[12] = -(xx * eye[0] + xy * eye[1] + xz * eye[2]);
  out[13] = -(yx * eye[0] + yy * eye[1] + yz * eye[2]);
  out[14] = -(zx * eye[0] + zy * eye[1] + zz * eye[2]);
  out[15] = 1;
  return out;
}

export function compose(out, tx, ty, tz, rx, ry, rz, sx = 1, sy = sx, sz = sx) {
  // Translate · Rz · Ry · Rx · Scale — the order the renderer poses parts in.
  const cx = Math.cos(rx), sxr = Math.sin(rx);
  const cy = Math.cos(ry), syr = Math.sin(ry);
  const cz = Math.cos(rz), szr = Math.sin(rz);
  const m00 = cy * cz, m01 = cy * szr, m02 = -syr;
  const m10 = sxr * syr * cz - cx * szr, m11 = sxr * syr * szr + cx * cz, m12 = sxr * cy;
  const m20 = cx * syr * cz + sxr * szr, m21 = cx * syr * szr - sxr * cz, m22 = cx * cy;
  out[0] = m00 * sx; out[1] = m01 * sx; out[2] = m02 * sx; out[3] = 0;
  out[4] = m10 * sy; out[5] = m11 * sy; out[6] = m12 * sy; out[7] = 0;
  out[8] = m20 * sz; out[9] = m21 * sz; out[10] = m22 * sz; out[11] = 0;
  out[12] = tx; out[13] = ty; out[14] = tz; out[15] = 1;
  return out;
}

/** Project a world point through a view-projection matrix to pixels. */
export function project(vp, x, y, z, width, height) {
  const cx = vp[0] * x + vp[4] * y + vp[8] * z + vp[12];
  const cy = vp[1] * x + vp[5] * y + vp[9] * z + vp[13];
  const cw = vp[3] * x + vp[7] * y + vp[11] * z + vp[15];
  const w = Math.abs(cw) < 1e-6 ? 1e-6 : cw;
  return {
    x: (cx / w * 0.5 + 0.5) * width,
    y: (1 - (cy / w * 0.5 + 0.5)) * height,
    w
  };
}

// ——— Shaders ————————————————————————————————————————————————

export function createProgram(gl, vertSrc, fragSrc) {
  const compile = (type, src) => {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      throw new Error('shader: ' + gl.getShaderInfoLog(sh));
    }
    return sh;
  };
  const prog = gl.createProgram();
  gl.attachShader(prog, compile(gl.VERTEX_SHADER, vertSrc));
  gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, fragSrc));
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    throw new Error('link: ' + gl.getProgramInfoLog(prog));
  }
  // Look the locations up once; per-frame getUniformLocation is a known
  // pitfall that quietly costs more than the draw call it precedes.
  const uniforms = {}, attribs = {};
  const nU = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < nU; i++) {
    const n = gl.getActiveUniform(prog, i).name.replace(/\[0\]$/, '');
    uniforms[n] = gl.getUniformLocation(prog, n);
  }
  const nA = gl.getProgramParameter(prog, gl.ACTIVE_ATTRIBUTES);
  for (let i = 0; i < nA; i++) {
    const n = gl.getActiveAttrib(prog, i).name;
    attribs[n] = gl.getAttribLocation(prog, n);
  }
  return { prog, uniforms, attribs };
}

// ——— Mesh building —————————————————————————————————————————
// Vertices are interleaved position(3) · normal(3) · colour(3). Primitives are
// appended in the builder's current transform, so a part can be assembled from
// boxes and tubes in its own local space and uploaded once.

export const STRIDE = 9;

export class MeshBuilder {
  constructor() {
    this.verts = [];
    this.idx = [];
    this.stack = [];
    this.m = mat4();
  }

  push() { this.stack.push(this.m.slice()); return this; }
  pop() { this.m = this.stack.pop(); return this; }

  transform(tx, ty, tz, rx = 0, ry = 0, rz = 0, sx = 1, sy = sx, sz = sx) {
    multiply(this.m, this.m, compose(mat4(), tx, ty, tz, rx, ry, rz, sx, sy, sz));
    return this;
  }

  translate(x, y, z) { return this.transform(x, y, z); }
  rotate(rx, ry, rz) { return this.transform(0, 0, 0, rx, ry, rz); }

  vertex(x, y, z, nx, ny, nz, col) {
    const m = this.m;
    const wx = m[0] * x + m[4] * y + m[8] * z + m[12];
    const wy = m[1] * x + m[5] * y + m[9] * z + m[13];
    const wz = m[2] * x + m[6] * y + m[10] * z + m[14];
    // Normals ignore translation. The renderer never applies non-uniform
    // scale to a lit part, so the inverse-transpose is not needed here.
    let ax = m[0] * nx + m[4] * ny + m[8] * nz;
    let ay = m[1] * nx + m[5] * ny + m[9] * nz;
    let az = m[2] * nx + m[6] * ny + m[10] * nz;
    const l = Math.hypot(ax, ay, az) || 1;
    this.verts.push(wx, wy, wz, ax / l, ay / l, az / l, col[0], col[1], col[2]);
    return this.verts.length / STRIDE - 1;
  }

  /** Add a quad from four already-added vertex indices. */
  quadIdx(a, b, c, d) { this.idx.push(a, b, c, a, c, d); return this; }

  box(w, h, d, col, ox = 0, oy = 0, oz = 0) {
    const x0 = ox - w / 2, x1 = ox + w / 2;
    const y0 = oy - h / 2, y1 = oy + h / 2;
    const z0 = oz - d / 2, z1 = oz + d / 2;
    const faces = [
      [[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], [0, 0, 1]],
      [[x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [0, 0, -1]],
      [[x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [1, 0, 0]],
      [[x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], [-1, 0, 0]],
      [[x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0], [0, 1, 0]],
      [[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1], [0, -1, 0]]
    ];
    for (const f of faces) {
      const n = f[4];
      const a = this.vertex(f[0][0], f[0][1], f[0][2], n[0], n[1], n[2], col);
      const b = this.vertex(f[1][0], f[1][1], f[1][2], n[0], n[1], n[2], col);
      const c = this.vertex(f[2][0], f[2][1], f[2][2], n[0], n[1], n[2], col);
      const d2 = this.vertex(f[3][0], f[3][1], f[3][2], n[0], n[1], n[2], col);
      this.quadIdx(a, b, c, d2);
    }
    return this;
  }

  /** A cylinder along +Y, centred on the origin. */
  cylinder(radius, height, col, seg = 12, capped = true, radiusTop = radius) {
    const y0 = -height / 2, y1 = height / 2;
    const ring0 = [], ring1 = [];
    for (let i = 0; i <= seg; i++) {
      const a = (i / seg) * Math.PI * 2;
      const cx = Math.cos(a), sz = Math.sin(a);
      ring0.push(this.vertex(cx * radius, y0, sz * radius, cx, 0, sz, col));
      ring1.push(this.vertex(cx * radiusTop, y1, sz * radiusTop, cx, 0, sz, col));
    }
    for (let i = 0; i < seg; i++) this.quadIdx(ring0[i], ring0[i + 1], ring1[i + 1], ring1[i]);
    if (capped) {
      for (const [y, ny, r] of [[y0, -1, radius], [y1, 1, radiusTop]]) {
        const centre = this.vertex(0, y, 0, 0, ny, 0, col);
        const ring = [];
        for (let i = 0; i <= seg; i++) {
          const a = (i / seg) * Math.PI * 2;
          ring.push(this.vertex(Math.cos(a) * r, y, Math.sin(a) * r, 0, ny, 0, col));
        }
        for (let i = 0; i < seg; i++) {
          if (ny > 0) this.idx.push(centre, ring[i], ring[i + 1]);
          else this.idx.push(centre, ring[i + 1], ring[i]);
        }
      }
    }
    return this;
  }

  /** A tube between two points in the current space — how the frame is built. */
  tube(from, to, radius, col, seg = 8) {
    const dx = to[0] - from[0], dy = to[1] - from[1], dz = to[2] - from[2];
    const len = Math.hypot(dx, dy, dz);
    if (len < 1e-5) return this;
    // Rotate +Y onto the segment direction.
    const pitch = Math.atan2(Math.hypot(dx, dz), dy);
    const yaw = Math.atan2(dx, dz);
    this.push();
    this.transform((from[0] + to[0]) / 2, (from[1] + to[1]) / 2, (from[2] + to[2]) / 2,
                   0, yaw, 0);
    this.transform(0, 0, 0, pitch, 0, 0);
    this.cylinder(radius, len, col, seg);
    this.pop();
    return this;
  }

  /** A wheel: tyre torus in the XY plane, spinning about Z. */
  torus(radius, tube, col, major = 20, minor = 8) {
    const base = this.verts.length / STRIDE;
    for (let i = 0; i <= major; i++) {
      const u = (i / major) * Math.PI * 2;
      const cu = Math.cos(u), su = Math.sin(u);
      for (let j = 0; j <= minor; j++) {
        const v = (j / minor) * Math.PI * 2;
        const cv = Math.cos(v), sv = Math.sin(v);
        const nx = cu * cv, ny = su * cv, nz = sv;
        this.vertex(cu * (radius + tube * cv), su * (radius + tube * cv), tube * sv,
                    nx, ny, nz, col);
      }
    }
    const row = minor + 1;
    for (let i = 0; i < major; i++) {
      for (let j = 0; j < minor; j++) {
        const a = base + i * row + j;
        this.quadIdx(a, a + row, a + row + 1, a + 1);
      }
    }
    return this;
  }

  /** A low-poly sphere, used for helmets, shoulders and knees. */
  sphere(radius, col, seg = 12, rings = 8) {
    const base = this.verts.length / STRIDE;
    for (let r = 0; r <= rings; r++) {
      const phi = (r / rings) * Math.PI;
      const sp = Math.sin(phi), cp = Math.cos(phi);
      for (let s = 0; s <= seg; s++) {
        const th = (s / seg) * Math.PI * 2;
        const nx = sp * Math.cos(th), ny = cp, nz = sp * Math.sin(th);
        this.vertex(nx * radius, ny * radius, nz * radius, nx, ny, nz, col);
      }
    }
    const row = seg + 1;
    for (let r = 0; r < rings; r++) {
      for (let s = 0; s < seg; s++) {
        const a = base + r * row + s;
        this.quadIdx(a, a + 1, a + row + 1, a + row);
      }
    }
    return this;
  }

  /** A double-sided flat quad in the XY plane — banners, flags, number plates. */
  plane(w, h, col, ox = 0, oy = 0) {
    const a = this.vertex(ox - w / 2, oy - h / 2, 0, 0, 0, 1, col);
    const b = this.vertex(ox + w / 2, oy - h / 2, 0, 0, 0, 1, col);
    const c = this.vertex(ox + w / 2, oy + h / 2, 0, 0, 0, 1, col);
    const d = this.vertex(ox - w / 2, oy + h / 2, 0, 0, 0, 1, col);
    this.quadIdx(a, b, c, d);
    const e = this.vertex(ox - w / 2, oy - h / 2, 0, 0, 0, -1, col);
    const f = this.vertex(ox + w / 2, oy - h / 2, 0, 0, 0, -1, col);
    const g = this.vertex(ox + w / 2, oy + h / 2, 0, 0, 0, -1, col);
    const h2 = this.vertex(ox - w / 2, oy + h / 2, 0, 0, 0, -1, col);
    this.quadIdx(e, h2, g, f);
    return this;
  }

  get empty() { return this.idx.length === 0; }

  upload(gl) { return new Mesh(gl, this.verts, this.idx); }
}

export class Mesh {
  constructor(gl, verts, idx) {
    this.gl = gl;
    this.count = idx.length;
    this.vbo = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(verts), gl.STATIC_DRAW);
    this.ibo = gl.createBuffer();
    // Past 65535 vertices the 16-bit index type silently wraps, which shows up
    // as garbage triangles across the mesh. The terrain ribbon is well past
    // that, so use 32-bit indices when the extension is there.
    const big = verts.length / STRIDE > 65535;
    this.type = big ? gl.UNSIGNED_INT : gl.UNSIGNED_SHORT;
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.ibo);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,
                  big ? new Uint32Array(idx) : new Uint16Array(idx), gl.STATIC_DRAW);
  }

  bind(attribs) {
    const gl = this.gl;
    gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.ibo);
    const b = STRIDE * 4;
    gl.enableVertexAttribArray(attribs.aPos);
    gl.vertexAttribPointer(attribs.aPos, 3, gl.FLOAT, false, b, 0);
    gl.enableVertexAttribArray(attribs.aNormal);
    gl.vertexAttribPointer(attribs.aNormal, 3, gl.FLOAT, false, b, 12);
    gl.enableVertexAttribArray(attribs.aColor);
    gl.vertexAttribPointer(attribs.aColor, 3, gl.FLOAT, false, b, 24);
  }

  draw(attribs) {
    this.bind(attribs);
    this.gl.drawElements(this.gl.TRIANGLES, this.count, this.type, 0);
  }

  dispose() {
    this.gl.deleteBuffer(this.vbo);
    this.gl.deleteBuffer(this.ibo);
  }
}

/** A CSS colour → [r,g,b] floats the builder stores per vertex.
 *  Both spellings have to work: the biome palette is hex, but shade() in the
 *  2D renderer hands back 'rgb(r,g,b)', and parsing one as the other silently
 *  produces a colour rather than an error. */
export function rgb(css) {
  if (typeof css !== 'string') return [1, 0, 1];
  const fn = css.match(/rgba?\(([^)]+)\)/i);
  if (fn) {
    const p = fn[1].split(',').map(Number);
    return [(p[0] || 0) / 255, (p[1] || 0) / 255, (p[2] || 0) / 255];
  }
  let h = css.replace('#', '').trim();
  if (h.length === 3) h = h.split('').map((x) => x + x).join('');
  return [parseInt(h.slice(0, 2), 16) / 255,
          parseInt(h.slice(2, 4), 16) / 255,
          parseInt(h.slice(4, 6), 16) / 255];
}

export function mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

export function scaleRGB(c, k) {
  return [Math.min(1, c[0] * k), Math.min(1, c[1] * k), Math.min(1, c[2] * k)];
}
