#!/usr/bin/env bash
# Checks use synthetic fixtures only; no game executable or assets required.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT="$ROOT/build/linux-checks"
mkdir -p "$OUT"
python3 recomp/tools/compiler_compat.py clang "$OUT/compiler-flags.txt"
read -ra COMPAT_FLAGS < "$OUT/compiler-flags.txt"
CC=(clang "${COMPAT_FLAGS[@]}")
read -ra CF <<< "$(pkg-config --cflags sdl2 freetype2 fontconfig sndfile glew libpng)"
read -ra GL <<< "$(pkg-config --libs sdl2 glew libpng)"
for f in recomp/runtime/rt.c recomp/runtime/win32/*.c recomp/host/linux.c src/renderer/linux/renderer.c; do
    "${CC[@]}" -fsyntax-only -D_GNU_SOURCE -I recomp/runtime -I recomp/third_party/mojoshader -I recomp/third_party/minimp3 "${CF[@]}" "$f"
    "${CC[@]}" -fsyntax-only -D_GNU_SOURCE -DFF_EDITION -I recomp/runtime -I recomp/third_party/mojoshader -I recomp/third_party/minimp3 "${CF[@]}" "$f"
done
"${CC[@]}" -O1 -g -D_GNU_SOURCE -ffunction-sections -fdata-sections -Wl,--gc-sections -I recomp/runtime \
    -o "$OUT/winsock" recomp/tests/winsock_linux_test.c -pthread
"$OUT/winsock"
"${CC[@]}" -O1 -g -D_GNU_SOURCE -ffunction-sections -fdata-sections -Wl,--gc-sections -I recomp/runtime \
    -o "$OUT/interlocked" recomp/tests/interlocked_test.c -pthread
"$OUT/interlocked"
"${CC[@]}" -O1 -g -D_GNU_SOURCE -ffunction-sections -fdata-sections -Wl,--gc-sections -I recomp/runtime \
    -o "$OUT/window_geometry" recomp/tests/window_geometry_test.c -pthread -lm
"$OUT/window_geometry"
"${CC[@]}" -O1 -g -D_GNU_SOURCE -ffunction-sections -fdata-sections -Wl,--gc-sections -I recomp/runtime -I recomp/runtime/win32 \
    -o "$OUT/ff_imports" recomp/tests/ff_imports_test.c -lm
"$OUT/ff_imports"
"${CC[@]}" -O1 -g -D_GNU_SOURCE -I recomp/runtime -I recomp/runtime/win32 -o "$OUT/resources" recomp/tests/resources_test.c -lm
"$OUT/resources"
"${CC[@]}" -O1 -g -D_GNU_SOURCE -I recomp/runtime -I recomp/runtime/win32 -o "$OUT/dp8" \
    recomp/tests/dp8test.c recomp/runtime/win32/dp8proto.c -pthread
"$OUT/dp8"
# Direct3D 8 (d3d8.c) through the whole runtime built as Freedom Force's (FF_EDITION), methods called through the guest
# vtables and import thunks
D8="$OUT/d3d8"; mkdir -p "$D8"
python3 recomp/tools/gen_imptab.py "$D8/imptab.c" recomp/runtime/win32/*.c > /dev/null
MOJO=(-DSUPPORT_PROFILE_D3D=0 -DSUPPORT_PROFILE_BYTECODE=0 -DSUPPORT_PROFILE_HLSL=0 -DSUPPORT_PROFILE_ARB1=0 -DSUPPORT_PROFILE_ARB1_NV=0
      -DSUPPORT_PROFILE_SPIRV=0 -DSUPPORT_PROFILE_GLSPIRV=0 -DSUPPORT_PROFILE_GLSLES=0 -DSUPPORT_PROFILE_GLSLES3=0 -DSUPPORT_PROFILE_METAL=0
      -DMOJOSHADER_FLIP_RENDERTARGET -DMOJOSHADER_DEPTH_CLIPPING -I recomp/third_party/mojoshader)
for f in recomp/third_party/mojoshader/mojoshader.c recomp/third_party/mojoshader/mojoshader_common.c recomp/third_party/mojoshader/profiles/*.c; do
    "${CC[@]}" -c -O1 -w "${MOJO[@]}" -o "$D8/mojo_$(basename "$f" .c).o" "$f"
done
for f in recomp/runtime/rt.c recomp/runtime/win32/*.c "$D8/imptab.c"; do
    "${CC[@]}" -c -O1 -g -D_GNU_SOURCE -DFF_EDITION -w -I recomp/runtime -I recomp/runtime/win32 -I recomp/third_party/mojoshader \
        -I recomp/third_party/minimp3 "${CF[@]}" -o "$D8/$(basename "$f" .c).o" "$f"
done
read -ra RTLIBS <<< "$(pkg-config --libs sdl2 glew libpng sndfile freetype2 fontconfig)"
"${CC[@]}" -O1 -g -D_GNU_SOURCE -DFF_EDITION -Wall -Wno-unused-function -I recomp/runtime -I recomp/runtime/win32 -o "$OUT/d3d8_test" \
    recomp/tests/d3d8_test.c "$D8"/*.o "${RTLIBS[@]}" -pthread -ldl -lm -lz
"$OUT/d3d8_test"
"${CC[@]}" -O1 -g "${CF[@]}" -o "$OUT/renderer" recomp/tests/renderer_test.c src/renderer/linux/renderer.c "${GL[@]}" -lm
"$OUT/renderer" src/renderer/linux
for test in frame_pacer display_modes; do
    "${CC[@]}" -O1 -g -o "$OUT/$test" "recomp/tests/${test}_test.c" -lm
    "$OUT/$test"
done
python3 -m py_compile recomp/tools/*.py recomp/host/test_lab/*.py
python3 recomp/tests/edition_test.py
"${CC[@]}" -O1 -g -D_GNU_SOURCE -DDS2_BROKEN_WORLD -I recomp/runtime \
    -o "$OUT/guest-flow" recomp/tests/guest_flow_test.c recomp/runtime/rt.c -lm -pthread
"$OUT/guest-flow"

if [[ -x recomp/.venv/bin/python ]]; then
    recomp/.venv/bin/python recomp/tests/lift_flow_test.py
    recomp/.venv/bin/python recomp/tests/jumptable_test.py
fi
