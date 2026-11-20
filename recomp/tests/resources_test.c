/* PE resource lookup by name (FindResourceExA): names compare case-insensitively for A-Z only. Freedom Force finds its
 * menus as named RT_DIALOG resources (DLG_MAINMENU, language 0xc09); "| 32" on every character made '_' never match.
 * A synthetic resource directory; no game files. */
#include <assert.h>
#include <stdio.h>
#include "../runtime/win32/resources.c"
static uint8_t memory[1 << 20]; uint8_t *G_MEM = memory;
uint32_t w32_image_base = 0x10000, w32_process_heap, w32_env_a;
const char *w32_image_name(uint32_t base) { (void)base; return 0; }
int w32_wide_to_mb(uint32_t cp, const uint16_t *s, int n, uint8_t *out, int cap) { (void)cp; (void)s; (void)n; (void)out; (void)cap; return 0; }
uint32_t w32_callback(Ctx *c, uint32_t fn, int nargs, const uint32_t *args) { (void)c; (void)fn; (void)nargs; (void)args; return 0; }
void w32_now_systemtime(uint32_t p) { (void)p; }
uint32_t heap_alloc(uint32_t h, uint32_t flags, uint32_t size) { (void)h; (void)flags; (void)size; return 0; }
int heap_free(uint32_t h, uint32_t p) { (void)h; (void)p; return 0; }
void w32_set_last_error(Ctx *c, uint32_t e) { (void)c; (void)e; }
static void w16(uint32_t a, uint16_t v) { memcpy(memory + a, &v, 2); }
static void w32(uint32_t a, uint32_t v) { memcpy(memory + a, &v, 4); }
static uint32_t find(const char *name, uint32_t lang)
{
    Ctx c = {0}; c.esp = 0x8000; uint32_t s = 0x40000;        /* a name above 0x10000: below it is an integer id */
    strcpy((char *)memory + s, name);
    uint32_t args[5] = {0x4000, 0, 5 /* RT_DIALOG */, s, lang}; memcpy(memory + c.esp, args, sizeof args);
    imp_kernel32_FindResourceExA(&c); assert(c.esp == 0x8000 + 4 + 16);
    return c.eax;
}
int main(void)
{
    uint32_t base = w32_image_base, root = base + 0x1000;
    w32(base + 0x3c, 0x80); w32(base + 0x80 + 24 + 96 + 16, 0x1000);       /* the resource directory's RVA */
    w16(root + 14, 1); w32(root + 16, 5); w32(root + 20, 0x80000000u | 0x18);                 /* type 5 */
    w16(root + 0x18 + 12, 1); w32(root + 0x18 + 16, 0x80000000u | 0x100); w32(root + 0x18 + 20, 0x80000000u | 0x30);
    w16(root + 0x30 + 14, 1); w32(root + 0x30 + 16, 0xc09); w32(root + 0x30 + 20, 0x48);      /* English (Australia) */
    w32(root + 0x48, 0x2000); w32(root + 0x4c, 0x10);                                         /* the data entry */
    const char *nm = "DLG_MAINMENU"; w16(root + 0x100, (uint16_t)strlen(nm));
    for (size_t k = 0; nm[k]; k++) w16(root + 0x102 + 2 * (uint32_t)k, (uint16_t)nm[k]);
    assert(find("DLG_MAINMENU", 0xc09) == root + 0x48);
    assert(find("dlg_mainmenu", 0xc09) == root + 0x48);
    assert(find("DLG_MAINMENU", 0x409) == root + 0x48);                    /* another language: the first one there */
    assert(find("DLG\x7fMAINMENU", 0xc09) == 0 && find("DLG_MAINMENUS", 0xc09) == 0 && find("DLG_MAINMEN", 0xc09) == 0);
    printf("PE resources: named lookup with '_', case, language fallback and mismatches passed\n");
    return 0;
}
