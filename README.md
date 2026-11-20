# Freedom Force for macOS (native Metal port)

> This repository holds no game files. You need your own copy of *Freedom Force* (GOG 1.3); the build reads it from
> your game folder and checks it against [`game/MANIFEST.txt`](game/MANIFEST.txt).

The goal is a native Apple Silicon build of *Freedom Force* (Irrational Games, 2002) drawing with Metal. It's made the
way the other ports were (Dungeon Siege, Dungeon Siege II, Diablo II, Fallout: New Vegas, The Sims, The Sims 2):
- the game's x86 code is statically recompiled to C, then compiled for arm64;
- a small Windows layer runs it;
- its Direct3D 8 drawing becomes Metal.

Players use their own copy. GOG's comes first; Steam's comes later.

- [`docs/PLAN.md`](docs/PLAN.md): the intent, what is known about the game, the phases, and which work needs the Mac.
- [`recomp/README.md`](recomp/README.md): the recompiler, the Windows layer and the hosts, imported from
  `sims-2-macos`, and how to build (`recomp/build_ff.sh`).
- `src/`: the renderers (Metal, and OpenGL for the Linux development host) and their command protocol.
- `game/MANIFEST.txt`: every file the GOG 1.3 installer (build 19478) installs, with its hash and size. The recompiler
  reads `fforce.exe`, the game's own `Standard.dll` and `Sound.dll`, and `python15.dll` from your game folder
  (`recomp/build_ff.sh "/path/to/Freedom Force"`), and checks each against this list.

## Status and installing

Plays in test mode on an Apple Silicon Mac: a new campaign reaches mission 1 and plays, saves load, every map (68)
loads and was toured, and the coverage test runs every character, power, state and effect without a crash. Not yet
checked on screen: real full screen and the notch, the Retina cursor, listening to the sound, a whole campaign. The
log is [`docs/PLAN.md`](docs/PLAN.md)'s "Done so far"; it is the status, not this paragraph. Installing needs the
Xcode command line tools:

```sh
./install.sh --gog-installer "setup_freedom_force_1.3_(19478).exe"   # GOG's offline installer (brew install innoextract)
./install.sh --game-dir "/path/to/Freedom Force"                     # or a game folder copied from Windows
./install.sh --nightly                                               # "Freedom Force Nightly.app", from the nightly branch
```

The app goes to `~/Applications`, and saves, settings and logs to `~/Games/FreedomForceNative`; the game folder is only
read. For developers, `recomp/tools/ff_iterate.sh` builds and runs a short test session (`DS_TEST=1`, muted audio, a
scratch data folder).
