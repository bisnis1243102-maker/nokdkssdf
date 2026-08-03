# ArtForge

A generative image generator for iOS. Everything runs on device — no API, no
network, no key. Type a prompt, pick an engine, and the app synthesises a
1600×1600 original from scratch.

## How it works

Every image is a pure function of `(prompt, style, seed)`. The prompt is folded
into a 64-bit hash that seeds a SplitMix64 generator; that generator drives the
palette, every parameter, and every stroke. The same three inputs always give
back the identical image, which is what makes the gallery cheap — only recipes
are stored on disk, and images are re-rendered on demand.

## The six engines

| Engine | Technique |
| --- | --- |
| **Flow** | Thousands of particles advected through a turbulent fBm field, leaving translucent trails |
| **Nebula** | Per-pixel domain-warped noise, optionally mixed with a ridged variant |
| **Shards** | Recursive rectangle subdivision, coloured from a shared noise field so neighbours relate |
| **Strata** | Stacked ridge lines that clip each other, producing occlusion and depth |
| **Fractal** | Julia set with smooth (continuous) escape-time colouring — no banding |
| **Bloom** | Circle packing by dart throwing, with a spatial grid for collision lookups |

Colour is never picked from a fixed list. A harmony rule (analogous,
complementary, triadic, split-complement, or monochrome) generates a hue set,
then saturation and brightness curves turn it into a ramp that renderers sample
continuously. A shared finishing pass — gradient backdrop, vignette, and film
grain — gives six unrelated algorithms one consistent look.

## Using it

- **Generate** — new seed, same prompt and style
- **Variation** — nudges the seed for a closely related piece (tapping the canvas does the same)
- **Surprise** — random engine and seed
- **Keep** — adds the piece to your gallery; tap any thumbnail to bring it back
- **Save / Share** — writes the full-resolution PNG to Photos or hands it to the share sheet

## Building

Open `ArtForge.xcodeproj` in Xcode and run, or grab the unsigned `.ipa` from the
repo's `latest` release and sign it on device. Requires iOS 16 or newer.
