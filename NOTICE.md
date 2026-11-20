# Notices and credits

**Freedom Force** © its respective rights holders (Irrational Games, 2002). Nothing from the game is in this
repository: the recompiler reads the binaries from the player's own GOG copy and checks each one's checksum against
`game/MANIFEST.txt`, and the app reads the game's data from that copy.

The recompiler, the Windows layer, the renderers and the host come from the author's earlier ports (Dungeon Siege,
Dungeon Siege II, Fallout: New Vegas, The Sims 2), imported from `sims-2-macos`.

Third-party code in this repository:
- **MojoShader** (zlib licence), `recomp/third_party/mojoshader/`: Direct3D 9 shader bytecode to Metal and GLSL.
- **minimp3** (CC0), `recomp/third_party/minimp3/`: MP3 decoding.

Used at build time (installed into `recomp/.venv` with pip, not redistributed here):
- **Capstone** (BSD): disassembly for the recompiler. https://www.capstone-engine.org/
- **Unicorn** (GPL-2.0): x86 emulation, used only by the test suite to compare the recompiled code with the original.
  https://www.unicorn-engine.org/

Specifications and prior work the inherited code learned from:
- Microsoft's published Open Specifications for DirectPlay 8 ([MC-DPL8CS], [MC-DPL8R], [MC-DPLHP]), from which the
  multiplayer network protocol (`dp8proto.c`) is implemented; `recomp/tests/dp8test.c` uses their example packets.
- `src/dsr/dsr_snapshot.bin` records the device capabilities reported by Wine's DirectDraw implementation (Wine,
  LGPL), so that a game sees a consistent Direct3D 7 device.
