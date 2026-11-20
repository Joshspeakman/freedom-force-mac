"""Switch bounds the lifter must find exactly (a guess reads past the table and decodes data as code). Synthetic x86 in
the forms MSVC 6 emits in Freedom Force; no game files needed."""
from pathlib import Path
from types import SimpleNamespace
import collections
import struct
import sys
import unittest
import capstone

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from lift import Lifter

BASE = 0x401000


def lifter(code):
    l = Lifter.__new__(Lifter)
    l.TLO, l.THI, l.code = BASE, BASE + len(code), bytes(code)
    u32 = lambda va: struct.unpack_from('<I', code, va - BASE)[0] if BASE <= va < l.THI - 3 else None
    l.pe = SimpleNamespace(u32=u32, bytes_at=lambda va, n: bytes(code[va - BASE:va - BASE + n]))
    l.md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32); l.md.detail = True
    l.funcs = {BASE}; l.cache = {}; l.jt_cache = {}; l.imp_index = {}; l.scc_of = {}
    l.tail_edges = collections.defaultdict(set); l.unsup = collections.Counter(); l.internal = []; l.unres_jt = []
    l.hooks = {}; l.overrides = {}; l.illegal_seh = False; l.guest_flow = False
    return l


def program(prologue, jmp_index_reg_byte, table_at, entries, extra):
    """prologue bytes at BASE, then jmp [reg*4 + table]; the table has `entries` real targets then `extra` more code
    pointers (a neighbouring switch's), each target a ret"""
    code = bytearray(b'\xcc' * 0x200)
    code[:len(prologue)] = prologue
    jmp_at = len(prologue)
    code[jmp_at:jmp_at + 7] = bytes([0xff, 0x24, jmp_index_reg_byte]) + struct.pack('<I', BASE + table_at)
    for k in range(entries + extra):
        target = 0x180 + 2 * k; code[target] = 0xc3
        struct.pack_into('<I', code, table_at + 4 * k, BASE + target)
    return code, BASE + jmp_at


class Bounds(unittest.TestCase):
    def bound(self, code, jmp):
        l = lifter(code); l.collect(BASE)
        return len(l.jt_cache[jmp][1]), jmp in l.unres_jt

    def test_bound_in_a_register_from_push_pop(self):
        # push 9; lea ecx, [ebx-1]; pop edi; xor eax, eax; cmp ecx, edi; ja +7; jmp [ecx*4 + table]
        pro = bytes.fromhex('6a09' '8d4bff' '5f' '33c0' '3bcf' '7707')
        code, jmp = program(pro, 0x8d, 0x100, 10, 6)
        code[jmp - BASE + 7] = 0xc3                                    # the ja target
        self.assertEqual(self.bound(code, jmp), (10, False))

    def test_bound_in_a_register_from_mov(self):
        # mov edx, 4; cmp eax, edx; ja +7; jmp [eax*4 + table]
        pro = bytes.fromhex('ba04000000' '3bc2' '7707')
        code, jmp = program(pro, 0x85, 0x100, 5, 6)
        code[jmp - BASE + 7] = 0xc3
        self.assertEqual(self.bound(code, jmp), (5, False))

    def test_byte_table_through_al(self):
        # cmp edx, 0x1e; ja +x; xor eax, eax; mov al, [edx + bytes]; jmp [eax*4 + table]: the bound is the largest byte
        pro = bytes.fromhex('83fa1e' '770f' '33c0' '8a82') + struct.pack('<I', BASE + 0xc0)
        code, jmp = program(pro, 0x85, 0x100, 4, 6)
        code[jmp - BASE + 7] = 0xc3
        code[0xc0:0xc0 + 31] = bytes([k % 4 for k in range(31)])
        self.assertEqual(self.bound(code, jmp), (4, False))


class FarTargets(unittest.TestCase):
    def test_unbounded_table_into_reordered_code(self):
        # Windows' basic-block reordered DLLs (MSVCRT's memcpy): an unbounded jmp [edx*4 + table] whose entries alternate
        # near blocks and blocks of a function 10 KB away. Far entries count only on that function's instruction
        # boundaries: one inside "mov eax, imm32" is padding read as an address, not code.
        code = bytearray(b'\xcc' * 0x3000)
        code[0:2] = bytes.fromhex('23d1')                                     # and edx, ecx (no bound)
        code[2:9] = bytes([0xff, 0x24, 0x95]) + struct.pack('<I', BASE + 0x100)
        code[0x180] = 0xc3
        far = 0x2800; code[far:far + 15] = bytes.fromhex('b844332211') * 3; code[far + 15] = 0xc3
        for k, t in enumerate((0x180, far + 10, far + 1)):
            struct.pack_into('<I', code, 0x100 + 4 * k, BASE + t)
        l = lifter(code); l.funcs.add(BASE + far); l.collect(BASE)
        self.assertEqual(sorted(l.jt_cache[BASE + 2][1]), [BASE + 0x180, BASE + far + 10])


if __name__ == '__main__':
    unittest.main()
