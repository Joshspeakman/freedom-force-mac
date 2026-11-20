# Recompiler and runtime: Freedom Force as native code

Static recompilation of the user's own GOG copy of *Freedom Force* (GOG 1.3, build 19478: `fforce.exe`, and the game's
own `Standard.dll`, `Sound.dll` and `python15.dll`) into C, compiled for Apple Silicon (Metal) or Linux x86-64
(SDL/OpenGL, for development). Nothing derived from the game is committed: the scripts regenerate everything under
`recomp/work/` (git-ignored). The plan and its phases: [docs/PLAN.md](../docs/PLAN.md).

This tree was imported from `sims-2-macos` (`nightly`, commit `db1a5fb`) in plan phase 0, which inherited it from the
author's Dungeon Siege II and Fallout: New Vegas ports. The Sims 2's own parts were removed, as were the files that
belong only to those other games (their build scripts, tools, saves and tests, Broken World's tools, the Linux player
launcher). Shared files keep the other games' `#ifdef` branches (`FNV_EDITION`, `DS2_BROKEN_WORLD`, and Dungeon Siege
II as the default), so that fixes made upstream still apply with few conflicts; they compile out under `FF_EDITION`.
File names stay as upstream: `sims2_imports.c`, `ds2_imports.c` and `fnv_imports.c` are mostly game-independent
Windows functions that each port needed in turn. (`tests/ff_shader_fixture.c` is about fixed-function shaders, not
Freedom Force.)

## Building

```sh
recomp/build_ff.sh                                   # reads ../game (this repository's), writes recomp/work/ff
recomp/build_ff.sh "/path/to/Freedom Force"          # or a GOG installation folder
recomp/tools/build_app.sh recomp/work/ff             # Mac: host, Metal renderer, launch window -> app/FreedomForceNative
```

`build_ff.sh` checks the SHA-256 of every binary it lifts against `game/MANIFEST.txt` (`FF_ANY_BUILD=1` skips this,
unsupported), then:

| Step | Tool | Notes |
|---|---|---|
| Analysis | `tools/analyze.py` | Reused when `analysis.json` is at least as new as `analyze.py`; `FF_REANALYZE=1` redoes it. |
| Lifting | `tools/lift.py --game ff` | one C function per original function; no Dungeon Siege hooks or overrides |
| DLLs | the same tools | `Standard.dll`, `Sound.dll` and `python15.dll`, and (when the game folder has them) `MSVCRT.dll`, `MSVCP60.dll`, `zlib-1.1.3.dll`, `Mss32.dll` with Miles' `Mssfast.m3d` and `Mp3dec.asi`, lifted into the same image set (`tools/link_tables.py`). A DLL whose base is taken is lifted from a relocated copy (`tools/image_bases.py` picks a free 16 MB slot: `Sound.dll` goes to `0x11000000`; `tools/rebase_pe.py`); `loader.c` relocates the original the same way at run time. Why the C runtime is lifted: [docs/IMPORTS.md](../docs/IMPORTS.md). |
| Compiling | `tools/cc1.sh` | only files whose C changed are recompiled (`FF_BUILD_JOBS=n` sets the parallel jobs) |
| Runtime | `tools/build_runtime.sh` | the Windows runtime with `-DFF_EDITION` (chosen because `fforce.exe` is in the build folder; on Linux also the host and the link); `FF_RELINK=1 build_ff.sh` redoes only this |

## What's where

- `build_ff.sh`: the build above.
- `tools/`: the recompiler (`analyze.py`, `lift.py`, `sse.py`, `link_tables.py`, `pe.py`, `survey.py`), the editions
  (`editions.py`: the executables each build accepts), `steamstub.py` (for the Steam copy later), and the app helpers
  (`build_app.sh`, `extract_icon.py`, `nightly_icon.m`).
- `runtime/rt.c`, `rt.h`, `rt_sse.h`: the execution model below. `runtime/edition.h`: the per-game profile
  (`FF_EDITION`: the executable's name, image end, the app's name).
- `runtime/win32/`: the Windows APIs: loader, memory, heaps, threads, SEH, files (copy-on-write into the data folder),
  registry, USER32 (with the Windows cursor drawn over the frame), GDI, Direct3D 9 (`d3d9*.c`, fixed-function stages,
  CPU vertex processing), DirectDraw/Direct3D 7 (`ddraw.c`), DirectSound, DirectInput, Miles, DirectPlay 8 (`dpnet.c`,
  `dp8proto.c`), Winsock. Direct3D 8 (`d3d8.c`): Direct3D 8's vtables over the Direct3D 9 objects, with adapters
  where the two versions differ (`D3D8_LOG=1` logs them; `D3D8_SHADERS=1` reports vertex and pixel shader support,
  off by default so that the engine takes its fixed-function paths).
- `host/main.m`: the Mac host; `host/ff_launcher.m`: Freedom Force's launch window (`tools/build_app.sh` picks it for
  `FF_EDITION`). `host/launcher.m` is the other ports' launch window, kept for merges (only syntax-checked here, by
  `tests/check_macos.sh`). `../src/renderer`: the Metal renderer. `host/linux.c`: the Linux host.
- `third_party/`: MojoShader and minimp3.

## Execution model

- **Memory:** one 4 GB host region; guest address = offset. Each image sits at its preferred base (`fforce.exe` at
  `0x400000`), so the pointers the game stores keep their 32-bit values.
- **Functions:** one C function per original function. Registers are C locals, written back to a per-thread context
  around calls. The guest stack is real, so calling conventions, `this` pointers and stack-walking code behave as
  before.
- **Flags:** lazy: flag-setting instructions record their operands; consumers compute only the flags they need.
- **x87:** eight doubles with TOP and the control/status words; transcendentals use the host math library.
- **Memory ordering:** on arm64 every guest access keeps x86's ordering (`RT_TSO`: acquire loads, release stores).
- **Indirect calls and jumps:** an address to function table; jump tables become `switch` statements; imports go
  through `rt_import`.
- **Exceptions:** SEH through the game's own handlers; C++ `catch` blocks resume at their continuations.
- **CPU:** `cpuid` reports an SSE2-only Intel CPU, so the executable's 3DNow!, SSE4 and AVX paths are never taken.
  Instructions the lifter doesn't support become traps that name their address.

## Testing

- `bash recomp/tests/check_macos.sh`: CPU, failure-injection, host and synthetic Metal pixel tests on a Mac. No game
  files needed.
- `recomp/tests/check_linux.sh`: the Linux equivalent (needs `clang` and the SDL2, FreeType, fontconfig, libsndfile,
  GLEW and libpng development packages; run it under `xvfb-run` without a display). It includes
  `tests/edition_test.py`: `FF_EDITION`, `build_ff.sh`'s hashes and the image layout checked against `game/`.
- Instruction fuzzers against Unicorn (`tests/fuzz_sse.py`, `tests/fuzz_insn.py`) and `tools/import_gap.py` (the
  imports the runtime lacks: plan phase 1).
- Test mode: `DS_TEST=1` (an ordinary background window, no mouse capture, no launch window), `W32_AUDIO_MUTE=1`,
  `DS_RESOLUTION=WxH`, `DS_SCRIPT="@145:tap:648,380;@160:shot:/tmp/a.png"` (scripted input at presented frames) and
  `DS_CMDFILE=<file>` (commands appended while the game runs).

## A note from the author

These projects are roughly 90% built with AI, with human testing along the way. I started them because some of my
favorite games either ran badly on macOS or wouldn’t run at all, and Wine and CrossOver didn’t always get me where I
wanted.

I’m a 40-year-old dad with a full-time job. I don’t have the time or desire to write all of this from scratch, and AI
made it possible to get somewhere with it.

If that puts you off, no hard feelings. Use them, skip them, fork them. It’s all good. I would have happily used an
existing, human-written native port, but I couldn’t find one that did what I wanted. Mostly, I just want to play my
games.

The aim is straightforward native builds without unwanted extras or a stack of translation layers. Forks and
improvements are welcome.
