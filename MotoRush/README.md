# MotoRush

An original 2.5D physics motocross game. Zero dependencies, zero downloaded
assets — every bike, track, particle and sound is generated at runtime from
code. Runs in any modern browser on desktop, phone or tablet.

## Run it

```bash
cd MotoRush
python3 -m http.server 8080
# open http://localhost:8080
```

It must be served over HTTP (ES modules do not load from `file://`).

## Controls

| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Throttle | ↑ / W / Space | RT or A | THROTTLE |
| Brake | ↓ / S | LT or B | BRAKE |
| Lean back / forward | ← / → | Left stick Y | LEAN BACK / LEAN FWD |
| Whip left / right | A / D | Right stick X | WHIP L / WHIP R |
| Reset | R | — | — |
| Pause | Esc | — | ❚❚ |

Touch controls appear automatically on coarse-pointer devices. Every key is
rebindable in Settings.

**The skill loop:** lean back to loft the front over a face, lean forward to
bring the nose down, and match the bike's angle to the slope you are about to
land on. Landing square carries your speed and gives a momentum bonus; landing
flat on a downslope or crossed-up scrubs drive; landing badly enough crashes
you. Whipping is free style points *if* you straighten before touchdown.

## What is in the box

- **Physics** — rigid chassis with two raycast suspension units, asymmetric
  spring/damper curves, bottom-out stops, a friction circle per tyre, engine
  torque curves with wheelspin, rider weight transfer (the actual cause of
  wheelies, stoppies and nose-dive), air control, whip/scrub, landing-quality
  scoring, verlet ragdoll crashes, and rut deformation on heavy landings.
- **Tracks** — seeded procedural generator producing tabletops, doubles,
  triples, step-ups/downs, whoops, rollers, rhythm sections, berms and rolling
  terrain, weighted by biome and difficulty. 12 biomes (motocross, supercross,
  sand, mud, forest, snow, desert, night, mountain, beach, volcano, fantasy)
  and a 240-track deterministic catalogue.
- **AI** — six personalities running the *same* physics and the same input
  struct as the player, with ballistic landing prediction, feature-risk
  assessment, reaction delay scaled by skill, and genuine mistakes. Plus an
  adaptive-difficulty tracker that keeps races close between sessions.
- **Progression** — XP and levels, coins, nine bikes across eight classes, six
  upgrade lines per bike, twelve cosmetic slots, daily/weekly missions,
  achievements, five championships, ranked points with tiers, a 30-tier season
  pass, and daily login streaks. All persisted to `localStorage` in a
  server-shaped document.
- **Presentation** — parallax skies, stadium rigs, weather (rain, snow,
  embers, heat shimmer), dust and roost particles, dynamic camera with speed
  zoom and impact shake, slow-motion on crashes and finishes, procedural
  engine/wind/crowd/landing audio and a dynamic music layer that follows race
  intensity.
- **Accessibility** — colorblind tint modes, screen-shake scaling, landing and
  throttle assists (neither adds grip — they only smooth your own input), full
  key rebinding, reduced-motion support.

Holds 60 FPS in headless Chromium at 900×520 with a six-bike field; the
renderer drops particle counts, DPR and texture passes on the `low` quality
setting.

## What is designed but not implemented

Being explicit rather than implying more than ships here:

- **Real-time multiplayer** is not networked. Ranked and quick races run
  against the local AI field; the ghost system, deterministic seeded tracks and
  the 10 Hz replay buffer are the pieces a rollback/lockstep netcode layer
  would need, but there is no server, matchmaking, lobby, spectator mode or
  anti-cheat in this build. The leaderboard on the Ranked screen is generated
  locally around your own rating.
- **Replay viewer** — full-field poses are captured every 100 ms during a race
  (`Race.replay`), but there is no playback UI or cinematic replay camera yet.
- **Monetization** — the season pass, daily rewards and shop economy are
  wired to the in-game coin currency only. There is no store, no real-money
  path and nothing purchasable that affects performance.
- Races are single-lap point-to-point sprints; multi-lap circuits are not
  implemented.

## Layout

```
index.html      screens, HUD, touch controls
style.css       UI
js/data.js      bikes, biomes, missions, cosmetics, championships, season
js/track.js     procedural track generator + track catalogue
js/physics.js   bike simulation (suspension, tyres, weight transfer, crashes)
js/ai.js        racing AI personalities + adaptive difficulty
js/render.js    camera, particles, canvas renderer
js/audio.js     Web Audio synthesis (engine, ambience, SFX, music)
js/input.js     keyboard / gamepad / touch → four analogue channels
js/save.js      profile, economy, missions, records, ghosts
js/game.js      race session: field, scoring, effects, results
js/main.js      app shell, menus, HUD, frame loop
```

## Tuning notes

Physics constants live at the top of `js/physics.js` and in the bike specs in
`js/data.js`. Units are metres, kilograms and seconds throughout. The values
that matter most for feel:

- `susStiff` / `susDamp` / `travel` — ride height and how much a landing
  upsets the chassis.
- `power` + `torqueCurve` — thrust is `power × (1 − v/topSpeed)^(1/torqueCurve)`,
  so top speed is limited by gearing rather than grip.
- The friction circle caps tyre load at 1.6 × static weight, which is what
  keeps a suspension spike from handing you several g of braking for a frame.
- `onLanding()` owns the entire risk/reward loop: quality thresholds, momentum
  multipliers and the crash rule.

No third-party assets, track layouts, branding or code are used anywhere in
this project.
