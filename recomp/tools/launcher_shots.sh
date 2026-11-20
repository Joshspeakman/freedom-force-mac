#!/bin/bash
# launcher_shots.sh [game folder] : the launch window as images in recomp/work/launcher/ (closed, each group open, the
# GOG banner, hover/focus), with the art composed from the game as install.sh does (recomp/work/art). Build first
# (tools/build_app.sh work/ff). The images show the game's art: keep them local.
set -euo pipefail
cd "$(dirname "$0")/.."
GAME="${1:-$HOME/Games/FreedomForce}"; OUT=work/launcher; D=$OUT/data; mkdir -p "$D"
if [ ! -f work/art/heroes.png ]; then
  python3 -I tools/ff_art.py "$GAME" work/art-src && clang -fobjc-arc -framework AppKit tools/ff_art.m -o work/ff_art && work/ff_art work/art-src work/art
fi
[ -L "$D/art" ] || ln -s ../../art "$D/art"
shot() { local n=$1; shift; env "$@" DS_LAUNCHER_SHOT="$PWD/$OUT/$n.png" DS_UPDATE_BRANCH=nightly W32_AUDIO_MUTE=1 \
  work/ff/app/FreedomForceNative --exe work/ff/fforce.exe --game "$GAME" --data "$D" 2>&1 | grep -q saved && echo "$OUT/$n.png"; }
shot closed; shot keyart FF_BANNER=keyart; shot display DS_LAUNCHER_OPEN=display; shot guide DS_LAUNCHER_OPEN="key guide"
shot files DS_LAUNCHER_OPEN=files; shot hover DS_LAUNCHER_FOCUS=3 DS_LAUNCHER_HOVER=100
