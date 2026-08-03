// MotoRush — unified input. Keyboard, gamepad and touch all resolve to the
// same four analogue channels the physics consumes.

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

export class InputManager {
  constructor(profile) {
    this.profile = profile;
    this.keys = new Set();
    this.touch = { throttle: 0, brake: 0, lean: 0, whip: 0 };
    this.pad = null;
    this.lastSource = 'keyboard';
    this.paused = false;
    this.onPause = null;
    this.onReset = null;

    window.addEventListener('keydown', (e) => {
      if (e.repeat) return;
      const k = normKey(e.key);
      this.keys.add(k);
      this.lastSource = 'keyboard';
      const map = this.profile.data.settings.keys;
      if (k === normKey(map.pause)) { e.preventDefault(); this.onPause && this.onPause(); }
      if (k === normKey(map.reset)) { this.onReset && this.onReset(); }
      if ([' ', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright'].includes(k)) e.preventDefault();
    });
    window.addEventListener('keyup', (e) => this.keys.delete(normKey(e.key)));
    window.addEventListener('blur', () => this.keys.clear());
    window.addEventListener('gamepadconnected', (e) => { this.pad = e.gamepad.index; this.lastSource = 'gamepad'; });
    window.addEventListener('gamepaddisconnected', () => { this.pad = null; });
  }

  bindTouch(root) {
    const setFrom = (el, on) => {
      const ch = el.dataset.input;
      const val = parseFloat(el.dataset.value || '1');
      if (ch === 'lean' || ch === 'whip') this.touch[ch] = on ? val : 0;
      else this.touch[ch] = on ? val : 0;
      el.classList.toggle('active', on);
      this.lastSource = 'touch';
    };
    root.querySelectorAll('[data-input]').forEach(el => {
      const down = (e) => { e.preventDefault(); setFrom(el, true); if (navigator.vibrate) navigator.vibrate(8); };
      const up = (e) => { e.preventDefault(); setFrom(el, false); };
      el.addEventListener('pointerdown', down);
      el.addEventListener('pointerup', up);
      el.addEventListener('pointercancel', up);
      el.addEventListener('pointerleave', up);
    });
  }

  gamepadState() {
    if (this.pad == null || !navigator.getGamepads) return null;
    const gp = navigator.getGamepads()[this.pad];
    if (!gp) return null;
    const dz = (v) => (Math.abs(v) < 0.14 ? 0 : v);
    const throttle = Math.max(gp.buttons[7] ? gp.buttons[7].value : 0, gp.buttons[0] && gp.buttons[0].pressed ? 1 : 0);
    const brake = Math.max(gp.buttons[6] ? gp.buttons[6].value : 0, gp.buttons[1] && gp.buttons[1].pressed ? 1 : 0);
    const lean = dz(gp.axes[1] || 0) * -1;   // stick up = lean forward
    const whip = dz(gp.axes[2] || 0);
    if (throttle || brake || lean || whip) this.lastSource = 'gamepad';
    return { throttle, brake, lean, whip };
  }

  read() {
    const map = this.profile.data.settings.keys;
    const has = (k) => this.keys.has(normKey(k));
    let throttle = has(map.throttle) || has('w') || has(' ') ? 1 : 0;
    let brake = has(map.brake) || has('s') ? 1 : 0;
    let lean = 0;
    if (has(map.leanBack)) lean -= 1;
    if (has(map.leanFwd)) lean += 1;
    let whip = 0;
    if (has(map.whipL)) whip -= 1;
    if (has(map.whipR)) whip += 1;

    const gp = this.gamepadState();
    if (gp) {
      throttle = Math.max(throttle, gp.throttle);
      brake = Math.max(brake, gp.brake);
      if (Math.abs(gp.lean) > Math.abs(lean)) lean = gp.lean;
      if (Math.abs(gp.whip) > Math.abs(whip)) whip = gp.whip;
    }

    throttle = Math.max(throttle, this.touch.throttle);
    brake = Math.max(brake, this.touch.brake);
    if (Math.abs(this.touch.lean) > Math.abs(lean)) lean = this.touch.lean;
    if (Math.abs(this.touch.whip) > Math.abs(whip)) whip = this.touch.whip;

    return {
      throttle: clamp(throttle, 0, 1),
      brake: clamp(brake, 0, 1),
      lean: clamp(lean, -1, 1),
      whip: clamp(whip, -1, 1)
    };
  }
}

function normKey(k) {
  if (!k) return '';
  return k.length === 1 ? k.toLowerCase() : k.toLowerCase();
}
