# Imports: what the runtime provides and what it lacks (plan phase 1)

Surveyed on 2026-10-16 from the four binaries in `game/` with the runtime imported from `sims-2-macos`:

```sh
recomp/.venv/bin/python recomp/tools/import_gap.py game/fforce.exe game/Standard.dll game/Sound.dll game/python15.dll
```

Imports that another image of the recompiled set exports are bound to it by the loader. They count as served even
though `Sound.dll` is lifted from a copy moved to 0x11000000.

| Image | DLL | Imports | Served by the recompiled set | Implemented natively | Missing |
|---|---|---:|---:|---:|---:|
| fforce.exe | ADVAPI32.dll | 3 |  | 3 |  |
| fforce.exe | DINPUT.dll | 1 |  |  | 1 |
| fforce.exe | GDI32.dll | 1 |  | 1 |  |
| fforce.exe | KERNEL32.dll | 25 |  | 25 |  |
| fforce.exe | MSVCP60.dll | 13 |  |  | 13 |
| fforce.exe | MSVCRT.dll | 90 |  |  | 90 |
| fforce.exe | ole32.dll | 3 |  | 3 |  |
| fforce.exe | python15.dll | 53 | 53 |  |  |
| fforce.exe | Sound.dll | 115 | 115 |  |  |
| fforce.exe | Standard.dll | 76 | 76 |  |  |
| fforce.exe | USER32.dll | 31 |  | 28 | 3 |
| fforce.exe | WINMM.dll | 1 |  | 1 |  |
| Standard.dll | ADVAPI32.dll | 5 |  | 5 |  |
| Standard.dll | KERNEL32.dll | 19 |  | 19 |  |
| Standard.dll | MSVCP60.dll | 4 |  |  | 4 |
| Standard.dll | MSVCRT.dll | 58 |  |  | 58 |
| Standard.dll | USER32.dll | 5 |  | 5 |  |
| Standard.dll | WINMM.dll | 1 |  | 1 |  |
| Standard.dll | zlib-1.1.3.dll | 8 |  |  | 8 |
| Sound.dll | KERNEL32.dll | 3 |  | 3 |  |
| Sound.dll | mss32.dll | 78 |  | 40 | 38 |
| Sound.dll | MSVCP60.dll | 4 |  |  | 4 |
| Sound.dll | MSVCRT.dll | 24 |  |  | 24 |
| Sound.dll | Standard.dll | 14 | 14 |  |  |
| python15.dll | KERNEL32.dll | 20 |  | 19 | 1 |
| python15.dll | MSVCRT.dll | 149 |  |  | 149 |
| python15.dll | USER32.dll | 1 |  |  | 1 |
| python15.dll | WINMM.dll | 1 |  |  | 1 |
| python15.dll | WSOCK32.dll | 30 |  | 27 | 3 |

Not in this table: what the game loads at run time with `LoadLibrary`/`GetProcAddress` (`D3D8.DLL`'s
`Direct3DCreate8`, found in the survey), COM objects made with `CoCreateInstance` (DirectPlay), and the imports of the
DLLs below once they are lifted. A test run lists those (`W32_TRACE`, and "unimplemented import" stops).

## The missing imports, and how each is to be provided

| What | Count | How | Why |
|---|---:|---|---|
| `MSVCRT.dll` (C runtime, MSVC 6) | 90 + 58 + 24 + 149 (≈ 200 distinct) | **Lift the game's own `MSVCRT.dll`** into the image set | Earlier ports had the C runtime linked into the executable, so it was recompiled with the game. Here it is a DLL. It holds C++ exception handling (`__CxxFrameHandler`, `_CxxThrowException`, `_EH_prolog`, `_except_handler3`), `setjmp`/`longjmp`, `printf`/`scanf` formatting (Python's float `repr` depends on it), x87 helpers (`_ftol`, `_CI*`), and `FILE` objects that the game and Python share (`PyRun_File` takes the game's `FILE *`; Python reads `_iob`, `_pctype`). Recompiling it keeps every one of these exact; writing them natively would mean re-implementing Visual C++'s exception machinery. |
| `MSVCP60.dll` (C++ library) | 13 + 4 + 4 | **Lift** | Same reasons: `std::_Lockit`, `ios_base::Init`, exception classes and vtables (`??_7out_of_range@std@@6B@` is data). |
| `zlib-1.1.3.dll` (by ordinal) | 8 | **Lift** | The game ships it; lifting needs no ordinal table, which isn't known here. Host zlib could stand in later. |
| `mss32.dll` (Miles) | 38 of 78 missing from `miles.c` | **Lift `Mss32.dll`**, `System/Miles/Mssfast.m3d` and `System/Miles/Mp3dec.asi` | As Dungeon Siege did. `miles.c` (`W32_MILES=native`) stays the fallback, but it would need those 38 functions first. |
| `DINPUT.dll!DirectInputCreateEx` | 1 | Native: **done** | `IDirectInput7A` and `IDirectInputDevice7A` over `dinput8.c`'s keyboard and mouse (DirectInput 7's device type codes). |
| `USER32`: `GetKeyboardState`, `OpenIcon`, `ToAscii`, `LoadStringA` | 4 | Native: **done** | `ff_imports.c` (`ToAscii`: US layout, tested); `LoadStringA` in `resources.c`, which now also finds a recompiled DLL's resources. |
| `WINMM!PlaySoundA`, `KERNEL32!CreatePipe` | 2 | Native: **done**, both fail | Python's `winsound` and `os.popen`, which the game's scripts are not expected to use. |
| `WSOCK32` ordinals 51, 53, 55 | 3 | Native: **done**, "no data" | `gethostbyaddr`, `getprotobyname`, `getservbyname` (Python's `socket` module). |

**Needs the Mac:** `MSVCRT.dll`, `MSVCP60.dll`, `zlib-1.1.3.dll`, `Mss32.dll`, `System/Miles/Mssfast.m3d` and
`System/Miles/Mp3dec.asi` are not in `game/`. `recomp/build_ff.sh` lifts each of them when it is in the game folder,
checked against `MANIFEST.txt`, and says which are absent. There are two ways to provide them:
- build on the Mac from the GOG folder: `recomp/build_ff.sh ~/Games/FreedomForce`;
- or copy them into `game/` so that cloud sessions lift them too. That puts six more of the game's files in the
  private repository, which is the user's call (`CLAUDE.md`).

## Data imports

On Windows the IAT slot of an imported variable holds the variable's address. The loader now does the same for data
exported by a recompiled image (`loader.c`, `w32_export_is_data`); functions still go through their thunk. Without
this, the game and Python would have used two different `None` objects, and the game's objects would have got
thunk addresses for vtables. `W32_LOADLOG=1` lists the bindings. The 15 in the set:

- `fforce.exe` from `Sound.dll`: `??_7CSoundHandle@@6B@`, `??_7ISoundIO@@6B@` (vtables).
- `fforce.exe` from `Standard.dll`:
  - `??_7CObject@ig@@6B@`, `??_7CRefCount@ig@@6B@` (vtables);
  - `?Class@CObject@ig@@2VCClass@2@B`, `?theDebugMgr@CDebugMgr@@0PAV1@A`,
    `?_instance@?$TSingleton@VCGlobalFileSystem@ig@@@ig@@0PAVCGlobalFileSystem@2@A` (objects).
- `fforce.exe` from `python15.dll`: `PyTuple_Type`, `PyString_Type`, `PyInt_Type`, `PyExc_RuntimeError`,
  `_Py_TrueStruct`, `_Py_NoneStruct`, `_Py_ZeroStruct`.
- `Sound.dll` from `Standard.dll`: `?theDebugMgr@CDebugMgr@@0PAV1@A`.

Verified in a test-mode run on Linux: all 15 were bound to the exporting image's address, `Sound.dll`'s at its new
base. The run then stopped, as expected, at `msvcrt!malloc`, called from `Standard.dll`'s start-up.
