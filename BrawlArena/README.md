# Brawl Arena (Android + iOS)

A Brawl Stars-style top-down Showdown brawler: 10 fighters drop into a
destructible arena, last one standing wins. HTML5 canvas game wrapped in an
Android WebView app; the iOS shell in `../BrawlArenaiOS` references the same
`index.html`, so both platforms share one game source.

## Gameplay

- **Showdown**: you + 9 AI brawlers, shrinking poison zone, last alive wins
- **3 brawlers**, each with a chargeable **SUPER** (deal damage to fill it):
  - **BUCK** — shotgun burst; SUPER: leap and blast on landing
  - **VERA** — long-range sniper; SUPER: piercing railgun bolt
  - **DYNO** — lobbed bombs; SUPER: rocket rain on an area
- Smash **loot boxes** for power cubes: +400 max HP and +8% damage each
- **Bushes** hide you until you shoot or an enemy gets close
- Trophies for placement, stored on-device (win +10 … last places lose some)

## Controls

Left half = move stick • right half drag = aim, release = fire •
quick tap = auto-shot at nearest enemy • yellow button = SUPER.
Desktop testing: WASD + mouse click, Space = super.

## Multiplayer note

Opponents are AI bots (a server is required for true online play — the
game loop is structured so a networked mode can be added later).

## Builds

CI attaches `BrawlArena.apk` (installable debug build) and
`BrawlArena-unsigned.ipa` (sign with KSign/Sideloadly) to the repo's
**latest** GitHub Release on every push touching these projects.
