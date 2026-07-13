# Brawl Arena 3D (Android + iOS)

A Brawl Stars-style 3D Showdown brawler (Three.js, angled top-down camera)
wrapped in an Android WebView app; the iOS shell in `../BrawlArenaiOS`
references the same `index.html`, so both platforms share one game source.
Two modes: **Bots Showdown** (offline, 10-player last-one-standing) and
**Online Arena** (real players over Supabase Realtime).

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

## Online multiplayer (Supabase)

Online Arena is a drop-in deathmatch against real players: everyone shares
one arena over a Supabase Realtime channel, respawn on death, +2 trophies
per KO. No dedicated game server needed — clients broadcast their state at
10 Hz and each client is authoritative over its own HP.

To enable it:
1. Create a free project at https://supabase.com
2. Project Settings → API → copy the **Project URL** and **anon public** key
3. Paste them into `SUPABASE_URL` / `SUPABASE_ANON_KEY` at the top of the
   `<script>` block in `app/src/main/assets/index.html`
4. Push — CI rebuilds both apps; everyone on the same build now shares
   the arena

Until keys are configured, the Online button explains what's missing and
Bots Showdown works fully offline.

## Builds

CI attaches `BrawlArena.apk` (installable debug build) and
`BrawlArena-unsigned.ipa` (sign with KSign/Sideloadly) to the repo's
**latest** GitHub Release on every push touching these projects.
