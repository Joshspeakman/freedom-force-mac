/* Windows functions Freedom Force (GOG 1.3) imports beyond what the earlier ports needed (docs/IMPORTS.md): the
 * keyboard state and its translation, and what python15.dll's modules import (pipes, PlaySound, host lookups), which
 * the game's scripts are not expected to call and which fail as they would on a machine without them. */
#include "w32.h"

extern uint8_t w32_keys[256];                          /* user32.c: bit 7 down, bit 0 toggled */

/* ---- user32 ---- */
IMPL(user32, GetKeyboardState) { memcpy(GP(ARG(0)), w32_keys, 256); RET(1, 1); }
/* ToAscii(virtual key, scan code, key state[256], WORD *out, flags): the US layout, which is what the game's text
 * entry expects (names of heroes and saves). Shift and Caps Lock from the given state; Ctrl+letter gives the control
 * character; Alt gives nothing. Returns 1 with the character in *out, or 0. */
static int us_char(uint32_t vk, int shift, int caps)
{
    static const char digits[] = "0123456789", shifted[] = ")!@#$%^&*(";
    static const struct { uint8_t vk; char plain, shift; } oem[] = {
        {0xba, ';', ':'}, {0xbb, '=', '+'}, {0xbc, ',', '<'}, {0xbd, '-', '_'}, {0xbe, '.', '>'}, {0xbf, '/', '?'},
        {0xc0, '`', '~'}, {0xdb, '[', '{'}, {0xdc, '\\', '|'}, {0xdd, ']', '}'}, {0xde, '\'', '"'}};
    if (vk >= 'A' && vk <= 'Z') return (int)(shift != caps ? vk : vk + 32);
    if (vk >= '0' && vk <= '9') return shift ? shifted[vk - '0'] : digits[vk - '0'];
    if (vk >= 0x60 && vk <= 0x69) return '0' + (int)(vk - 0x60);          /* the number pad */
    switch (vk) {
    case 0x20: return ' '; case 0x0d: return '\r'; case 0x08: return 8; case 0x09: return '\t'; case 0x1b: return 27;
    case 0x6a: return '*'; case 0x6b: return '+'; case 0x6d: return '-'; case 0x6e: return '.'; case 0x6f: return '/';
    }
    for (size_t k = 0; k < sizeof oem / sizeof *oem; k++) if (oem[k].vk == vk) return shift ? oem[k].shift : oem[k].plain;
    return 0;
}
int w32_to_ascii(uint32_t vk, const uint8_t *state)
{
    int shift = (state[0x10] & 0x80) != 0, caps = state[0x14] & 1, ctrl = (state[0x11] & 0x80) != 0, alt = (state[0x12] & 0x80) != 0;
    if (alt) return 0;
    if (ctrl) return vk >= 'A' && vk <= 'Z' ? (int)(vk - 'A' + 1) : 0;
    return us_char(vk & 0xff, shift, caps);
}
IMPL(user32, ToAscii)
{
    uint32_t vk = ARG(0), scan = ARG(1), state = ARG(2), out = ARG(3);
    if (scan & 0x8000) RET(0, 5);                     /* a key release */
    int ch = state ? w32_to_ascii(vk, GP(state)) : 0;
    if (!ch) RET(0, 5);
    rt_w16(G_MEM, out, (uint16_t)ch); RET(1, 5);
}
/* OpenIcon(window): restore a minimized window. The host owns minimizing (the game window is never iconic in the
 * runtime's own sense of the game asking for it), so there is nothing to restore. */
IMPL(user32, OpenIcon) { RET(1, 1); }

/* ---- winmm: PlaySoundA (Python's winsound): no sound played; stopping (no sound named) succeeds ---- */
IMPL(winmm, PlaySoundA) { RET(ARG(0) ? 0u : 1u, 3); }

/* ---- kernel32: CreatePipe (Python's os.popen): no child processes here ---- */
IMPL(kernel32, CreatePipe) { w32_set_last_error(c, 5); RET(0, 4); }           /* ERROR_ACCESS_DENIED */

/* ---- wsock32 (Python's socket module): lookups the game doesn't use, answered "no data" (WSANO_DATA) ---- */
IMPL(wsock32, ord51) { rt_w32(G_MEM, c->fs_base + 0x34, 11004); RET(0, 3); }  /* gethostbyaddr(addr, len, type) */
IMPL(wsock32, ord53) { rt_w32(G_MEM, c->fs_base + 0x34, 11004); RET(0, 1); }  /* getprotobyname(name) */
IMPL(wsock32, ord55) { rt_w32(G_MEM, c->fs_base + 0x34, 11004); RET(0, 2); }  /* getservbyname(name, proto) */
