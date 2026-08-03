// MotoRush — persistent profile: progression, economy, missions, records.
// Stored locally; the shape is deliberately server-friendly so the same
// document could be synced by an account service later.

import { BIKES, DAILY_POOL, WEEKLY_POOL, ACHIEVEMENTS, SEASON, xpForLevel, GEAR } from './data.js';

const KEY = 'motorush.profile.v1';

const todayKey = () => new Date().toISOString().slice(0, 10);
const weekKey = () => {
  const d = new Date();
  const first = new Date(d.getFullYear(), 0, 1);
  const week = Math.floor(((d - first) / 86400000 + first.getDay() + 1) / 7);
  return `${d.getFullYear()}-W${week}`;
};

function defaultProfile() {
  return {
    version: 1,
    name: 'Rider',
    number: 21,
    xp: 0,
    level: 1,
    coins: 3000,
    gems: 25,
    bikes: ['sprout50'],
    currentBike: 'sprout50',
    upgrades: { sprout50: {} },
    cosmetics: {
      owned: { helmet: ['Slate'], jersey: ['Classic'], pants: ['Slate'], boots: ['Standard'],
        gloves: ['Grip'], goggles: ['Clear'], plastics: ['Stock'], graphics: ['Blank'],
        plate: ['White'], wheels: ['Black'], exhaust: ['Stock'], victory: ['Fist Pump'] },
      equipped: { helmet: 'Slate', jersey: 'Classic', pants: 'Slate', boots: 'Standard',
        gloves: 'Grip', goggles: 'Clear', plastics: 'Stock', graphics: 'Blank',
        plate: 'White', wheels: 'Black', exhaust: 'Stock', victory: 'Fist Pump' }
    },
    stats: { races: 0, wins: 0, perfects: 0, crashes: 0, airtime: 0, whipdeg: 0,
      cleanraces: 0, champs: 0, distance: 0 },
    achievements: {},
    records: {},          // trackId -> { time, ghost }
    championships: {},    // id -> { round, points, done }
    daily: null,
    weekly: null,
    season: { id: SEASON.id, xp: 0, tier: 0, claimed: [], premium: false },
    rank: { points: 900, tier: 'Bronze', best: 900 },
    settings: {
      master: 0.8, sfx: 0.9, music: 0.35, quality: 'high', motionBlur: true,
      colorblind: 'none', subtitles: true, assistLanding: false, assistThrottle: false,
      touchScale: 1, touchLayout: 'default', shake: 1,
      keys: { throttle: 'ArrowUp', brake: 'ArrowDown', leanBack: 'ArrowLeft', leanFwd: 'ArrowRight',
        whipL: 'a', whipR: 'd', reset: 'r', pause: 'Escape' }
    },
    adaptive: 0.6,
    lastLogin: null,
    loginStreak: 0
  };
}

export class Profile {
  constructor() {
    this.data = load();
    this.rollMissions();
    this.dailyLogin();
  }

  save() {
    try { localStorage.setItem(KEY, JSON.stringify(this.data)); } catch (e) { /* private mode */ }
  }

  reset() { this.data = defaultProfile(); this.rollMissions(); this.save(); }

  // ——— Progression ————————————————————————————————————————
  addXP(amount) {
    const d = this.data;
    d.xp += amount;
    d.season.xp += amount;
    const levels = [];
    while (d.xp >= xpForLevel(d.level)) {
      d.xp -= xpForLevel(d.level);
      d.level++;
      levels.push(d.level);
      d.coins += 500 + d.level * 120;
    }
    const tier = Math.min(SEASON.tiers, Math.floor(d.season.xp / SEASON.xpPerTier));
    const tiersGained = tier - d.season.tier;
    d.season.tier = tier;
    this.checkAchievements();
    this.save();
    return { levels, tiersGained };
  }

  addCoins(n) { this.data.coins += n; this.save(); }

  spend(n) {
    if (this.data.coins < n) return false;
    this.data.coins -= n; this.save(); return true;
  }

  // ——— Garage ————————————————————————————————————————————
  ownsBike(id) { return this.data.bikes.includes(id); }

  buyBike(id) {
    const b = BIKES.find(x => x.id === id);
    if (!b || this.ownsBike(id)) return { ok: false, reason: 'owned' };
    if (this.data.level < b.level) return { ok: false, reason: 'level' };
    if (!this.spend(b.price)) return { ok: false, reason: 'coins' };
    this.data.bikes.push(id);
    this.data.upgrades[id] = {};
    this.checkAchievements();
    this.save();
    return { ok: true };
  }

  upgradeCost(bikeId, upg) {
    const lvl = (this.data.upgrades[bikeId] || {})[upg.id] || 0;
    return Math.round(upg.cost * Math.pow(1.55, lvl));
  }

  buyUpgrade(bikeId, upg) {
    const u = this.data.upgrades[bikeId] || (this.data.upgrades[bikeId] = {});
    const lvl = u[upg.id] || 0;
    if (lvl >= upg.max) return { ok: false, reason: 'max' };
    const cost = this.upgradeCost(bikeId, upg);
    if (!this.spend(cost)) return { ok: false, reason: 'coins' };
    u[upg.id] = lvl + 1;
    this.save();
    return { ok: true, level: lvl + 1 };
  }

  bikeSpec(id = this.data.currentBike) {
    return BIKES.find(b => b.id === id) || BIKES[0];
  }

  upgradesFor(id = this.data.currentBike) { return this.data.upgrades[id] || {}; }

  // ——— Cosmetics ————————————————————————————————————————
  cosmeticPrice(slot) {
    const prices = { helmet: 1800, jersey: 1500, pants: 1500, boots: 1200, gloves: 900,
      goggles: 900, plastics: 2000, graphics: 2500, plate: 700, wheels: 2200,
      exhaust: 2600, victory: 3000 };
    return prices[slot] || 1200;
  }

  buyCosmetic(slot, item) {
    const owned = this.data.cosmetics.owned[slot] || (this.data.cosmetics.owned[slot] = []);
    if (owned.includes(item)) return { ok: false, reason: 'owned' };
    if (!GEAR[slot] || !GEAR[slot].includes(item)) return { ok: false, reason: 'unknown' };
    if (!this.spend(this.cosmeticPrice(slot))) return { ok: false, reason: 'coins' };
    owned.push(item); this.save(); return { ok: true };
  }

  equip(slot, item) {
    if (!(this.data.cosmetics.owned[slot] || []).includes(item)) return false;
    this.data.cosmetics.equipped[slot] = item; this.save(); return true;
  }

  // ——— Missions ————————————————————————————————————————
  rollMissions() {
    const d = this.data;
    const pick = (pool, n) => {
      const copy = [...pool];
      const out = [];
      while (out.length < n && copy.length) out.push(...copy.splice((Math.random() * copy.length) | 0, 1));
      return out.map(m => ({ ...m, progress: 0, claimed: false }));
    };
    if (!d.daily || d.daily.key !== todayKey()) d.daily = { key: todayKey(), list: pick(DAILY_POOL, 3) };
    if (!d.weekly || d.weekly.key !== weekKey()) d.weekly = { key: weekKey(), list: pick(WEEKLY_POOL, 2) };
    this.save();
  }

  dailyLogin() {
    const d = this.data;
    const t = todayKey();
    if (d.lastLogin === t) return null;
    const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
    d.loginStreak = d.lastLogin === yesterday ? d.loginStreak + 1 : 1;
    d.lastLogin = t;
    const reward = { coins: 300 + Math.min(7, d.loginStreak) * 150, gems: d.loginStreak % 7 === 0 ? 25 : 0 };
    d.coins += reward.coins; d.gems += reward.gems;
    this.save();
    return { streak: d.loginStreak, ...reward };
  }

  // Applies a finished race to every mission that tracks one of its stats.
  applyRaceStats(delta) {
    const d = this.data;
    for (const k in delta) d.stats[k] = (d.stats[k] || 0) + delta[k];
    const bump = (list) => {
      for (const m of list) {
        if (m.claimed) continue;
        m.progress = Math.min(m.goal, (m.progress || 0) + (delta[m.stat] || 0));
      }
    };
    if (d.daily) bump(d.daily.list);
    if (d.weekly) bump(d.weekly.list);
    this.checkAchievements();
    this.save();
  }

  claimMission(scope, id) {
    const bucket = this.data[scope];
    if (!bucket) return null;
    const m = bucket.list.find(x => x.id === id);
    if (!m || m.claimed || m.progress < m.goal) return null;
    m.claimed = true;
    this.addCoins(m.coins);
    const res = this.addXP(m.xp);
    return { ...m, levelUps: res.levels };
  }

  // ——— Achievements ————————————————————————————————————
  checkAchievements() {
    const d = this.data, s = d.stats, got = [];
    const unlock = (id) => { if (!d.achievements[id]) { d.achievements[id] = Date.now(); got.push(id); } };
    if (s.races >= 1) unlock('first_race');
    if (s.wins >= 1) unlock('first_win');
    if (d.level >= 10) unlock('level10');
    if (d.level >= 25) unlock('level25');
    if (d.bikes.length >= 5) unlock('garage5');
    if (s.airtime >= 60) unlock('airtime');
    if (s.champs >= 1) unlock('champ1');
    if (s.cleanraces >= 1) unlock('no_crash');
    return got.map(id => ACHIEVEMENTS.find(a => a.id === id));
  }

  unlockAchievement(id) {
    if (this.data.achievements[id]) return null;
    this.data.achievements[id] = Date.now();
    this.save();
    return ACHIEVEMENTS.find(a => a.id === id);
  }

  // ——— Records / ghosts ————————————————————————————————
  recordTime(trackId, time, ghost) {
    const r = this.data.records[trackId];
    if (!r || time < r.time) {
      this.data.records[trackId] = { time, ghost: ghost ? compressGhost(ghost) : (r && r.ghost) || null };
      this.save();
      return true;
    }
    return false;
  }

  ghostFor(trackId) {
    const r = this.data.records[trackId];
    return r && r.ghost ? decompressGhost(r.ghost) : null;
  }

  // ——— Ranked ————————————————————————————————————————
  applyRanked(position, fieldSize) {
    const r = this.data.rank;
    const expected = (fieldSize + 1) / 2;
    const delta = Math.round((expected - position) * 18 + (position === 1 ? 12 : 0));
    r.points = Math.max(0, r.points + delta);
    r.best = Math.max(r.best, r.points);
    r.tier = rankTier(r.points);
    this.save();
    return { delta, points: r.points, tier: r.tier };
  }
}

export function rankTier(p) {
  if (p >= 3200) return 'Legend';
  if (p >= 2600) return 'Champion';
  if (p >= 2100) return 'Diamond';
  if (p >= 1700) return 'Platinum';
  if (p >= 1300) return 'Gold';
  if (p >= 1000) return 'Silver';
  return 'Bronze';
}

// Ghosts are stored as quantised keyframes — ~10 Hz, 3 bytes-ish per sample
// once JSON-encoded, so a 3-minute lap costs a few kilobytes.
export function compressGhost(samples) {
  return samples.map(s => [
    Math.round(s.x * 20), Math.round(s.y * 20), Math.round(s.ang * 100), Math.round((s.whip || 0) * 100)
  ]);
}

export function decompressGhost(packed) {
  return packed.map(a => ({ x: a[0] / 20, y: a[1] / 20, ang: a[2] / 100, whip: a[3] / 100 }));
}

function load() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return defaultProfile();
    const parsed = JSON.parse(raw);
    return { ...defaultProfile(), ...parsed, settings: { ...defaultProfile().settings, ...(parsed.settings || {}) } };
  } catch (e) {
    return defaultProfile();
  }
}
