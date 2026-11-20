"""Freedom Force edition: the executable check, build_ff.sh's hashes and edition.h against game/ and its manifest."""
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parent/'game'
sys.path.insert(0, str(ROOT/'tools'))
from editions import FF_GOG_13, PROFILES, identify


def manifest():
    """game/MANIFEST.txt: path -> sha256 (lines 'sha256  bytes  path'; # comments)."""
    out = {}
    for line in (GAME/'MANIFEST.txt').read_text().splitlines():
        if line.startswith('#') or not line.strip(): continue
        sha, _size, path = line.split(None, 2)
        out[path] = sha
    return out


def image_end(path):
    d = path.read_bytes(); opt = struct.unpack_from('<I', d, 0x3c)[0] + 24
    return struct.unpack_from('<I', d, opt + 28)[0] + struct.unpack_from('<I', d, opt + 56)[0]


@unittest.skipUnless((GAME/'MANIFEST.txt').is_file(), 'no game/ folder (private repository only)')
class FreedomForce(unittest.TestCase):
    def test_executable_is_recognised(self):
        self.assertEqual(identify(GAME/'fforce.exe'), 'ff')
        self.assertEqual(PROFILES['ff']['sha256'], manifest()['fforce.exe'])
        self.assertEqual(PROFILES['ff']['hooks'], ())

    def test_build_script_lifts_only_manifest_files(self):
        """build_ff.sh checks every binary it lifts against the manifest: each one it names must be listed there."""
        script = (ROOT/'build_ff.sh').read_text()
        names = ['fforce.exe'] + [n for key in ('REQUIRED', 'OPTIONAL')
                                  for n in re.search(key + r'=\(([^)]*)\)', script).group(1).split()]
        self.assertEqual(names[:4], ['fforce.exe', 'Standard.dll', 'Sound.dll', 'python15.dll'])
        m = manifest()
        for name in names: self.assertIn(name, m)
        self.assertEqual(m['fforce.exe'], FF_GOG_13)

    def test_edition_header(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d)/'e.c'; exe = Path(d)/'e'
            src.write_text('#include "edition.h"\n#include <stdio.h>\n'
                           'int main(void) { printf("%s|%s|%s|%x|%d\\n", GAME_EXE, HOST_NAME, DS2_TITLE, DS2_IMAGE_END,'
                           '\n#ifdef NO_DS2_NATIVE\n1\n#else\n0\n#endif\n); return 0; }\n')
            subprocess.run(['clang', '-DFF_EDITION', '-I', str(ROOT/'runtime'), str(src), '-o', str(exe)], check=True)
            exe_name, host, title, end, no_native = subprocess.run([str(exe)], check=True, capture_output=True,
                                                                  text=True).stdout.strip().split('|')
        self.assertEqual((exe_name, host, title, no_native), ('fforce.exe', 'FreedomForceNative', 'Freedom Force', '1'))
        want = (image_end(GAME/'fforce.exe') + 0xfff) & ~0xfff         # the image's end, page-aligned
        self.assertEqual(int(end, 16), want)

    def test_dll_bases_do_not_overlap(self):
        """the four binaries in game/ after tools/image_bases.py: Sound.dll moves (Standard.dll has 0x10000000) and no
        two images overlap"""
        from image_bases import plan, span
        specs = plan(GAME, 'fforce.exe', ['Standard.dll', 'Sound.dll', 'python15.dll'])
        self.assertEqual(specs, ['Standard.dll', 'Sound.dll@0x11000000', 'python15.dll'])
        spans = [(0x400000, image_end(GAME/'fforce.exe'), 'fforce.exe')]
        for spec in specs:
            name, _, base = spec.partition('@')
            b, size = span(GAME/name)
            b = int(base, 16) if base else b
            spans.append((b, b + size, name))
        spans.sort()
        for (b0, e0, n0), (b1, e1, n1) in zip(spans, spans[1:]):
            self.assertLessEqual(e0, b1, f'{n0} overlaps {n1}')

    def test_relocation_keeps_away_from_every_image(self):
        """a synthetic set where three DLLs want one base: each later one gets its own free 16 MB slot"""
        import image_bases
        spans = {'a.exe': (0x400000, 0x350000), 'x.dll': (0x10000000, 0x20000), 'y.dll': (0x10000000, 0x20000),
                 'z.dll': (0x10000000, 0x20000), 'w.dll': (0x11000000, 0x10000)}
        real = image_bases.span
        image_bases.span = lambda p: spans[Path(p).name]
        try: out = image_bases.plan('/', 'a.exe', ['x.dll', 'w.dll', 'y.dll', 'z.dll'])
        finally: image_bases.span = real
        self.assertEqual(out, ['x.dll', 'w.dll', 'y.dll@0x12000000', 'z.dll@0x13000000'])


if __name__ == '__main__':
    unittest.main()
