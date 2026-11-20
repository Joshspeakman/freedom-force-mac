/* Freedom Force's small imports: the keyboard translation (ToAscii) for the US layout, and GetKeyboardState. */
#include <assert.h>
#include <stdio.h>
#include "../runtime/win32/ff_imports.c"
static uint8_t memory[1 << 16]; uint8_t *G_MEM = memory;
uint8_t w32_keys[256];
void w32_set_last_error(Ctx *c, uint32_t e) { (void)c; (void)e; }
static char key(uint32_t vk, const char *mods)
{
    uint8_t st[256] = {0};
    for (const char *m = mods; *m; m++) { if (*m == 's') st[0x10] = 0x80; if (*m == 'c') st[0x11] = 0x80; if (*m == 'a') st[0x12] = 0x80; if (*m == 'L') st[0x14] = 1; }
    return (char)w32_to_ascii(vk, st);
}
int main(void)
{
    assert(key('A', "") == 'a' && key('A', "s") == 'A' && key('A', "L") == 'A' && key('A', "sL") == 'a');
    assert(key('1', "") == '1' && key('1', "s") == '!' && key('0', "s") == ')');
    assert(key(0xba, "") == ';' && key(0xba, "s") == ':' && key(0xde, "s") == '"' && key(0xc0, "") == '`');
    assert(key(0x20, "") == ' ' && key(0x0d, "") == '\r' && key(0x08, "") == 8 && key(0x61, "") == '1');
    assert(key('C', "c") == 3 && key('A', "a") == 0 && key(0x70 /* F1 */, "") == 0 && key('1', "c") == 0);
    /* through the import: (vk, scan, state, out, flags); a release (scan bit 15) gives nothing */
    Ctx c = {0}; c.esp = 0x1000; uint32_t state = 0x2000, out = 0x3000;
    memory[state + 0x10] = 0x80;
    uint32_t args[6] = {0x4000, 'Q', 0x10, state, out, 0}; memcpy(memory + c.esp, args, sizeof args);
    imp_user32_ToAscii(&c); assert(c.eax == 1 && memory[out] == 'Q' && c.esp == 0x1000 + 4 + 20);
    c.esp = 0x1000; args[2] = 0x8010; memcpy(memory + c.esp, args, sizeof args);
    imp_user32_ToAscii(&c); assert(c.eax == 0);
    w32_keys['W'] = 0x81; c.esp = 0x1000; uint32_t a2[2] = {0x4000, 0x5000}; memcpy(memory + c.esp, a2, sizeof a2);
    imp_user32_GetKeyboardState(&c); assert(c.eax == 1 && memory[0x5000 + 'W'] == 0x81);
    printf("Freedom Force imports: ToAscii (US layout, Shift, Caps Lock, Ctrl, Alt, releases), GetKeyboardState passed\n");
    return 0;
}
