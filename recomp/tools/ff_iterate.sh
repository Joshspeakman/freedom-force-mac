#!/bin/bash
# ff_iterate.sh [build|relink|run] : rebuild (everything, or FF_RELINK for runtime-only changes; "run" skips it) and run
# a short test session of Freedom Force; prints the end of the log.
#   GAME   the game folder (default: this repository's game/, which has the binaries but no data: the run stops where the
#          game first needs its files). A GOG installation folder is only read.
#   SECS   how long the session runs (default 60); the game is killed after that.
#   DATA   the data folder (default: a new scratch folder under recomp/work/, never the player's own).
#   DS_RESOLUTION  WxH, written into the scratch copy of options.dat (host/main.m); unset, the game's own (640x480).
# Test mode only: DS_TEST=1 (an ordinary background window, no mouse capture, no launch window), muted audio.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; cd "$HERE"
GAME="${GAME:-$HERE/../game}"; SECS="${SECS:-60}"; N=$(date +%H%M%S)
DATA="${DATA:-$HERE/work/scratch-$N}"; mkdir -p "$DATA"
case "${1:-build}" in
  relink) FF_RELINK=1 ./build_ff.sh "$GAME" > work/build.log 2>&1 || { echo "build failed: work/build.log"; grep -E "error|undefined" work/build.log | head -20; exit 1; } ;;
  build) ./build_ff.sh "$GAME" > work/build.log 2>&1 || { echo "build failed: work/build.log"; grep -E "error|undefined" work/build.log | head -20; exit 1; } ;;
  run) ;;
  *) echo "usage: ff_iterate.sh [build|relink|run]"; exit 2 ;;
esac
APP=work/ff/app/FreedomForceLinux; [[ $(uname -s) == Darwin ]] && APP=work/ff/app/FreedomForceNative
[[ -x "$APP" ]] || { echo "no $APP: build first (on the Mac, also tools/build_app.sh work/ff)"; exit 1; }
RUN=(); [[ $(uname -s) == Linux && -z "${DISPLAY:-}" ]] && RUN=(xvfb-run -a -s "-screen 0 1280x1024x24")
DS_TEST=1 W32_AUDIO_MUTE=1 DS_EXIT_AFTER=$SECS timeout -k 10 $((SECS + 15)) \
  ${RUN[@]+"${RUN[@]}"} "$APP" --exe work/ff/fforce.exe --game "$GAME" --data "$DATA" > "work/run-$N.log" 2>&1 < /dev/null
echo "run rc=$? log work/run-$N.log data $DATA"
tail -"${TAIL:-30}" "work/run-$N.log" | cut -c1-300
