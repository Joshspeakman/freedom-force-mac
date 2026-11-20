#!/bin/bash
# build_ff.sh [game folder] [outdir]
# Recompile Freedom Force (GOG 1.3, build 19478) into C: fforce.exe, and the DLLs below lifted into the same image set.
# The game folder defaults to this repository's game/; a GOG installation folder works too. It is only read.
# Everything generated stays local (work/ is git-ignored).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/tools/trash.sh"
GAME="${1:-$HERE/../game}"; OUT="${2:-$HERE/work/ff}"
GAME="$(cd "$GAME" && pwd)"
# Every binary lifted is checked against game/MANIFEST.txt (GOG 1.3, build 19478). Lifted besides the executable:
#   - the game's own DLLs: Standard.dll, Sound.dll, python15.dll (required);
#   - the C runtime, zlib and Miles the game ships, when the game folder has them: MSVCRT.dll, MSVCP60.dll (the game's
#     C and C++ runtime, C++ exceptions included), zlib-1.1.3.dll, Mss32.dll with its software 3D provider and MP3
#     decoder. Without them a build still links, but the game stops at its first call into the C runtime.
# A DLL whose preferred base is taken (Standard.dll and Sound.dll both want 0x10000000) is lifted from a relocated copy
# (tools/image_bases.py picks the base, tools/rebase_pe.py makes the copy); loader.c relocates the original the same way
# at run time.
REQUIRED=(Standard.dll Sound.dll python15.dll)
OPTIONAL=(MSVCRT.dll MSVCP60.dll zlib-1.1.3.dll Mss32.dll System/Miles/Mssfast.m3d System/Miles/Mp3dec.asi)
MANIFEST="$HERE/../game/MANIFEST.txt"
sha() { if command -v shasum >/dev/null; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1; }
want() { awk -v p="$1" '!/^#/ && $3 == p { print $1 }' "$MANIFEST"; }
echo "== checking $GAME"
DLLS=(); MISSING=()
for rel in fforce.exe "${REQUIRED[@]}" "${OPTIONAL[@]}"; do
  if [ ! -f "$GAME/$rel" ]; then
    [[ " ${OPTIONAL[*]} " == *" $rel "* ]] || { echo "no $rel in $GAME"; exit 1; }
    MISSING+=("$rel"); continue
  fi
  if [ "$(sha "$GAME/$rel")" != "$(want "$rel")" ]; then
    [ -n "${FF_ANY_BUILD:-}" ] || { echo "$rel is not GOG 1.3's (build 19478); FF_ANY_BUILD=1 tries anyway"; exit 1; }
    echo "$rel differs from GOG 1.3's (FF_ANY_BUILD)"
  fi
  [ "$rel" = fforce.exe ] || DLLS+=("$rel")
done
[ ${#MISSING[@]} -eq 0 ] || echo "not in the game folder, so not lifted: ${MISSING[*]} (the game stops at its first call into them)"
PY="$HERE/.venv/bin/python"
export PYTHONHASHSEED=0                                     # the same C from the same input (incremental compiles)
[ -x "$PY" ] || { python3 -m venv "$HERE/.venv" && "$HERE/.venv/bin/pip" install -q capstone==5.0.7 unicorn==2.1.4; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
python3 "$HERE/tools/compiler_compat.py" "${CC:-clang}" "$OUT/compiler-flags.txt.new"
# arm64: x86's memory ordering for the game's threads (runtime/rt.h RT_TSO); x86-64 has it natively
if [[ "$(uname -m)" == arm64 ]]; then printf '%s -DRT_TSO\n' "$(head -1 "$OUT/compiler-flags.txt.new")" > "$OUT/compiler-flags.txt.tmp" && mv "$OUT/compiler-flags.txt.tmp" "$OUT/compiler-flags.txt.new"; fi
cmp -s "$OUT/compiler-flags.txt.new" "$OUT/compiler-flags.txt" && trash_paths "$OUT/compiler-flags.txt.new" || mv "$OUT/compiler-flags.txt.new" "$OUT/compiler-flags.txt"   # changed flags: recompile all
cp "$GAME/fforce.exe" "$OUT/fforce.exe"                   # also tells build_runtime.sh the edition (FF_EDITION)
EXE="$OUT/fforce.exe"
if [[ -n "${FF_RELINK:-}" && -d "$OUT/obj" ]]; then       # runtime changes only: keep the lifted objects
  echo "== runtime and link (FF_RELINK)"; exec "$HERE/tools/build_runtime.sh" "$OUT"
fi
echo "== analysis"
if [[ -n "${FF_REANALYZE:-}" || ! -f "$OUT/analysis.json" || "$OUT/analysis.json" -ot "$HERE/tools/analyze.py" ]]; then
  "$PY" "$HERE/tools/analyze.py" "$EXE" "$OUT/analysis.json" > "$OUT/analysis.log"
else echo "(kept: same analyze.py; FF_REANALYZE=1 redoes it)"; fi
sed -n '/^functions /p; /^decode failures:/p; /^jump tables /p; /^SEH:/p' "$OUT/analysis.log"
echo "== lifting"
# keep the previous C to recompile only the files whose text changed
trash_paths "$OUT/prev"; mkdir -p "$OUT/prev"; for g in "$OUT"/lift_*.c "$OUT"/*_lift_*.c "$OUT/fntab.c"; do [ -f "$g" ] && mv "$g" "$OUT/prev/"; done
"$PY" "$HERE/tools/lift.py" "$EXE" "$OUT/analysis.json" "$OUT" --game ff | grep -Ev '^unsupported: \{\}$'
# the game's own DLLs, recompiled into the same image set (as the Dungeon Siege II build does for Miles and Bink)
NIMP=$("$PY" -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["imports"]))' "$OUT/image.json")
IMGS=("=")
for spec in $("$PY" "$HERE/tools/image_bases.py" "$GAME" fforce.exe "${DLLS[@]}"); do
  rel=${spec%@*}; tag=$(basename "$rel" | tr . - | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' _); src="$GAME/$rel"
  if [[ $spec == *@* ]]; then mkdir -p "$OUT/rebased"; "$PY" "$HERE/tools/rebase_pe.py" "$src" "$OUT/rebased/$(basename "$rel")" "${spec#*@}"; src="$OUT/rebased/$(basename "$rel")"; fi
  "$PY" "$HERE/tools/analyze.py" "$src" "$OUT/$tag.json" > "$OUT/$tag.log"; head -1 "$OUT/$tag.log"
  "$PY" "$HERE/tools/lift.py" "$src" "$OUT/$tag.json" "$OUT" --tag "$tag" --imp-base "$NIMP" | grep -E 'lifted|internal'
  NIMP=$((NIMP + $("$PY" -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["imports"]))' "$OUT/${tag}_image.json")))
  IMGS+=("$tag=$rel")
done
"$PY" "$HERE/tools/link_tables.py" "$OUT" "${IMGS[@]}"
echo "== compiling"
mkdir -p "$OUT/obj"; [[ "$OUT/compiler-flags.txt" -nt "$OUT/obj" ]] && trash_paths "$OUT"/obj/*.o
TODO=()
for g in "$OUT"/lift_*.c "$OUT"/*_lift_*.c "$OUT/fntab.c"; do
  o="$OUT/obj/$(basename "$g" .c).o"
  if [[ -f "$o" ]] && cmp -s "$g" "$OUT/prev/$(basename "$g")" && [[ "$o" -nt "$HERE/runtime/rt.h" && "$o" -nt "$HERE/runtime/rt_sse.h" ]]; then continue; fi
  trash_paths "$o"; TODO+=("$g")
done
for o in "$OUT"/obj/*.o; do [[ -f "$OUT/$(basename "$o" .o).c" ]] || trash_paths "$o"; done    # files the lift no longer makes
trash_paths "$OUT/prev"; touch "$OUT/obj"
echo "${#TODO[@]} of $(ls "$OUT"/lift_*.c "$OUT"/*_lift_*.c "$OUT/fntab.c" | wc -l | tr -d ' ') files changed"
JOBS="${FF_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN)}"
[[ ${#TODO[@]} -eq 0 ]] || printf '%s\0' "${TODO[@]}" | xargs -0 -n 1 -P "$JOBS" "$HERE/tools/cc1.sh" "$OUT"
echo "== $(ls "$OUT/obj" | wc -l | tr -d ' ') object files; runtime and link"
"$HERE/tools/build_runtime.sh" "$OUT"
