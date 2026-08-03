// MotoRush — static game data: bikes, biomes, missions, cosmetics.
// All content original; no third-party assets or branding.

export const BIKES = [
  {
    id: 'sprout50', name: 'Sprout 50', cls: '50cc', price: 0, level: 1,
    mass: 92, power: 3400, topSpeed: 22, torqueCurve: 0.9,
    susStiff: 26000, susDamp: 1500, travel: 0.22, grip: 1.15, brake: 900,
    wheelbase: 1.05, seatHeight: 0.36, color: '#7fe08a',
    blurb: 'Forgiving mini-bike. Great for learning rhythm sections.'
  },
  {
    id: 'cadet65', name: 'Cadet 65', cls: '65cc', price: 2500, level: 2,
    mass: 98, power: 4600, topSpeed: 27, torqueCurve: 0.95,
    susStiff: 28000, susDamp: 1650, travel: 0.24, grip: 1.12, brake: 1050,
    wheelbase: 1.12, seatHeight: 0.38, color: '#63c7ff',
    blurb: 'Snappier than the 50 with a touch more punch out of berms.'
  },
  {
    id: 'ridge85', name: 'Ridge 85', cls: '85cc', price: 7000, level: 5,
    mass: 106, power: 6200, topSpeed: 32, torqueCurve: 1.0,
    susStiff: 31000, susDamp: 1800, travel: 0.27, grip: 1.08, brake: 1200,
    wheelbase: 1.2, seatHeight: 0.42, color: '#ffd166',
    blurb: 'The first bike that will bite you. Rewards clean throttle.'
  },
  {
    id: 'lance125', name: 'Lance 125', cls: '125cc', price: 16000, level: 9,
    mass: 118, power: 8400, topSpeed: 38, torqueCurve: 1.15,
    susStiff: 34000, susDamp: 1950, travel: 0.3, grip: 1.04, brake: 1350,
    wheelbase: 1.3, seatHeight: 0.46, color: '#ff8f5c',
    blurb: 'Two-stroke sting. Lives in the top half of the rev range.'
  },
  {
    id: 'vector250', name: 'Vector 250F', cls: '250cc', price: 34000, level: 14,
    mass: 126, power: 10200, topSpeed: 43, torqueCurve: 1.05,
    susStiff: 36000, susDamp: 2100, travel: 0.31, grip: 1.02, brake: 1500,
    wheelbase: 1.34, seatHeight: 0.47, color: '#c17dff',
    blurb: 'Balanced four-stroke. The championship all-rounder.'
  },
  {
    id: 'apex450', name: 'Apex 450', cls: '450cc', price: 62000, level: 20,
    mass: 138, power: 14500, topSpeed: 50, torqueCurve: 1.3,
    susStiff: 39000, susDamp: 2300, travel: 0.32, grip: 0.96, brake: 1700,
    wheelbase: 1.38, seatHeight: 0.48, color: '#ff5d73',
    blurb: 'Brutal torque. Wheelies on command, punishes greedy hands.'
  },
  {
    id: 'volt-e', name: 'Volt E1', cls: 'Electric', price: 78000, level: 24,
    mass: 132, power: 13000, topSpeed: 46, torqueCurve: 1.6,
    susStiff: 37000, susDamp: 2200, travel: 0.3, grip: 1.06, brake: 1600,
    wheelbase: 1.32, seatHeight: 0.45, color: '#5ef2d6', electric: true,
    blurb: 'Instant torque, no shift dips, eerie silence off the gate.'
  },
  {
    id: 'relic71', name: 'Relic 71', cls: 'Vintage', price: 45000, level: 18,
    mass: 148, power: 7600, topSpeed: 36, torqueCurve: 0.85,
    susStiff: 19000, susDamp: 1200, travel: 0.18, grip: 0.92, brake: 950,
    wheelbase: 1.42, seatHeight: 0.5, color: '#d9c39a',
    blurb: 'Twin shocks, drum brakes, zero forgiveness. Style points only.'
  },
  {
    id: 'nova-x', name: 'Nova X', cls: 'Fantasy', price: 120000, level: 30,
    mass: 110, power: 17000, topSpeed: 58, torqueCurve: 1.4,
    susStiff: 42000, susDamp: 2600, travel: 0.36, grip: 1.2, brake: 2000,
    wheelbase: 1.3, seatHeight: 0.44, color: '#8ab4ff', glow: true,
    blurb: 'Mag-lev damping and a powerband that never ends.'
  }
];

export const UPGRADES = [
  { id: 'engine', name: 'Engine', max: 5, cost: 1800, effect: 'Power +7% / level' },
  { id: 'suspension', name: 'Suspension', max: 5, cost: 1600, effect: 'Damping control +6% / level' },
  { id: 'tires', name: 'Tires', max: 5, cost: 1200, effect: 'Grip +5% / level' },
  { id: 'brakes', name: 'Brakes', max: 5, cost: 1000, effect: 'Braking +8% / level' },
  { id: 'transmission', name: 'Transmission', max: 5, cost: 1500, effect: 'Top speed +4% / level' },
  { id: 'weight', name: 'Weight Reduction', max: 5, cost: 2200, effect: 'Mass -3% / level' }
];

// Biome definition drives both track generation and the renderer's palette.
export const BIOMES = {
  motocross: {
    name: 'Motocross', sky: ['#7ec8ff', '#dff1ff'], ground: '#8a6244', groundDeep: '#5d4230',
    accent: '#c8a97a', rolling: 1.0, jumpBias: 1.0, whoopBias: 0.8, grip: 1.0, dust: '#c9a97e'
  },
  supercross: {
    name: 'Supercross', sky: ['#1b2340', '#38406b'], ground: '#6b4c37', groundDeep: '#3d2b1f',
    accent: '#9c7a55', rolling: 0.4, jumpBias: 1.6, whoopBias: 1.6, grip: 1.05, dust: '#b39a76',
    stadium: true, night: true
  },
  sand: {
    name: 'Sand', sky: ['#ffd79a', '#ffeccd'], ground: '#e0c081', groundDeep: '#b3945c',
    accent: '#f0dcae', rolling: 1.4, jumpBias: 0.7, whoopBias: 1.8, grip: 0.78, dust: '#efd9a8'
  },
  mud: {
    name: 'Mud', sky: ['#7f8794', '#b9c0c9'], ground: '#4f4034', groundDeep: '#332a22',
    accent: '#6a5646', rolling: 1.1, jumpBias: 0.9, whoopBias: 1.0, grip: 0.7, dust: '#5a4a3b',
    rain: true
  },
  forest: {
    name: 'Forest', sky: ['#8fd3a5', '#e6f7ea'], ground: '#5c4a32', groundDeep: '#3a2f20',
    accent: '#6f8f4f', rolling: 1.2, jumpBias: 0.9, whoopBias: 0.9, grip: 1.02, dust: '#8a7a58',
    trees: true
  },
  snow: {
    name: 'Snow', sky: ['#c9dcef', '#f6fbff'], ground: '#e8f0f7', groundDeep: '#a9bdd0',
    accent: '#ffffff', rolling: 1.0, jumpBias: 0.8, whoopBias: 0.9, grip: 0.62, dust: '#ffffff',
    snowing: true
  },
  desert: {
    name: 'Desert', sky: ['#ffb27a', '#ffe3c2'], ground: '#c98f5c', groundDeep: '#8e6039',
    accent: '#e6b98a', rolling: 1.5, jumpBias: 1.1, whoopBias: 0.7, grip: 0.9, dust: '#e3c093',
    heat: true
  },
  night: {
    name: 'Night', sky: ['#0b1026', '#1d2748'], ground: '#3b3145', groundDeep: '#241e2c',
    accent: '#5a4c68', rolling: 1.0, jumpBias: 1.2, whoopBias: 1.1, grip: 0.95, dust: '#6b5f78',
    night: true
  },
  mountain: {
    name: 'Mountain', sky: ['#6fa8dc', '#dbe9f7'], ground: '#6d6a63', groundDeep: '#43413c',
    accent: '#8d8a80', rolling: 1.8, jumpBias: 1.2, whoopBias: 0.6, grip: 0.98, dust: '#9c968a'
  },
  beach: {
    name: 'Beach', sky: ['#5fc9ff', '#d8f3ff'], ground: '#dcc394', groundDeep: '#a98f63',
    accent: '#f2e2bd', rolling: 0.9, jumpBias: 0.9, whoopBias: 1.2, grip: 0.85, dust: '#eddcb4'
  },
  volcano: {
    name: 'Volcano', sky: ['#3a1020', '#7b2531'], ground: '#3a2b2b', groundDeep: '#1d1414',
    accent: '#ff6a3d', rolling: 1.3, jumpBias: 1.4, whoopBias: 1.0, grip: 0.92, dust: '#8c5a45',
    embers: true, night: true, heat: true
  },
  fantasy: {
    name: 'Fantasy', sky: ['#2b1a4d', '#7a4bb5'], ground: '#4a3a6d', groundDeep: '#2a2044',
    accent: '#a97fff', rolling: 1.6, jumpBias: 1.5, whoopBias: 1.1, grip: 1.1, dust: '#c0a4ff',
    night: true, glow: true
  }
};

export const BIOME_KEYS = Object.keys(BIOMES);

export const AI_PERSONALITIES = [
  { id: 'beginner', name: 'Rookie', skill: 0.55, aggression: 0.3, risk: 0.25, mistake: 0.05 },
  { id: 'safe', name: 'Steady', skill: 0.72, aggression: 0.35, risk: 0.3, mistake: 0.02 },
  { id: 'technical', name: 'Technical', skill: 0.85, aggression: 0.5, risk: 0.45, mistake: 0.012 },
  { id: 'aggressive', name: 'Aggressive', skill: 0.86, aggression: 0.9, risk: 0.75, mistake: 0.028 },
  { id: 'risky', name: 'Sendy', skill: 0.8, aggression: 0.8, risk: 0.95, mistake: 0.045 },
  { id: 'pro', name: 'Pro', skill: 0.96, aggression: 0.7, risk: 0.6, mistake: 0.008 }
];

export const GEAR = {
  helmet: ['Slate', 'Ember', 'Frost', 'Venom', 'Carbon', 'Solar'],
  jersey: ['Classic', 'Fade', 'Stripe', 'Camo', 'Neon', 'Retro'],
  pants: ['Slate', 'Ember', 'Frost', 'Venom', 'Carbon'],
  boots: ['Standard', 'Pro', 'Elite'],
  gloves: ['Grip', 'Vent', 'Pro'],
  goggles: ['Clear', 'Mirror', 'Tint'],
  plastics: ['Stock', 'Gloss', 'Matte', 'Chrome'],
  graphics: ['Blank', 'Bolt', 'Wave', 'Shatter', 'Circuit'],
  plate: ['White', 'Black', 'Yellow', 'Red'],
  wheels: ['Black', 'Silver', 'Gold', 'Anodized'],
  exhaust: ['Stock', 'Slip-on', 'Full System'],
  victory: ['Fist Pump', 'Whip', 'Nac-Nac', 'Stand-up']
};

export const ACHIEVEMENTS = [
  { id: 'first_race', name: 'Gate Drop', desc: 'Finish your first race.' },
  { id: 'first_win', name: 'Holeshot Hero', desc: 'Win a race.' },
  { id: 'perfect5', name: 'Momentum', desc: 'Land 5 perfect landings in one race.' },
  { id: 'whip360', name: 'Bar Dragger', desc: 'Accumulate 360° of whip in one race.' },
  { id: 'no_crash', name: 'Clean Sheet', desc: 'Finish a race without crashing.' },
  { id: 'champ1', name: 'Plate Holder', desc: 'Win a championship.' },
  { id: 'level10', name: 'Privateer', desc: 'Reach level 10.' },
  { id: 'level25', name: 'Factory Rider', desc: 'Reach level 25.' },
  { id: 'garage5', name: 'Collector', desc: 'Own 5 bikes.' },
  { id: 'airtime', name: 'Frequent Flyer', desc: 'Log 60 seconds of air time.' }
];

export const DAILY_POOL = [
  { id: 'd_race3', desc: 'Finish 3 races', goal: 3, stat: 'races', xp: 300, coins: 600 },
  { id: 'd_perfect8', desc: 'Land 8 perfect landings', goal: 8, stat: 'perfects', xp: 350, coins: 700 },
  { id: 'd_air20', desc: 'Log 20s of air time', goal: 20, stat: 'airtime', xp: 300, coins: 550 },
  { id: 'd_win1', desc: 'Win a race', goal: 1, stat: 'wins', xp: 400, coins: 900 },
  { id: 'd_whip720', desc: 'Whip a total of 720°', goal: 720, stat: 'whipdeg', xp: 350, coins: 750 },
  { id: 'd_nocrash', desc: 'Finish a race without crashing', goal: 1, stat: 'cleanraces', xp: 400, coins: 800 }
];

export const WEEKLY_POOL = [
  { id: 'w_race15', desc: 'Finish 15 races', goal: 15, stat: 'races', xp: 1800, coins: 4000 },
  { id: 'w_win5', desc: 'Win 5 races', goal: 5, stat: 'wins', xp: 2400, coins: 6000 },
  { id: 'w_perfect60', desc: 'Land 60 perfect landings', goal: 60, stat: 'perfects', xp: 2000, coins: 4500 },
  { id: 'w_champ', desc: 'Win a championship', goal: 1, stat: 'champs', xp: 3000, coins: 8000 }
];

export const CHAMPIONSHIPS = [
  { id: 'rookie', name: 'Rookie Cup', cls: '50cc', rounds: 3, difficulty: 0.5, reward: 4000,
    biomes: ['motocross', 'forest', 'beach'] },
  { id: 'regional', name: 'Regional Series', cls: '85cc', rounds: 4, difficulty: 0.65, reward: 9000,
    biomes: ['motocross', 'sand', 'mud', 'supercross'] },
  { id: 'national', name: 'National Outdoors', cls: '250cc', rounds: 5, difficulty: 0.8, reward: 22000,
    biomes: ['motocross', 'sand', 'mountain', 'desert', 'mud'] },
  { id: 'arena', name: 'Arena Nights', cls: '250cc', rounds: 5, difficulty: 0.85, reward: 26000,
    biomes: ['supercross', 'supercross', 'night', 'supercross', 'stadium'] },
  { id: 'worlds', name: 'World Championship', cls: '450cc', rounds: 6, difficulty: 0.95, reward: 60000,
    biomes: ['motocross', 'sand', 'supercross', 'snow', 'volcano', 'mountain'] }
];

export const SEASON = {
  id: 's1', name: 'Season 1 — Dust & Thunder', tiers: 30, xpPerTier: 1200,
  rewards: (t) => {
    if (t % 10 === 0) return { type: 'bike', label: 'Bike token' };
    if (t % 5 === 0) return { type: 'cosmetic', label: 'Elite cosmetic' };
    if (t % 2 === 0) return { type: 'coins', label: '1,500 coins', coins: 1500 };
    return { type: 'coins', label: '750 coins', coins: 750 };
  }
};

export const xpForLevel = (lvl) => Math.round(500 * Math.pow(lvl, 1.35));
