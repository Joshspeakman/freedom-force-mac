/* Direct3D 8 (d3d8.c) through the real runtime, as the game calls it: Direct3DCreate8 found by GetProcAddress, every
 * method reached through the guest vtables and the import thunks. Checks what the game reads back (identifier, modes,
 * caps, descriptions, locks, handles, state blocks) and what reaches the renderer (the command ring's records).
 * Linked with the whole runtime built with -DFF_EDITION (tests/check_linux.sh); no game files. */
#include "d3d9_priv.h"                                /* the interface types (O9_*) */
#undef M
#undef END
#include "../../src/dsr/dsr_shm.h"
#include "../../src/dsr/dsr_proto.h"
#include <assert.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

/* no lifted code: empty tables */
const struct rt_fn { uint32_t addr; GuestFn fn; } rt_fntab[1] = {{0, 0}}; const unsigned rt_fntab_n = 0;
const struct rt_imp { uint32_t iat; const char *name; } rt_imptab[1] = {{0, ""}}; const unsigned rt_imptab_n = 0;
const struct rt_image { const char *name; uint32_t base, imp_first, imp_count; } rt_images[] = {{"", 0x400000u, 0, 0}};
const unsigned rt_images_n = 1;
void dsr_attach_consumer(DsrShmHeader *h);
extern int w32_screen_w, w32_screen_h, w32_screen_hz;
extern uint32_t vt[64];

static Ctx C;
static DsrShmHeader *H;
static uint32_t ring_seen;
static uint32_t r32(uint32_t a) { return rt_r32(G_MEM, a); }
static uint32_t galloc(uint32_t n) { uint32_t a = heap_alloc(w32_process_heap, 8, n); memset(G_MEM + a, 0, n); return a; }
static uint32_t gcall(uint32_t fn, int n, const uint32_t *a)
{
    uint32_t esp = C.esp;
    for (int k = n - 1; k >= 0; k--) { C.esp -= 4; rt_w32(G_MEM, C.esp, a[k]); }
    C.esp -= 4; rt_w32(G_MEM, C.esp, 0);
    rt_call(&C, fn);
    assert(C.esp == esp);                                  /* stdcall: the method popped its arguments */
    return C.eax;
}
/* iface->method(args...) */
static uint32_t M(uint32_t iface, int slot, int n, ...)
{
    uint32_t a[16]; va_list ap; va_start(ap, n); a[0] = iface; for (int k = 0; k < n; k++) a[k + 1] = va_arg(ap, uint32_t); va_end(ap);
    return gcall(r32(r32(iface) + 4u * (uint32_t)slot), n + 1, a);
}
/* records since the last call: count of op, and the payload of the last one */
static int ring_count(uint32_t op, const uint32_t **last)
{
    int n = 0; uint8_t *ring = (uint8_t *)H + DSR_HEADER_SIZE;
    for (uint32_t p = ring_seen; p != H->write_pos; ) {
        uint32_t *h = (uint32_t *)(ring + p % DSR_RING_SIZE);
        if (h[0] == DSR_WRAP) { p += 8 + h[1]; continue; }
        if (h[0] == op) { n++; if (last) *last = h + 2; }
        p += 8 + h[1];
    }
    return n;
}
static void ring_mark(void) { ring_seen = H->write_pos; H->read_pos = H->write_pos; }

/* Synthetic skinning exercises both UP and buffer draws, independent of game assets. */
static void blending_test(uint32_t dev)
{
    uint32_t wm = galloc(64), up = galloc(256), vbp = galloc(4), locked = galloc(4);
    const uint32_t *rec = 0;
    for (int indexed = 0; indexed <= 1; indexed++) for (int weights = indexed ? 0 : 1; weights <= 3; weights++) {
        float total = 0, expected = 2;
        unsigned betas = weights + indexed, fvf = 0x110 | (4 + 2 * betas) | (indexed ? 0x1000 : 0);
        unsigned stride = 12 + 4 * betas + 12 + 8;
        for (int j = 0; j <= weights; j++) {
            float m[16] = {2,0,0,0, 0,1,0,0, 0,0,1,0, 10.0f*(j+1),0,0,1};
            memcpy(G_MEM + wm, m, 64);
            assert(M(dev, 37, 2, 256 + (indexed ? 200+j : j), wm) == 0);
            float w = j < weights ? 0.1f*(j+1) : 1-total;
            expected += w * m[12]; if (j < weights) total += w;
        }
        for (int i = 0; i < 3; i++) {
            uint8_t *v = G_MEM + up + i*stride;
            float xyz[3] = {1,2,3}, normal[3] = {1,0,-1}, uv[2] = {0.25f,0.75f};
            memcpy(v, xyz, 12);
            for (int j = 0; j < weights; j++) { float w = 0.1f*(j+1); memcpy(v+12+4*j, &w, 4); }
            if (indexed) { uint8_t indices[4] = {200,201,202,203}; memcpy(v+12+4*weights, indices, 4); }
            memcpy(v+12+4*betas, normal, 12); memcpy(v+24+4*betas, uv, 8);
        }
        assert(M(dev, 50, 2, 151, weights ? weights : 256) == 0);
        assert(M(dev, 50, 2, 167, indexed) == 0);
        assert(M(dev, 76, 1, fvf) == 0);
        assert(M(dev, 23, 5, 3*stride, 0, fvf, 1, vbp) == 0);
        uint32_t vb = r32(vbp);
        assert(M(vb, 11, 4, 0, 0, locked, 0) == 0);
        memcpy(G_MEM + r32(locked), G_MEM + up, 3*stride);
        assert(M(vb, 12, 0) == 0 && M(dev, 83, 3, 0, vb, stride) == 0);
        for (int buffer = 0; buffer < 2; buffer++) {
            ring_mark();
            assert((buffer ? M(dev, 70, 3, 4, 0, 1) : M(dev, 72, 4, 4, 1, up, stride)) == 0);
            assert(ring_count(DSR_DRAW, &rec) == 1 && rec[1] == 0x112);
            float out[8]; memcpy(out, rec+4, sizeof out);
            assert(fabsf(out[0]-expected) < 0.0001f && out[1] == 2 && out[2] == 3);
            assert(out[3] == 0.5f && out[4] == 0 && out[5] == -1); /* inverse transpose */
            assert(out[6] == 0.25f && out[7] == 0.75f);
            assert(ring_count(DSR_TRANSFORM, &rec) == 2 && rec[0] == 1); /* identity, then restore */
            float restored[16]; memcpy(restored, rec+1, 64);
            assert(restored[0] == 2 && restored[12] == 10);
        }
        M(vb, 2, 0);
    }
    assert(M(dev, 50, 2, 151, 0) == 0 && M(dev, 50, 2, 167, 0) == 0);
    assert(M(dev, 76, 1, 0x112) == 0);
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 32) == 0);
    assert(ring_count(DSR_TRANSFORM, 0) == 0); /* ordinary meshes keep their world transform */
}

/* D3DTSS_TEXCOORDINDEX on fixed-function draws: the renderer takes stage 0's coordinates from the first set and stage
 * 1's from the second, so the layer repacks a draw whose stages use other sets (Freedom Force's city corners: a layer
 * drawn with the third set came out black, sampled with the first set's coordinates) */
static void texcoord_index_test(uint32_t dev, uint32_t tex)
{
    uint32_t up = galloc(3 * 36); const uint32_t *rec = 0; float out[7];
    for (int i = 0; i < 3; i++) { float v[9] = {(float)i, 2, 3, 0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f}; memcpy(G_MEM + up + 36 * i, v, 36); }
    assert(M(dev, 76, 1, 0x302) == 0);                                                      /* XYZ | TEX3 */
    assert(M(dev, 61, 2, 1, 0) == 0 && M(dev, 63, 3, 1, 1, 1) == 0);                        /* stage 1 off */
    assert(M(dev, 63, 3, 0, 11, 2) == 0);                                                   /* stage 0: the third set */
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 36) == 0);
    assert(ring_count(DSR_DRAW, &rec) == 1 && rec[1] == 0x202);
    memcpy(out, rec + 4 + 7, 7 * 4); assert(out[0] == 1 && out[3] == 0.5f && out[4] == 0.6f);   /* the second vertex */
    assert(M(dev, 63, 3, 0, 11, 0) == 0);                                                   /* the first set: unchanged */
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 36) == 0);
    assert(ring_count(DSR_DRAW, &rec) == 1 && rec[1] == 0x302);
    assert(M(dev, 61, 2, 1, tex) == 0 && M(dev, 63, 3, 1, 1, 4) == 0 && M(dev, 63, 3, 1, 11, 2) == 0);   /* stage 1 on, the third set */
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 36) == 0);
    assert(ring_count(DSR_DRAW, &rec) == 1 && rec[1] == 0x202);
    memcpy(out, rec + 4, 7 * 4); assert(out[3] == 0.1f && out[4] == 0.2f && out[5] == 0.5f && out[6] == 0.6f);
    assert(M(dev, 63, 3, 1, 11, 1) == 0);                                                   /* stage 1 on its own set 1: unchanged */
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 36) == 0);
    assert(ring_count(DSR_DRAW, &rec) == 1 && rec[1] == 0x302);
    assert(M(dev, 63, 3, 1, 1, 1) == 0 && M(dev, 61, 2, 1, 0) == 0);
}

int main(void)
{
    setenv("DSR_FPSCAP", "0", 1);
    void *mem = mmap(0, 1ull << 32, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
    assert(mem != MAP_FAILED); G_MEM = mem;
    w32_process_heap = heap_create(0, 0);
    w32_screen_w = 1280; w32_screen_h = 800; w32_screen_hz = 60;
    H = mmap(0, DSR_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0); assert(H != MAP_FAILED);
    H->magic = DSR_SHM_MAGIC; dsr_attach_consumer(H);
    uint32_t stack = vm_alloc(0, 1u << 20, 0x3000, 4); C.esp = stack + (1u << 20) - 64; C.fs_base = galloc(0x1000); C.fcw = 0x27f;

    /* LoadLibrary("D3D8.DLL") + GetProcAddress, as the game does */
    uint32_t name = galloc(32); strcpy((char *)G_MEM + name, "D3D8.DLL");
    uint32_t mod = gcall(w32_thunk_for("kernel32.dll", "LoadLibraryA"), 1, (uint32_t[]){name});
    assert(mod);
    uint32_t sym = galloc(32); strcpy((char *)G_MEM + sym, "Direct3DCreate8");
    uint32_t create = gcall(w32_thunk_for("kernel32.dll", "GetProcAddress"), 2, (uint32_t[]){mod, sym});
    assert(create);
    uint32_t d3d = gcall(create, 1, (uint32_t[]){220});
    assert(d3d && r32(d3d) == vt[O9_D3D]);

    /* IDirect3D8 */
    uint32_t id = galloc(1100); assert(M(d3d, 5, 3, 0, 0, id) == 0);                        /* GetAdapterIdentifier */
    #ifdef __APPLE__
    const char *adapter = "Metal";
#else
    const char *adapter = "Linux";
#endif
    assert(strstr((char *)G_MEM + id + 512, adapter) && r32(id + 1032) == 0x1002 && r32(id + 1064) == 1);
    uint32_t nmodes = M(d3d, 6, 1, 0); assert(nmodes > 0);                                  /* GetAdapterModeCount */
    uint32_t mode = galloc(16); assert(M(d3d, 7, 3, 0, nmodes - 1, mode) == 0);            /* EnumAdapterModes: the last */
    assert(r32(mode) == 1280 && r32(mode + 4) == 800 && r32(mode + 12) == 22);
    uint32_t caps = galloc(212); assert(M(d3d, 13, 3, 0, 1, caps) == 0);                   /* GetDeviceCaps (HAL) */
    assert(r32(caps + 22 * 4) == 4096 && r32(caps + 49 * 4) == 0xfffe0000u && r32(caps + 51 * 4) == 0xffff0000u);
    assert(M(d3d, 11, 5, 0, 1, 22, 1, 0) == 0);                                            /* CheckDeviceMultiSampleType(NONE) */

    /* CreateDevice: D3DPRESENT_PARAMETERS8 (13 DWORDs), windowed, automatic D24S8 depth, COPY_VSYNC */
    uint32_t pp = galloc(52), devp = galloc(4);
    uint32_t p8[13] = {640, 480, 22, 1, 0, 4, 0x10010, 1, 1, 75, 0, 0, 0}; memcpy(G_MEM + pp, p8, 52);
    ring_mark();
    assert(M(d3d, 15, 6, 0, 1, 0x10010, 0x40, pp, devp) == 0);
    uint32_t dev = r32(devp); assert(dev && r32(dev) == vt[O9_DEV]);
    assert(r32(pp) == 640 && r32(pp + 20) == 4);                                             /* still Direct3D 8's layout */
    assert(ring_count(DSR_SURFACE_CREATE, 0) >= 2);                                         /* back buffer and depth buffer */
    assert(M(dev, 7, 1, caps) == 0 && r32(caps + 49 * 4) == 0xfffe0000u);                  /* the device's GetDeviceCaps */

    /* a texture: Direct3D 8's level description has a Size; locks and the upload */
    uint32_t texp = galloc(4);
    assert(M(dev, 20, 7, 64, 32, 1, 0, 21, 1, texp) == 0);                                 /* CreateTexture(A8R8G8B8, MANAGED) */
    uint32_t tex = r32(texp); assert(tex && r32(tex) == vt[O9_TEX]);
    uint32_t desc = galloc(32); assert(M(tex, 14, 2, 0, desc) == 0);                       /* GetLevelDesc */
    assert(r32(desc) == 21 && r32(desc + 16) == 64 * 32 * 4 && r32(desc + 24) == 64 && r32(desc + 28) == 32);
    assert(M(tex, 13, 0) == 1);                                                              /* GetLevelCount */
    uint32_t lr = galloc(8); assert(M(tex, 16, 4, 0, lr, 0, 0) == 0 && r32(lr) == 256);    /* LockRect */
    memset(G_MEM + r32(lr + 4), 0x7f, 256 * 32);
    ring_mark(); assert(M(tex, 17, 1, 0) == 0); assert(ring_count(DSR_SURFACE_UPLOAD, 0) == 1);   /* UnlockRect */
    uint32_t surfp = galloc(4); assert(M(tex, 15, 2, 0, surfp) == 0);                      /* GetSurfaceLevel */
    uint32_t surf = r32(surfp); assert(r32(surf) == vt[O9_SURF]);
    assert(M(surf, 8, 1, desc) == 0 && r32(desc + 16) == 64 * 32 * 4);                    /* IDirect3DSurface8::GetDesc */
    M(surf, 2, 0);

    /* sampler states as texture-stage states: the mip filter goes out in Direct3D 7's numbering */
    const uint32_t *rec = 0; uint32_t v = galloc(4);
    ring_mark(); assert(M(dev, 63, 3, 0, 18, 2) == 0);                                      /* SetTextureStageState(0, MIPFILTER, LINEAR) */
    assert(ring_count(DSR_TSS, &rec) == 1 && rec[0] == 0 && rec[1] == 18 && rec[2] == 3);
    assert(M(dev, 62, 3, 0, 18, v) == 0 && r32(v) == 2);
    ring_mark(); assert(M(dev, 63, 3, 1, 1, 4) == 0);                                       /* COLOROP: a texture-stage state */
    assert(ring_count(DSR_TSS, &rec) == 1 && rec[0] == 1 && rec[1] == 1 && rec[2] == 4);
    assert(M(dev, 61, 2, 0, tex) == 0);                                                     /* SetTexture */

    /* vertex shaders: an FVF code, and a declaration handle */
    assert(M(dev, 76, 1, 0x44) == 0 && M(dev, 77, 1, v) == 0 && r32(v) == 0x44);           /* XYZRHW | DIFFUSE */
    uint32_t decl = galloc(32), hp = galloc(4);
    uint32_t tok[] = {0x20000000u, 0x40020000u, 0x40040005u, 0x80000000u | 3u << 25 | 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xffffffffu};
    tok[3] = 0x80000000u | 1u << 25 | 4;                                                    /* D3DVSD_CONST(4, 1) */
    float k4[4] = {1, 2, 3, 4}; memcpy(&tok[4], k4, 16); tok[8] = 0xffffffffu;
    decl = galloc(sizeof tok); memcpy(G_MEM + decl, tok, 36);
    assert(M(dev, 75, 4, decl, 0, hp, 0) == 0);                                              /* CreateVertexShader(declaration only) */
    uint32_t h = r32(hp); assert(h & 1);
    assert(M(dev, 76, 1, h) == 0 && M(dev, 77, 1, v) == 0 && r32(v) == h);
    uint32_t cst = galloc(16); assert(M(dev, 80, 3, 4, cst, 1) == 0 && !memcmp(G_MEM + cst, k4, 16));   /* the declaration's constant */
    uint32_t size = galloc(4); rt_w32(G_MEM, size, 0);
    assert(M(dev, 81, 3, h, 0, size) == 0 && r32(size) == 36);                              /* GetVertexShaderDeclaration */
    assert(M(dev, 78, 1, h) == 0 && M(dev, 76, 1, h) != 0);                                 /* deleted: no longer usable */

    /* a pretransformed triangle from a vertex buffer */
    uint32_t vbp = galloc(4); assert(M(dev, 23, 5, 60, 0, 0x44, 1, vbp) == 0);
    uint32_t vb = r32(vbp), data = galloc(4); assert(r32(vb) == vt[O9_VB]);
    assert(M(vb, 11, 4, 0, 0, data, 0) == 0);
    float tri[15] = {10, 10, 0.5f, 1, 0, 100, 10, 0.5f, 1, 0, 10, 100, 0.5f, 1, 0};
    uint32_t col = 0xff00ff00u; memcpy(&tri[4], &col, 4); memcpy(&tri[9], &col, 4); memcpy(&tri[14], &col, 4);
    memcpy(G_MEM + r32(data), tri, 60); assert(M(vb, 12, 0) == 0);
    uint32_t vdesc = galloc(24); assert(M(vb, 13, 1, vdesc) == 0 && r32(vdesc + 16) == 60 && r32(vdesc + 20) == 0x44);
    assert(M(dev, 83, 3, 0, vb, 20) == 0);                                                  /* SetStreamSource(0, vb, 20) */
    uint32_t vb2 = galloc(4), stride = galloc(4); assert(M(dev, 84, 3, 0, vb2, stride) == 0 && r32(vb2) == vb && r32(stride) == 20);
    assert(M(dev, 76, 1, 0x44) == 0);
    ring_mark(); assert(M(dev, 34, 0) == 0);                                                /* BeginScene */
    assert(M(dev, 70, 3, 4, 0, 1) == 0);                                                    /* DrawPrimitive(TRIANGLELIST, 0, 1) */
    assert(ring_count(DSR_DRAW, &rec) == 1 && rec[0] == 4 && rec[1] == 0x44 && rec[2] == 3);

    /* indices with a base vertex (SetIndices), drawn indexed */
    uint32_t ibp = galloc(4); assert(M(dev, 24, 5, 6, 0, 101, 1, ibp) == 0);               /* CreateIndexBuffer(INDEX16) */
    uint32_t ib = r32(ibp); assert(M(ib, 11, 4, 0, 0, data, 0) == 0);
    uint16_t idx[3] = {0, 1, 2}; memcpy(G_MEM + r32(data), idx, 6); assert(M(ib, 12, 0) == 0);
    assert(M(dev, 85, 2, ib, 0) == 0);
    uint32_t ib2 = galloc(4), base = galloc(4); assert(M(dev, 86, 2, ib2, base) == 0 && r32(ib2) == ib && r32(base) == 0);
    ring_mark(); assert(M(dev, 71, 5, 4, 0, 3, 0, 1) == 0);                                 /* DrawIndexedPrimitive */
    assert(ring_count(DSR_DRAW, &rec) == 1 && rec[2] == 3 && rec[3] == 3);
    assert(M(dev, 85, 2, ib, 7) == 0 && M(dev, 86, 2, ib2, base) == 0 && r32(base) == 7);

    /* lights by any index (NetImmerse uses 11 to 16; only 0 to 7 were kept, and its characters drew black) */
    uint32_t lt = galloc(104), mat = galloc(68), wm = galloc(64);
    float l8[26] = {0}; uint32_t dirl = 3; l8[0] = l8[1] = l8[2] = 1; l8[17] = 1;          /* directional, white, along +z */
    memcpy(G_MEM + lt, &dirl, 4); memcpy(G_MEM + lt + 4, l8, 100);
    assert(M(dev, 44, 2, 11, lt) == 0 && M(dev, 46, 2, 11, 1) == 0);                        /* SetLight(11), LightEnable(11) */
    assert(M(dev, 47, 2, 11, v) == 0 && r32(v) != 0);                                       /* GetLightEnable */
    uint32_t lt2 = galloc(104); assert(M(dev, 45, 2, 11, lt2) == 0 && !memcmp(G_MEM + lt, G_MEM + lt2, 104));
    assert(M(dev, 45, 2, 12, lt2) != 0);                                                    /* never set: GetLight fails */
    float m8[17] = {1, 1, 1, 1}; memcpy(G_MEM + mat, m8, 68); assert(M(dev, 42, 1, mat) == 0);   /* SetMaterial: white diffuse */
    float ident[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}; memcpy(G_MEM + wm, ident, 64);
    assert(M(dev, 37, 2, 256, wm) == 0);                                                    /* SetTransform(WORLD) */
    assert(M(dev, 50, 2, 137, 1) == 0 && M(dev, 50, 2, 139, 0) == 0);                       /* LIGHTING on, no ambient */
    assert(M(dev, 76, 1, 0x12) == 0);                                                       /* XYZ | NORMAL */
    float lv[18] = {0, 0, 1, 0, 0, -1, 1, 0, 1, 0, 0, -1, 0, 1, 1, 0, 0, -1};              /* facing the light */
    uint32_t up = galloc(72); memcpy(G_MEM + up, lv, 72);
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 24) == 0);                                  /* DrawPrimitiveUP */
    assert(ring_count(DSR_DRAW, &rec) == 1 && rec[1] == 0x52 && rec[2] == 3);               /* lit: a diffuse added */
    uint32_t lit; memcpy(&lit, (const uint8_t *)(rec + 4) + 24, 4); assert(lit == 0xffffffffu);   /* fully lit, not black */
    assert(M(dev, 46, 2, 11, 0) == 0);                                                      /* LightEnable(11, off) */
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 24) == 0);
    assert(ring_count(DSR_DRAW, &rec) == 1); memcpy(&lit, (const uint8_t *)(rec + 4) + 24, 4); assert((lit & 0xffffff) == 0);
    /* NetImmerse gives each new light the next index (over 1000 in a mission): no limit on how many are kept */
    for (uint32_t k = 100; k < 400; k++) { assert(M(dev, 44, 2, k, lt) == 0 && M(dev, 46, 2, k, 1) == 0 && M(dev, 46, 2, k, 0) == 0); }
    assert(M(dev, 44, 2, 1000, lt) == 0 && M(dev, 46, 2, 1000, 1) == 0);                    /* the 302nd light */
    assert(M(dev, 47, 2, 399, v) == 0 && r32(v) == 0 && M(dev, 47, 2, 1000, v) == 0 && r32(v) != 0);
    ring_mark(); assert(M(dev, 72, 4, 4, 1, up, 24) == 0);
    assert(ring_count(DSR_DRAW, &rec) == 1); memcpy(&lit, (const uint8_t *)(rec + 4) + 24, 4); assert(lit == 0xffffffffu);
    assert(M(dev, 46, 2, 1000, 0) == 0);
    assert(M(dev, 50, 2, 137, 0) == 0);
    assert(M(dev, 35, 0) == 0);                                                             /* EndScene */

    blending_test(dev);
    texcoord_index_test(dev, tex);

    /* image surfaces and CopyRects */
    uint32_t ap = galloc(4), bp = galloc(4);
    assert(M(dev, 27, 4, 16, 16, 21, ap) == 0 && M(dev, 27, 4, 16, 16, 21, bp) == 0);      /* CreateImageSurface */
    uint32_t a = r32(ap), b = r32(bp);
    assert(M(a, 8, 1, desc) == 0 && r32(desc + 12) == 2 && r32(desc + 16) == 1024);        /* SYSTEMMEM, Size */
    assert(M(a, 9, 3, lr, 0, 0) == 0);
    for (uint32_t y = 0; y < 16; y++) for (uint32_t x = 0; x < 16; x++) rt_w32(G_MEM, r32(lr + 4) + y * r32(lr) + 4 * x, y << 8 | x);
    assert(M(a, 10, 0) == 0);
    uint32_t rect = galloc(16), pt = galloc(8); int32_t rc[4] = {2, 3, 6, 5}, at[2] = {8, 9}; memcpy(G_MEM + rect, rc, 16); memcpy(G_MEM + pt, at, 8);
    assert(M(dev, 28, 5, a, rect, 1, b, pt) == 0);                                          /* CopyRects */
    assert(M(b, 9, 3, lr, 0, 0x10) == 0);
    uint32_t bm = r32(lr + 4), bpitch = r32(lr);
    assert(r32(bm + 9 * bpitch + 4 * 8) == (3u << 8 | 2) && r32(bm + 10 * bpitch + 4 * 11) == (4u << 8 | 5) && r32(bm + 11 * bpitch + 4 * 8) == 0);
    assert(M(b, 10, 0) == 0);

    /* render targets: SetRenderTarget(0 keeps the colour target, the depth buffer goes) and the back buffer */
    uint32_t bbp = galloc(4); assert(M(dev, 16, 3, 0, 0, bbp) == 0 && r32(r32(bbp)) == vt[O9_SURF]);   /* GetBackBuffer */
    ring_mark(); assert(M(dev, 31, 2, 0, 0) == 0);
    assert(ring_count(DSR_SET_RT, &rec) >= 1 && rec[1] == 0);
    uint32_t rtp = galloc(4); assert(M(dev, 32, 1, rtp) == 0 && r32(rtp) == r32(bbp));      /* GetRenderTarget */

    /* state blocks as tokens */
    assert(M(dev, 50, 2, 137, 1) == 0);                                                     /* LIGHTING on */
    assert(M(dev, 52, 0) == 0); assert(M(dev, 50, 2, 137, 0) == 0);                         /* BeginStateBlock; LIGHTING off */
    uint32_t token = galloc(4); assert(M(dev, 53, 1, token) == 0 && r32(token));            /* EndStateBlock */
    assert(M(dev, 51, 2, 137, v) == 0 && r32(v) == 1);                                      /* recording didn't apply it */
    assert(M(dev, 54, 1, r32(token)) == 0 && M(dev, 51, 2, 137, v) == 0 && r32(v) == 0);    /* ApplyStateBlock */
    assert(M(dev, 56, 1, r32(token)) == 0);                                                 /* DeleteStateBlock */
    assert(M(dev, 50, 2, 153, 1) == 0 && M(dev, 51, 2, 153, v) == 0 && r32(v) == 0);         /* SOFTWAREVERTEXPROCESSING: only a mixed device switches */

    /* the display mode, gamma, raster status, and a frame */
    assert(M(dev, 8, 1, mode) == 0 && r32(mode + 12) == 22);
    uint32_t ramp = galloc(1536); assert(M(dev, 19, 1, ramp) == 0 && rt_r16(G_MEM, ramp + 2 * 255) == 0xffff);
    assert(M(dev, 17, 1, galloc(8)) == 0);
    ring_mark(); assert(M(dev, 15, 4, 0, 0, 0, 0) == 0);                                    /* Present */
    assert(ring_count(DSR_PRESENT, 0) == 1);
    assert(M(dev, 65, 3, 0, galloc(4), 4) == 1);                                            /* GetInfo: S_FALSE */

    /* Reset with Direct3D 8's parameters */
    p8[0] = 800; p8[1] = 600; memcpy(G_MEM + pp, p8, 52);
    assert(M(dev, 14, 1, pp) == 0);
    assert(M(dev, 16, 3, 0, 0, bbp) == 0 && M(r32(bbp), 8, 1, desc) == 0 && r32(desc + 24) == 800 && r32(desc + 28) == 600);
    printf("Direct3D 8: identifier, modes, caps, device, textures, sampler states, vertex shader handles and declarations, "
           "buffers, base vertex, lights by any index, texture coordinate sets, image surfaces and CopyRects, render targets, state blocks, Present and Reset passed\n");
    return 0;
}
