// MotoRush — application shell: screens, HUD, economy flow, and the frame loop.

import { Profile, rankTier } from './save.js';
import { InputManager } from './input.js';
import { Renderer } from './render.js';
import { AudioEngine } from './audio.js';
import { Race } from './game.js';
import { generateTrack, trackCatalogue } from './track.js';
import { AdaptiveDifficulty } from './ai.js';
import {
  BIKES, UPGRADES, BIOMES, BIOME_KEYS, GEAR, ACHIEVEMENTS,
  CHAMPIONSHIPS, SEASON, xpForLevel
} from './data.js';

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const fmtTime = (t) => {
  if (!isFinite(t)) return '—';
  const m = Math.floor(t / 60), s = t - m * 60;
  return `${m}:${s < 10 ? '0' : ''}${s.toFixed(2)}`;
};
const fmtNum = (n) => Math.round(n).toLocaleString();

const COLOR_MAP = {
  Slate: '#5b6a82', Ember: '#ff5d3b', Frost: '#8fd9ff', Venom: '#8bf05a', Carbon: '#232830',
  Solar: '#ffc44d', Classic: '#f0f3f8', Fade: '#c88bff', Stripe: '#ffd166', Camo: '#7d8a5c',
  Neon: '#5ef2d6', Retro: '#e8a13a', White: '#f2f4f7', Black: '#20242e', Yellow: '#f5d03a',
  Red: '#e2503f', Silver: '#cfd6e0', Gold: '#e8c15a', Anodized: '#7ad1ff'
};

class App {
  constructor() {
    this.profile = new Profile();
    this.audio = new AudioEngine();
    this.input = new InputManager(this.profile);
    this.renderer = new Renderer($('#canvas'));
    this.catalogue = trackCatalogue(240);
    this.adaptive = new AdaptiveDifficulty(this.profile.data.adaptive);
    this.race = null;
    this.screen = 'menu';
    this.paused = false;
    this.lastT = performance.now();
    this.fpsAvg = 60;

    this.applySettings();
    this.bindUI();
    this.detectTouch();
    this.refreshWallet();
    this.showLoginReward();
    this.resize();
    window.addEventListener('resize', () => this.resize());
    requestAnimationFrame((t) => this.frame(t));
  }

  // ——— Setup ————————————————————————————————————————
  detectTouch() {
    const touch = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
    document.body.classList.toggle('touch-mode', touch);
    this.input.bindTouch($('#touch'));
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, this.profile.data.settings.quality === 'low' ? 1 : 2);
    this.renderer.resize(window.innerWidth, window.innerHeight, dpr);
  }

  applySettings() {
    const s = this.profile.data.settings;
    this.audio.masterVol = s.master; this.audio.sfxVol = s.sfx; this.audio.musicVol = s.music;
    this.audio.setBuses();
    this.renderer.quality = s.quality;
    this.renderer.motionBlur = s.motionBlur;
    this.renderer.colorblind = s.colorblind;
  }

  startAudio() {
    if (this.audio.ready) { this.audio.resume(); return; }
    this.audio.init();
    this.applySettings();
    this.audio.startMusic(() => (this.race ? clamp(Math.abs(this.race.player.vx) / 40, 0.1, 1) : 0.25));
  }

  bindUI() {
    document.addEventListener('pointerdown', () => this.startAudio(), { once: true });
    document.addEventListener('keydown', () => this.startAudio(), { once: true });

    $$('[data-go]').forEach(el => el.addEventListener('click', () => {
      this.audio.ui('tap');
      this.go(el.dataset.go);
    }));
    $('#btn-settings').addEventListener('click', () => { this.audio.ui('tap'); this.go('settings'); });
    $('#btn-back').addEventListener('click', () => { this.audio.ui('back'); this.show('menu'); });
    $('#btn-pause').addEventListener('click', () => this.togglePause());
    this.input.onPause = () => { if (this.screen === 'race') this.togglePause(); };
    this.input.onReset = () => { if (this.race && !this.race.player.finished) this.race.player.respawn(); };

    $$('#pause [data-pause]').forEach(b => b.addEventListener('click', () => {
      this.audio.ui('tap');
      const a = b.dataset.pause;
      if (a === 'resume') this.togglePause(false);
      else if (a === 'restart') { this.togglePause(false); this.startRace(this.lastRaceOpts); }
      else if (a === 'settings') { this.togglePause(false); this.go('settings'); }
      else { this.togglePause(false); this.quitRace(); }
    }));
  }

  show(name) {
    this.screen = name;
    $$('.screen').forEach(s => s.classList.remove('active'));
    if (name === 'race') $('#screen-race').classList.add('active');
    else if (name === 'menu') { $('#screen-menu').classList.add('active'); this.refreshMenu(); }
    else $('#screen-panel').classList.add('active');
  }

  toast(text, kind = '') {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.textContent = text;
    $('#toasts').appendChild(el);
    setTimeout(() => { el.style.opacity = '0'; el.style.transform = 'translateY(-8px)'; }, 2200);
    setTimeout(() => el.remove(), 2700);
  }

  refreshWallet() {
    const d = this.profile.data;
    $('#coin-val').textContent = fmtNum(d.coins);
    $('#gem-val').textContent = fmtNum(d.gems);
    $$('.coin-val').forEach(e => e.textContent = fmtNum(d.coins));
    $$('.gem-val').forEach(e => e.textContent = fmtNum(d.gems));
  }

  refreshMenu() {
    const d = this.profile.data;
    $('#lvl-val').textContent = d.level;
    $('#player-name').textContent = d.name;
    $('#rank-tier').textContent = `${d.rank.tier} · ${d.rank.points}`;
    $('#ranked-sub').textContent = `${d.rank.tier} · ${d.rank.points}`;
    $('#season-sub').textContent = `Tier ${d.season.tier} / ${SEASON.tiers}`;
    const need = xpForLevel(d.level);
    $('#xp-fill').style.width = `${clamp((d.xp / need) * 100, 0, 100)}%`;
    $('#xp-text').textContent = `${fmtNum(d.xp)} / ${fmtNum(need)} XP`;
    $('#streak-box').textContent = d.loginStreak > 1 ? `${d.loginStreak}-day streak` : '';
    this.refreshWallet();
  }

  showLoginReward() {
    const r = this.profile.data.loginStreak;
    if (r >= 1) this.toast(`Daily bonus claimed · day ${r}`, 'good');
  }

  // ——— Navigation ————————————————————————————————
  go(where) {
    const map = {
      quick: () => this.panelQuick(),
      career: () => this.panelCareer(),
      timetrial: () => this.panelTimeTrial(),
      ranked: () => this.panelRanked(),
      garage: () => this.panelGarage(),
      customize: () => this.panelCustomize(),
      tracks: () => this.panelTracks(),
      missions: () => this.panelMissions(),
      season: () => this.panelSeason(),
      records: () => this.panelRecords(),
      settings: () => this.panelSettings()
    };
    (map[where] || map.quick)();
  }

  panel(title, html) {
    $('#panel-title').textContent = title;
    $('#panel-body').innerHTML = html;
    this.show('panel');
    this.refreshWallet();
  }

  // ——— Quick race ————————————————————————————————
  panelQuick() {
    const biomes = BIOME_KEYS.map(k =>
      `<button class="chip ${k === 'motocross' ? 'on' : ''}" data-biome="${k}">${BIOMES[k].name}</button>`).join('');
    this.panel('Quick Race', `
      <div class="section-title">Surface</div>
      <div class="chips" id="biome-chips">${biomes}</div>
      <div class="section-title">Difficulty</div>
      <div class="chips" id="diff-chips">
        ${['Rookie:0.35', 'Amateur:0.55', 'Pro:0.75', 'Factory:0.95'].map((s, i) => {
          const [n, v] = s.split(':');
          return `<button class="chip ${i === 1 ? 'on' : ''}" data-diff="${v}">${n}</button>`;
        }).join('')}
      </div>
      <div class="section-title">Field</div>
      <div class="chips" id="field-chips">
        ${[1, 3, 5, 7].map((n, i) => `<button class="chip ${n === 5 ? 'on' : ''}" data-field="${n}">${n + 1} riders</button>`).join('')}
      </div>
      <div class="section-title">Bike</div>
      <div class="item"><h4>${this.profile.bikeSpec().name}<span class="tag">${this.profile.bikeSpec().cls}</span></h4>
        <small class="muted">${this.profile.bikeSpec().blurb}</small>
        <button class="btn small" id="q-garage">Change in Garage</button></div>
      <button class="btn primary" id="q-start" style="margin-top:12px">Drop the Gate</button>
    `);
    const pickGroup = (id, attr) => $$(`#${id} .chip`).forEach(c => c.addEventListener('click', () => {
      $$(`#${id} .chip`).forEach(x => x.classList.remove('on'));
      c.classList.add('on'); this.audio.ui('tap');
    }));
    pickGroup('biome-chips'); pickGroup('diff-chips'); pickGroup('field-chips');
    $('#q-garage').addEventListener('click', () => this.panelGarage());
    $('#q-start').addEventListener('click', () => {
      const biome = $('#biome-chips .chip.on').dataset.biome;
      const difficulty = parseFloat($('#diff-chips .chip.on').dataset.diff);
      const aiCount = parseInt($('#field-chips .chip.on').dataset.field, 10);
      this.startRace({ mode: 'quick', biome, difficulty, aiCount, seed: (Math.random() * 1e9) | 0 });
    });
  }

  // ——— Career ————————————————————————————————————
  panelCareer() {
    const d = this.profile.data;
    const rows = CHAMPIONSHIPS.map(c => {
      const st = d.championships[c.id] || { round: 0, points: 0, done: false };
      const pct = (st.round / c.rounds) * 100;
      return `<div class="list-row">
        <div class="grow">
          <b>${c.name}</b>
          <small>${c.cls} · ${c.rounds} rounds · ${st.points} pts${st.done ? ' · completed' : ''}</small>
          <div class="progress"><i style="width:${pct}%"></i></div>
        </div>
        <button class="btn small primary" data-champ="${c.id}">${st.round ? 'Continue' : 'Enter'}</button>
      </div>`;
    }).join('');
    this.panel('Career', `<div class="section-title">Championships</div><div class="list">${rows}</div>
      <div class="section-title">How it works</div>
      <div class="item"><small class="muted">Each round is a fresh procedural track from that series' rotation.
      Points are awarded 25/20/16/13/11/10 by finishing position. Win the series for a large payout,
      season XP and a plate.</small></div>`);
    $$('[data-champ]').forEach(b => b.addEventListener('click', () => {
      const c = CHAMPIONSHIPS.find(x => x.id === b.dataset.champ);
      this.startChampionshipRound(c);
    }));
  }

  startChampionshipRound(c) {
    const d = this.profile.data;
    const st = d.championships[c.id] || (d.championships[c.id] = { round: 0, points: 0, done: false });
    if (st.done) { st.round = 0; st.points = 0; st.done = false; }
    const biome = c.biomes[st.round % c.biomes.length];
    this.startRace({
      mode: 'championship', champId: c.id, biome: BIOMES[biome] ? biome : 'motocross',
      difficulty: c.difficulty, aiCount: 5, seed: (c.id.length * 7919 + st.round * 104729) | 0
    });
  }

  // ——— Time trial / ranked ————————————————————————
  panelTimeTrial() {
    const list = this.catalogue.slice(0, 40).map(t => {
      const rec = this.profile.data.records[t.id];
      return `<div class="list-row">
        <div class="grow"><b>${BIOMES[t.biome].name} · #${t.id}</b>
        <small>Difficulty ${(t.difficulty * 100) | 0}% · Best ${rec ? fmtTime(rec.time) : '—'}${rec && rec.ghost ? ' · ghost saved' : ''}</small></div>
        <button class="btn small primary" data-tt="${t.id}">Ride</button>
      </div>`;
    }).join('');
    this.panel('Time Trial', `<div class="section-title">Solo runs — beat your ghost</div><div class="list">${list}</div>`);
    $$('[data-tt]').forEach(b => b.addEventListener('click', () => {
      const t = this.catalogue[parseInt(b.dataset.tt, 10)];
      this.startRace({
        mode: 'timetrial', trackId: t.id, biome: t.biome, difficulty: t.difficulty,
        seed: t.seed, aiCount: 0, ghost: this.profile.ghostFor(t.id)
      });
    }));
  }

  panelRanked() {
    const d = this.profile.data;
    const board = this.fakeLeaderboard(d.rank.points, d.name);
    this.panel('Ranked', `
      <div class="item"><h4>${d.rank.tier}<span class="tag hot">${d.rank.points} RP</span></h4>
      <small class="muted">Season best ${d.rank.best} RP. Placement against a matched field; RP moves with your
      finishing position relative to the expected result.</small></div>
      <div class="section-title">Leaderboard</div>
      <div class="list">${board.map((r, i) => `<div class="list-row"><span class="p">${i + 1}</span>
        <div class="grow"><b>${r.name}</b><small>${r.tier}</small></div><span>${r.points}</span></div>`).join('')}</div>
      <button class="btn primary" id="ranked-go" style="margin-top:12px">Find Match</button>
      <div class="item"><small class="muted">Matchmaking, lobbies and live opponents run against a local
      simulated field in this build — see README for the networking design.</small></div>
    `);
    $('#ranked-go').addEventListener('click', () => {
      const diff = clamp(0.35 + (d.rank.points - 800) / 3000, 0.35, 1);
      this.startRace({ mode: 'ranked', biome: BIOME_KEYS[(Math.random() * BIOME_KEYS.length) | 0],
        difficulty: diff, aiCount: 5, seed: (Math.random() * 1e9) | 0 });
    });
  }

  fakeLeaderboard(myPoints, myName) {
    const names = ['Karo', 'Vance', 'Rook', 'Sable', 'Dune', 'Trace', 'Nyx', 'Falk', 'Pike', 'Rhen'];
    const rows = names.map((n, i) => ({ name: n, points: Math.round(myPoints + 400 - i * 78 + (i * 37) % 60) }));
    rows.push({ name: myName, points: myPoints });
    rows.sort((a, b) => b.points - a.points);
    return rows.map(r => ({ ...r, tier: rankTier(r.points) }));
  }

  // ——— Garage ————————————————————————————————————
  panelGarage() {
    const d = this.profile.data;
    const cards = BIKES.map(b => {
      const owned = this.profile.ownsBike(b.id);
      const locked = d.level < b.level;
      const sel = d.currentBike === b.id;
      const bar = (label, v, max) =>
        `<div class="stat-line"><span style="width:52px">${label}</span><span class="bar"><i style="width:${clamp((v / max) * 100, 3, 100)}%"></i></span></div>`;
      return `<div class="item ${sel ? 'selected' : ''} ${!owned && locked ? 'locked' : ''}">
        <div class="swatch" style="background:linear-gradient(135deg,${b.color},#111823)"></div>
        <h4>${b.name}<span class="tag">${b.cls}</span></h4>
        <small class="muted">${b.blurb}</small>
        ${bar('Power', b.power, 17000)}${bar('Speed', b.topSpeed, 58)}${bar('Grip', b.grip, 1.2)}${bar('Sus', b.travel, 0.36)}
        <div class="row">
          ${owned
            ? `<button class="btn small ${sel ? '' : 'primary'}" data-select="${b.id}">${sel ? 'Selected' : 'Select'}</button>
               <button class="btn small" data-upg="${b.id}">Upgrades</button>`
            : locked
              ? `<span class="tag">Unlocks at level ${b.level}</span>`
              : `<button class="btn small primary" data-buy="${b.id}">Buy ${fmtNum(b.price)}</button>`}
        </div>
      </div>`;
    }).join('');
    this.panel('Garage', `<div class="card-row">${cards}</div>`);
    $$('[data-select]').forEach(b => b.addEventListener('click', () => {
      d.currentBike = b.dataset.select; this.profile.save(); this.audio.ui('tap'); this.panelGarage();
    }));
    $$('[data-buy]').forEach(b => b.addEventListener('click', () => {
      const res = this.profile.buyBike(b.dataset.buy);
      if (res.ok) { this.audio.ui('buy'); this.toast('Bike unlocked', 'good'); this.panelGarage(); }
      else { this.audio.ui('deny'); this.toast(res.reason === 'coins' ? 'Not enough coins' : 'Locked', 'bad'); }
    }));
    $$('[data-upg]').forEach(b => b.addEventListener('click', () => this.panelUpgrades(b.dataset.upg)));
  }

  panelUpgrades(bikeId) {
    const spec = this.profile.bikeSpec(bikeId);
    const u = this.profile.upgradesFor(bikeId);
    const rows = UPGRADES.map(up => {
      const lvl = u[up.id] || 0;
      const cost = this.profile.upgradeCost(bikeId, up);
      const pips = Array.from({ length: up.max }, (_, i) =>
        `<i style="display:inline-block;width:14px;height:6px;border-radius:3px;margin-right:3px;background:${i < lvl ? 'var(--accent)' : 'rgba(255,255,255,.14)'}"></i>`).join('');
      return `<div class="list-row"><div class="grow"><b>${up.name}</b><small>${up.effect}</small><div style="margin-top:6px">${pips}</div></div>
        ${lvl >= up.max ? '<span class="tag good">MAX</span>'
          : `<button class="btn small primary" data-up="${up.id}">${fmtNum(cost)}</button>`}</div>`;
    }).join('');
    this.panel(`${spec.name} — Upgrades`, `<div class="list">${rows}</div>
      <button class="btn" id="back-garage" style="margin-top:12px">← Garage</button>`);
    $('#back-garage').addEventListener('click', () => this.panelGarage());
    $$('[data-up]').forEach(b => b.addEventListener('click', () => {
      const up = UPGRADES.find(x => x.id === b.dataset.up);
      const res = this.profile.buyUpgrade(bikeId, up);
      if (res.ok) { this.audio.ui('buy'); this.toast(`${up.name} → level ${res.level}`, 'good'); }
      else { this.audio.ui('deny'); this.toast(res.reason === 'coins' ? 'Not enough coins' : 'Maxed', 'bad'); }
      this.panelUpgrades(bikeId);
    }));
  }

  // ——— Customization ————————————————————————————
  panelCustomize() {
    const c = this.profile.data.cosmetics;
    const slots = Object.keys(GEAR).map(slot => {
      const items = GEAR[slot].map(it => {
        const owned = (c.owned[slot] || []).includes(it);
        const on = c.equipped[slot] === it;
        const col = COLOR_MAP[it] || '#5b6a82';
        return `<button class="chip ${on ? 'on' : ''}" data-slot="${slot}" data-item="${it}">
          <span style="display:inline-block;width:9px;height:9px;border-radius:50%;background:${col};margin-right:6px"></span>
          ${it}${owned ? '' : ` · ${fmtNum(this.profile.cosmeticPrice(slot))}`}</button>`;
      }).join('');
      return `<div class="section-title">${slot}</div><div class="chips">${items}</div>`;
    }).join('');
    this.panel('Customize', `
      <div class="item"><h4>Name plate</h4>
        <div class="row"><input type="text" id="name-in" maxlength="12" value="${this.profile.data.name}" />
        <input type="text" id="num-in" maxlength="3" style="width:70px" value="${this.profile.data.number}" />
        <button class="btn small" id="save-name">Save</button></div></div>
      ${slots}`);
    $('#save-name').addEventListener('click', () => {
      this.profile.data.name = ($('#name-in').value || 'Rider').slice(0, 12);
      this.profile.data.number = clamp(parseInt($('#num-in').value, 10) || 1, 1, 999);
      this.profile.save(); this.audio.ui('buy'); this.toast('Saved', 'good'); this.refreshMenu();
    });
    $$('[data-slot]').forEach(b => b.addEventListener('click', () => {
      const { slot, item } = b.dataset;
      if ((c.owned[slot] || []).includes(item)) {
        this.profile.equip(slot, item); this.audio.ui('tap');
      } else {
        const res = this.profile.buyCosmetic(slot, item);
        if (res.ok) { this.profile.equip(slot, item); this.audio.ui('buy'); this.toast('Unlocked', 'good'); }
        else { this.audio.ui('deny'); this.toast('Not enough coins', 'bad'); return this.panelCustomize(); }
      }
      this.panelCustomize();
    }));
  }

  gearColors() {
    const e = this.profile.data.cosmetics.equipped;
    return {
      helmetColor: COLOR_MAP[e.helmet] || '#ff5d73',
      jerseyColor: COLOR_MAP[e.jersey] || '#f0f3f8',
      pantsColor: COLOR_MAP[e.pants] || '#232a36',
      plateColor: COLOR_MAP[e.plate] || '#f2f4f7',
      rim: COLOR_MAP[e.wheels] || '#cfd6e0'
    };
  }

  // ——— Tracks ————————————————————————————————————
  panelTracks(page = 0) {
    const per = 24;
    const slice = this.catalogue.slice(page * per, page * per + per);
    const rows = slice.map(t => {
      const rec = this.profile.data.records[t.id];
      return `<div class="item"><h4>#${t.id} ${BIOMES[t.biome].name}<span class="tag">${(t.difficulty * 100) | 0}%</span></h4>
        <small class="muted">Seed ${t.seed} · Best ${rec ? fmtTime(rec.time) : '—'}</small>
        <button class="btn small primary" data-track="${t.id}">Ride</button></div>`;
    }).join('');
    const pages = Math.ceil(this.catalogue.length / per);
    this.panel('Tracks', `<div class="card-row">${rows}</div>
      <div class="row" style="justify-content:center;margin-top:12px">
        <button class="btn small" id="pg-prev" ${page === 0 ? 'disabled' : ''}>←</button>
        <span class="muted">Page ${page + 1} / ${pages}</span>
        <button class="btn small" id="pg-next" ${page + 1 >= pages ? 'disabled' : ''}>→</button></div>`);
    $('#pg-prev').addEventListener('click', () => this.panelTracks(page - 1));
    $('#pg-next').addEventListener('click', () => this.panelTracks(page + 1));
    $$('[data-track]').forEach(b => b.addEventListener('click', () => {
      const t = this.catalogue[parseInt(b.dataset.track, 10)];
      this.startRace({ mode: 'quick', trackId: t.id, biome: t.biome, difficulty: t.difficulty,
        seed: t.seed, aiCount: 5, ghost: this.profile.ghostFor(t.id) });
    }));
  }

  // ——— Missions / season / records ————————————————
  panelMissions() {
    const d = this.profile.data;
    const render = (scope, list) => list.map(m => {
      const pct = clamp((m.progress / m.goal) * 100, 0, 100);
      return `<div class="list-row"><div class="grow"><b>${m.desc}</b>
        <small>${Math.min(m.progress, m.goal)} / ${m.goal} · ${m.xp} XP · ${fmtNum(m.coins)} coins</small>
        <div class="progress"><i style="width:${pct}%"></i></div></div>
        ${m.claimed ? '<span class="tag good">Claimed</span>'
          : m.progress >= m.goal ? `<button class="btn small primary" data-claim="${scope}:${m.id}">Claim</button>`
            : '<span class="tag">In progress</span>'}</div>`;
    }).join('');
    this.panel('Missions', `
      <div class="section-title">Daily · resets at midnight</div><div class="list">${render('daily', d.daily.list)}</div>
      <div class="section-title">Weekly</div><div class="list">${render('weekly', d.weekly.list)}</div>
      <div class="section-title">Achievements</div>
      <div class="list">${ACHIEVEMENTS.map(a => `<div class="list-row"><div class="grow"><b>${a.name}</b><small>${a.desc}</small></div>
        ${d.achievements[a.id] ? '<span class="tag good">Unlocked</span>' : '<span class="tag">Locked</span>'}</div>`).join('')}</div>`);
    $$('[data-claim]').forEach(b => b.addEventListener('click', () => {
      const [scope, id] = b.dataset.claim.split(':');
      const res = this.profile.claimMission(scope, id);
      if (res) { this.audio.ui('buy'); this.toast(`+${res.xp} XP · +${fmtNum(res.coins)} coins`, 'good'); }
      this.panelMissions();
    }));
  }

  panelSeason() {
    const d = this.profile.data;
    const tiers = Array.from({ length: SEASON.tiers }, (_, i) => {
      const t = i + 1;
      const r = SEASON.rewards(t);
      const done = d.season.tier >= t;
      const claimed = d.season.claimed.includes(t);
      return `<div class="tier ${done ? 'done' : ''}"><b>${t}</b>${r.label}
        ${done && !claimed ? `<div><button class="btn small primary" data-tier="${t}" style="margin-top:6px">Claim</button></div>`
          : claimed ? '<div class="tag good" style="margin-top:6px">✓</div>' : ''}</div>`;
    }).join('');
    const pct = ((d.season.xp % SEASON.xpPerTier) / SEASON.xpPerTier) * 100;
    this.panel('Season Pass', `
      <div class="item"><h4>${SEASON.name}<span class="tag hot">Tier ${d.season.tier}/${SEASON.tiers}</span></h4>
        <div class="progress"><i style="width:${pct}%"></i></div>
        <small class="muted">Every race, mission and championship feeds season XP. All gameplay rewards are
        cosmetic or currency — no purchasable performance.</small></div>
      <div class="section-title">Rewards</div><div class="tier-strip">${tiers}</div>`);
    $$('[data-tier]').forEach(b => b.addEventListener('click', () => {
      const t = parseInt(b.dataset.tier, 10);
      const r = SEASON.rewards(t);
      d.season.claimed.push(t);
      if (r.coins) this.profile.addCoins(r.coins);
      else this.profile.addCoins(1000);
      this.profile.save(); this.audio.ui('buy'); this.toast(`Tier ${t} claimed`, 'good');
      this.panelSeason();
    }));
  }

  panelRecords() {
    const d = this.profile.data;
    const recs = Object.entries(d.records).sort((a, b) => a[0] - b[0]);
    this.panel('Records', `
      <div class="result-grid">
        <div><b>${d.stats.races}</b><span>RACES</span></div>
        <div><b>${d.stats.wins}</b><span>WINS</span></div>
        <div><b>${d.stats.perfects}</b><span>PERFECTS</span></div>
        <div><b>${d.stats.crashes}</b><span>CRASHES</span></div>
        <div><b>${Math.round(d.stats.airtime)}s</b><span>AIR TIME</span></div>
        <div><b>${Math.round(d.stats.whipdeg)}°</b><span>WHIP</span></div>
      </div>
      <div class="section-title">Track records</div>
      <div class="list">${recs.length ? recs.map(([id, r]) =>
        `<div class="list-row"><div class="grow"><b>Track #${id}</b><small>${r.ghost ? 'Ghost saved' : 'No ghost'}</small></div>
         <span>${fmtTime(r.time)}</span></div>`).join('') : '<div class="item"><small class="muted">No records yet.</small></div>'}</div>`);
  }

  // ——— Settings ————————————————————————————————
  panelSettings() {
    const s = this.profile.data.settings;
    const slider = (id, label, val) =>
      `<div class="item"><div class="spread"><b>${label}</b><span class="muted" id="${id}-out">${Math.round(val * 100)}%</span></div>
       <input type="range" id="${id}" min="0" max="1" step="0.01" value="${val}" /></div>`;
    this.panel('Settings', `
      <div class="section-title">Audio</div>
      ${slider('set-master', 'Master', s.master)}${slider('set-sfx', 'Effects', s.sfx)}${slider('set-music', 'Music', s.music)}
      <div class="section-title">Graphics</div>
      <div class="item"><div class="spread"><b>Quality</b>
        <div class="chips">${['low', 'medium', 'high'].map(q =>
          `<button class="chip ${s.quality === q ? 'on' : ''}" data-q="${q}">${q}</button>`).join('')}</div></div></div>
      <div class="item"><div class="spread"><b>Motion effects</b>
        <button class="btn small" id="set-blur">${s.motionBlur ? 'On' : 'Off'}</button></div></div>
      <div class="item"><div class="spread"><b>Screen shake</b><span class="muted" id="set-shake-out">${Math.round(s.shake * 100)}%</span></div>
        <input type="range" id="set-shake" min="0" max="1" step="0.05" value="${s.shake}" /></div>
      <div class="section-title">Accessibility</div>
      <div class="item"><div class="spread"><b>Colorblind mode</b>
        <div class="chips">${['none', 'protanopia', 'deuteranopia', 'tritanopia'].map(c =>
          `<button class="chip ${s.colorblind === c ? 'on' : ''}" data-cb="${c}">${c}</button>`).join('')}</div></div></div>
      <div class="item"><div class="spread"><b>Landing assist</b><button class="btn small" id="set-al">${s.assistLanding ? 'On' : 'Off'}</button></div>
        <small class="muted">Blends a corrective lean into your input in the air. Never adds grip.</small></div>
      <div class="item"><div class="spread"><b>Throttle assist</b><button class="btn small" id="set-at">${s.assistThrottle ? 'On' : 'Off'}</button></div>
        <small class="muted">Trims throttle when the front end is looping out.</small></div>
      <div class="item"><div class="spread"><b>Subtitles / callouts</b><button class="btn small" id="set-sub">${s.subtitles ? 'On' : 'Off'}</button></div></div>
      <div class="section-title">Controls</div>
      <div class="item"><small class="muted">Keyboard: ↑ / W throttle · ↓ / S brake · ← → lean · A / D whip · R reset · Esc pause.
        Gamepad: RT throttle, LT brake, left stick lean, right stick whip. Touch controls appear automatically on
        touchscreens.</small>
        <div class="row" style="margin-top:8px">${Object.entries(s.keys).map(([k, v]) =>
          `<button class="chip" data-rebind="${k}">${k}: ${v}</button>`).join('')}</div></div>
      <div class="section-title">Data</div>
      <div class="item"><button class="btn danger" id="set-reset">Reset profile</button></div>
    `);

    const bindSlider = (id, key) => {
      const el = $(`#${id}`);
      el.addEventListener('input', () => {
        s[key] = parseFloat(el.value);
        $(`#${id}-out`).textContent = `${Math.round(s[key] * 100)}%`;
        this.applySettings(); this.profile.save();
      });
    };
    bindSlider('set-master', 'master'); bindSlider('set-sfx', 'sfx'); bindSlider('set-music', 'music');
    bindSlider('set-shake', 'shake');
    $$('[data-q]').forEach(b => b.addEventListener('click', () => {
      s.quality = b.dataset.q; this.applySettings(); this.resize(); this.profile.save(); this.panelSettings();
    }));
    $$('[data-cb]').forEach(b => b.addEventListener('click', () => {
      s.colorblind = b.dataset.cb; this.applySettings(); this.profile.save(); this.panelSettings();
    }));
    $('#set-blur').addEventListener('click', () => { s.motionBlur = !s.motionBlur; this.applySettings(); this.profile.save(); this.panelSettings(); });
    $('#set-al').addEventListener('click', () => { s.assistLanding = !s.assistLanding; this.profile.save(); this.panelSettings(); });
    $('#set-at').addEventListener('click', () => { s.assistThrottle = !s.assistThrottle; this.profile.save(); this.panelSettings(); });
    $('#set-sub').addEventListener('click', () => { s.subtitles = !s.subtitles; this.profile.save(); this.panelSettings(); });
    $$('[data-rebind]').forEach(b => b.addEventListener('click', () => {
      const key = b.dataset.rebind;
      b.textContent = `${key}: press a key…`;
      const handler = (e) => {
        e.preventDefault();
        s.keys[key] = e.key;
        this.profile.save();
        window.removeEventListener('keydown', handler, true);
        this.panelSettings();
      };
      window.addEventListener('keydown', handler, true);
    }));
    $('#set-reset').addEventListener('click', () => {
      if (confirm('Erase all progress?')) { this.profile.reset(); this.applySettings(); this.toast('Profile reset'); this.show('menu'); }
    });
  }

  // ——— Race lifecycle ————————————————————————————
  startRace(opts) {
    this.startAudio();
    this.lastRaceOpts = opts;
    const s = this.profile.data.settings;
    const spec = this.profile.bikeSpec();
    const track = generateTrack({ seed: opts.seed, biome: opts.biome, difficulty: opts.difficulty });
    this.race = new Race({
      ...opts,
      track,
      playerSpec: spec,
      upgrades: this.profile.upgradesFor(),
      playerName: this.profile.data.name,
      playerNumber: this.profile.data.number,
      quality: s.quality,
      assist: { landing: s.assistLanding, throttle: s.assistThrottle },
      difficulty: opts.mode === 'quick' ? opts.difficulty : clamp(opts.difficulty * (0.7 + this.adaptive.value * 0.5), 0.2, 1)
    });
    $('#results').classList.remove('show');
    this.show('race');
  }

  quitRace() {
    this.race = null;
    $('#results').classList.remove('show');
    this.show('menu');
  }

  togglePause(force) {
    const on = force ?? !this.paused;
    this.paused = on;
    $('#pause').classList.toggle('show', on);
    if (on) this.audio.ui('back');
  }

  finishRace() {
    const r = this.race.results;
    if (!r || this.resultsShown) return;
    this.resultsShown = true;
    const opts = this.lastRaceOpts;
    const d = this.profile.data;

    // Rewards. Deliberately generous on skill, not on spending.
    const posBonus = [1, 0.75, 0.6, 0.5, 0.42, 0.36][r.position - 1] ?? 0.3;
    const baseXP = 220 + Math.round(r.track.difficulty * 260);
    const styleXP = Math.round(r.stats.style * 0.5 + r.stats.perfects * 25);
    const xp = Math.round((baseXP + styleXP) * posBonus + (r.position === 1 ? 150 : 0));
    const coins = Math.round((420 + r.track.difficulty * 520 + r.stats.perfects * 30) * posBonus);

    const levelRes = this.profile.addXP(xp);
    this.profile.addCoins(coins);
    this.profile.applyRaceStats({
      races: 1, wins: r.position === 1 ? 1 : 0, perfects: r.stats.perfects,
      crashes: r.stats.crashes, airtime: r.stats.airtime, whipdeg: r.stats.whipdeg,
      cleanraces: r.stats.crashes === 0 ? 1 : 0, distance: r.track.length
    });

    const unlocked = [];
    if (r.stats.perfects >= 5) { const a = this.profile.unlockAchievement('perfect5'); if (a) unlocked.push(a); }
    if (r.stats.whipdeg >= 360) { const a = this.profile.unlockAchievement('whip360'); if (a) unlocked.push(a); }

    let recordText = '';
    if (opts.trackId != null) {
      const isPB = this.profile.recordTime(opts.trackId, r.time, r.ghost);
      recordText = isPB ? 'New personal best — ghost saved' : '';
    }

    let rankText = '';
    if (opts.mode === 'ranked') {
      const rr = this.profile.applyRanked(r.position, r.fieldSize);
      rankText = `${rr.delta >= 0 ? '+' : ''}${rr.delta} RP · ${rr.tier} ${rr.points}`;
    }

    let champText = '';
    if (opts.mode === 'championship') {
      const c = CHAMPIONSHIPS.find(x => x.id === opts.champId);
      const st = d.championships[c.id];
      const pts = [25, 20, 16, 13, 11, 10][r.position - 1] ?? 8;
      st.points += pts; st.round++;
      if (st.round >= c.rounds) {
        st.done = true;
        this.profile.addCoins(c.reward);
        this.profile.applyRaceStats({ champs: 1 });
        champText = `Series complete — ${st.points} pts · +${fmtNum(c.reward)} coins`;
      } else {
        champText = `Round ${st.round}/${c.rounds} · +${pts} pts (${st.points} total)`;
      }
      this.profile.save();
    }

    this.adaptive.record(r.position, r.fieldSize);
    d.adaptive = this.adaptive.value;
    this.profile.save();

    const order = r.order.slice(0, 6).map((s, i) =>
      `<div class="reward-line"><span>${i + 1}. ${s.bike === this.race.player ? d.name : s.name}</span>
       <span>${s.bike.finished ? fmtTime(s.bike.finishTime) : '—'}</span></div>`).join('');

    $('#results-card').innerHTML = `
      <div class="result-hero">
        <div class="result-pos">P${r.position}</div>
        <div class="result-time">${fmtTime(r.time)}</div>
        <div class="muted">${r.track.name} · ${r.track.biome.name}${recordText ? ` · ${recordText}` : ''}</div>
      </div>
      <div class="result-grid">
        <div><b>${r.stats.perfects}</b><span>PERFECT</span></div>
        <div><b>${r.stats.crashes}</b><span>CRASHES</span></div>
        <div><b>${r.stats.airtime.toFixed(1)}s</b><span>AIR</span></div>
        <div><b>${Math.round(r.stats.whipdeg)}°</b><span>WHIP</span></div>
        <div><b>${r.stats.style}</b><span>STYLE</span></div>
        <div><b>${Math.round(r.track.length)}m</b><span>LENGTH</span></div>
      </div>
      <div class="reward-line"><span>XP earned</span><b>+${fmtNum(xp)}</b></div>
      <div class="reward-line"><span>Coins</span><b>+${fmtNum(coins)}</b></div>
      ${levelRes.levels.length ? `<div class="reward-line"><span>Level up</span><b>→ ${d.level}</b></div>` : ''}
      ${levelRes.tiersGained ? `<div class="reward-line"><span>Season tiers</span><b>+${levelRes.tiersGained}</b></div>` : ''}
      ${rankText ? `<div class="reward-line"><span>Ranked</span><b>${rankText}</b></div>` : ''}
      ${champText ? `<div class="reward-line"><span>Championship</span><b>${champText}</b></div>` : ''}
      ${unlocked.map(a => `<div class="reward-line"><span>Achievement</span><b>${a.name}</b></div>`).join('')}
      <div class="section-title">Finishing order</div>${order}
      <div class="row" style="margin-top:14px">
        <button class="btn primary" id="res-again">Race Again</button>
        <button class="btn" id="res-menu">Menu</button>
      </div>`;
    $('#results').classList.add('show');
    $('#res-again').addEventListener('click', () => {
      this.resultsShown = false;
      const next = { ...opts, seed: opts.mode === 'championship' ? undefined : (Math.random() * 1e9) | 0 };
      if (opts.mode === 'championship') {
        const c = CHAMPIONSHIPS.find(x => x.id === opts.champId);
        $('#results').classList.remove('show');
        if (d.championships[c.id].done) this.panelCareer(); else this.startChampionshipRound(c);
      } else this.startRace(next);
    });
    $('#res-menu').addEventListener('click', () => { this.resultsShown = false; this.quitRace(); });

    if (levelRes.levels.length) this.toast(`Level ${d.level}!`, 'good');
  }

  // ——— HUD ————————————————————————————————————
  updateHUD() {
    const race = this.race;
    if (!race) return;
    const p = race.player;
    const kmh = Math.max(0, p.forwardSpeed) * 3.6;
    $('#speed-val').textContent = Math.round(kmh);
    $('#gear-val').textContent = p.gear;
    const arc = $('#speedo-arc');
    const frac = clamp(kmh / (p.topSpeed * 3.6 * 1.1), 0, 1);
    arc.style.strokeDasharray = `${frac * 245} 327`;

    $('#hud-pos .val').textContent = `${race.playerPosition()}/${race.field.length}`;
    $('#hud-lap .val').textContent = `${Math.min(99, Math.round((p.x / race.track.finishX) * 100))}%`;
    $('#hud-lap .lbl').textContent = 'TRACK';
    $('#hud-time .val').textContent = fmtTime(race.time);
    $('#hud-combo .val').textContent = Math.round(p.style);

    const st = race.standings().slice(0, 6);
    $('#standings').innerHTML = st.map((s, i) =>
      `<div class="${s.bike === p ? 'me' : ''}"><span class="p">${i + 1}</span><span class="grow">${s.bike === p ? 'You' : s.name}</span></div>`).join('');

    const m = this.profile.data.daily.list.find(x => !x.claimed);
    $('#hud-mission').textContent = m ? `${m.desc} — ${Math.min(m.progress, m.goal)}/${m.goal}` : '';

    const msgs = $('#messages');
    msgs.innerHTML = race.messages.map(x => `<p class="${x.kind}">${x.text}</p>`).join('');
    $('#countdown').textContent = race.state === 'countdown' && race.countdown > 0
      ? String(Math.ceil(race.countdown)) : '';

    this.drawMinimap(race);
  }

  drawMinimap(race) {
    const c = $('#minimap-canvas');
    const ctx = c.getContext('2d');
    ctx.clearRect(0, 0, c.width, c.height);
    const t = race.track;
    const n = 180;
    let min = Infinity, max = -Infinity;
    const hs = [];
    for (let i = 0; i < n; i++) {
      const h = t.heightAt((i / (n - 1)) * t.length);
      hs.push(h); if (h < min) min = h; if (h > max) max = h;
    }
    const span = Math.max(1, max - min);
    ctx.beginPath();
    ctx.moveTo(0, c.height);
    for (let i = 0; i < n; i++) {
      ctx.lineTo((i / (n - 1)) * c.width, c.height - ((hs[i] - min) / span) * (c.height - 12) - 6);
    }
    ctx.lineTo(c.width, c.height); ctx.closePath();
    ctx.fillStyle = 'rgba(255,255,255,.14)'; ctx.fill();

    for (const b of race.field) {
      const px = clamp(b.x / t.length, 0, 1) * c.width;
      const py = c.height - ((t.heightAt(b.x) - min) / span) * (c.height - 12) - 6;
      ctx.fillStyle = b === race.player ? '#ff5d3b' : 'rgba(255,255,255,.5)';
      ctx.beginPath(); ctx.arc(px, py, b === race.player ? 4 : 2.6, 0, Math.PI * 2); ctx.fill();
    }
  }

  // ——— Frame loop ————————————————————————————————
  frame(now) {
    const dt = Math.min(0.05, (now - this.lastT) / 1000);
    this.lastT = now;
    this.fpsAvg = this.fpsAvg * 0.94 + (1 / Math.max(dt, 1e-4)) * 0.06;

    if (this.screen === 'race' && this.race && !this.paused) {
      const input = this.input.read();
      this.race.update(dt, input, this.audio.ready ? this.audio : null);
      this.race.cam.shake *= this.profile.data.settings.shake;
      this.race.stepCamera(dt, this.renderer.canvas);
      this.race.draw(this.renderer, this.gearColors());
      this.updateHUD();
      if (this.race.finished && !this.resultsShown && !this.resultsPending && this.race.results) {
        this.resultsPending = true;
        setTimeout(() => { this.resultsPending = false; this.finishRace(); }, 900);
      }
    }
    requestAnimationFrame((t) => this.frame(t));
  }
}

window.app = new App();
