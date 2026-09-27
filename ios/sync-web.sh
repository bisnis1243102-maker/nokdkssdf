#!/usr/bin/env bash
# Copies the HTML5 games from the repo root into the iOS app bundles' www folders.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf Web
mkdir -p Web/PlanetHopper/www Web/BeatBattle/www Web/RetroHopper/www Web/StarHopper64/www
cp ../index.html ../three.min.js Web/PlanetHopper/www/
cp ../beatbattle/index.html Web/BeatBattle/www/
cp ../retro/index.html Web/RetroHopper/www/
cp ../star64/index.html ../star64/three.min.js Web/StarHopper64/www/
echo "Synced web games into ios/Web"
