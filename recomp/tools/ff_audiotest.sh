#!/bin/bash
# ff_audiotest.sh [game folder] : is the sound the port plays what the game's files hold? Test mode, muted (the mix is
# recorded with W32_AUDIO_DUMP, which taps it before the mute), scratch data. Two checks:
#   menu music: the main menu's track, Sounds/musak/m00.mp3, decoded by macOS (afconvert) and correlated with the
#     recording (tools/ff_audiocorr.c); right rate and no gaps give 1.0 to four places
#   speech: the Danger Room's first mission; the voice lines the game asks for (W32_DIRLOG shows its loose-file checks)
#     are each found in the recording, mixed with the music
# The recordings and decodes stay in recomp/work/audio (they are the game's sound).
set -uo pipefail
cd "$(dirname "$0")/.."
GAME="${1:-$HOME/Games/FreedomForce}"; A=$PWD/work/audio; mkdir -p "$A/ref"
clang -O2 -framework Accelerate tools/ff_audiocorr.c -o work/ff_audiocorr || exit 1
decode() {   # decode <path in sounds.ff, / separated> <out.wav>
  python3 -I - "$GAME" "$1" "$2" <<'EOF'
import os, subprocess, sys, zipfile, tempfile
game, inner, out = sys.argv[1:]
z = zipfile.ZipFile(os.path.join(game, 'Data', 'sounds.ff')); names = {n.lower(): n for n in z.namelist()}
with tempfile.NamedTemporaryFile(suffix='.mp3') as t:
    t.write(z.read(names[inner.replace('/', '\\').lower()])); t.flush()
    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@44100', '-c', '2', t.name, out], check=True)
EOF
}
fail=0
echo "== menu music"
decode Sounds/musak/m00.mp3 "$A/ref/m00.wav"
W32_AUDIO_DUMP="$A/menu.wav" SECS=40 GAME="$GAME" TAIL=0 tools/ff_iterate.sh run > /dev/null
work/ff_audiocorr "$A/menu.wav" "$A/ref/m00.wav" || fail=1
echo "== speech in the first mission"
W32_DIRLOG=1 W32_AUDIO_DUMP="$A/mission1.wav" DS_SCRIPT="@20:dimove:-170,0;@25:diclick:0,0;@32:dimove:-32,-100;@35:diclick:0,0;@40:dimove:394,316;@45:diclick:0,0;@55:diclick:0,0" \
  SECS=100 GAME="$GAME" TAIL=0 tools/ff_iterate.sh run > "$A/mission1.out"
LOG=$(awk '/^run rc=/ {print $4}' "$A/mission1.out")
lines=$(grep -o 'speech.english.[A-Za-z0-9_]*\.mp3' "$LOG" | sort -u | sed 's/.*english.//')
[ -n "$lines" ] || { echo "no voice line was asked for"; fail=1; }
refs=(); for l in $lines; do decode "Sounds/speech/english/$l" "$A/ref/${l%.mp3}.wav"; refs+=("$A/ref/${l%.mp3}.wav"); done
if [ ${#refs[@]} -gt 0 ]; then
  out=$(work/ff_audiocorr --find "$A/mission1.wav" "${refs[@]}"); echo "$out"
  echo "$out" | grep -q "^${#refs[@]} of ${#refs[@]} found" || fail=1
fi
[ $fail = 0 ] && echo "audio: music and speech play as the game's files hold them" || echo "audio: FAILED"
exit $fail
