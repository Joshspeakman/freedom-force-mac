"""image_bases.py <game folder> <exe> <dll>... : one line per DLL, "path" when it can stay at its preferred base or
"path@0xBASE" when it overlaps an image before it (the executable, then the DLLs in order) and must be lifted from a
relocated copy (tools/rebase_pe.py). New bases are the first free 16 MB slot from 0x11000000, so each relocated DLL
keeps the 16 MB address window the runtime gives a DLL. Paths are relative to the game folder."""
import struct
import sys
from pathlib import Path


def span(path):
    d = Path(path).read_bytes()[:4096]
    opt = struct.unpack_from('<I', d, 0x3c)[0] + 24
    base, size = struct.unpack_from('<I', d, opt + 28)[0], struct.unpack_from('<I', d, opt + 56)[0]
    return base, (size + 0xffff) & ~0xffff


def plan(game, exe, dlls):
    taken = [span(Path(game) / exe)]
    out = []
    for rel in dlls:
        base, size = span(Path(game) / rel)
        free = lambda b: all(b + size <= tb or tb + ts <= b for tb, ts in taken)
        if free(base):
            out.append(rel)
        else:
            base = 0x11000000
            while not free(base) or not all(abs(base - tb) >= 0x01000000 for tb, _ in taken[1:]): base += 0x01000000
            out.append('%s@%#x' % (rel, base))
        taken.append((base, size))
    return out


if __name__ == '__main__':
    print('\n'.join(plan(sys.argv[1], sys.argv[2], sys.argv[3:])))
