/* Direct3D 8 (Freedom Force: LoadLibrary("D3D8.DLL"), Direct3DCreate8) on the Direct3D 9 layer (d3d9.c). The objects
 * are Direct3D 9's own (one guest interface each: a vtable and the object's slot, ddraw.c make_iface); from
 * Direct3DCreate8 on, the interfaces made get Direct3D 8's vtables. Where the two versions' methods take the same
 * arguments the vtable slot is Direct3D 9's method itself; elsewhere an adapter here rewrites the arguments and calls
 * the Direct3D 9 method:
 *   - D3DPRESENT_PARAMETERS (no MultiSampleQuality), D3DCAPS8 (the first 53 DWORDs of D3DCAPS9),
 *     D3DADAPTER_IDENTIFIER8 (no DeviceName), D3DSURFACE_DESC / D3DVOLUME_DESC (a Size field);
 *   - the swap-chain argument Direct3D 9 added (GetBackBuffer, GetDisplayMode, gamma, raster status), the shared-handle
 *     argument of the Create methods, the multisample quality of render targets and depth buffers;
 *   - sampler states set as texture-stage states (D3DTSS_ADDRESSU ... D3DTSS_MAXANISOTROPY, D3DTSS_ADDRESSW);
 *   - vertex shaders as handles: an FVF code (even), or a handle from CreateVertexShader (odd) naming a declaration
 *     (D3DVSD tokens, made a Direct3D 9 vertex declaration), an optional shader and the constants the declaration loads;
 *   - SetIndices' base vertex index, which Direct3D 9 takes in DrawIndexedPrimitive;
 *   - state blocks as DWORD tokens; CreateImageSurface (a system-memory surface); CopyRects; GetFrontBuffer.
 * The device reports no vertex or pixel shader support unless D3D8_SHADERS=1, so that the engine (NetImmerse 4,
 * NiDX8) takes its fixed-function paths; Direct3D 9's shader path runs D3D9 bytecode, and Direct3D 8 shaders have no
 * dcl instructions (verify before turning it on). D3D9_LOG=1 logs the Direct3D 9 methods as they are reached. */
#include "d3d9_priv.h"
#include <pthread.h>

typedef void (*Fn)(Ctx *);
#define F9(type, slot) d9_method(type, slot)

/* ---- calling a Direct3D 9 method with other arguments: they are pushed below the caller's stack (with a dummy
 * return address); the stdcall method pops them ---- */
static uint32_t call9(Ctx *c, Fn fn, int n, const uint32_t *args)
{
    uint32_t esp = c->esp;
    for (int k = n - 1; k >= 0; k--) { c->esp -= 4; rt_w32(G_MEM, c->esp, args[k]); }
    c->esp -= 4; rt_w32(G_MEM, c->esp, 0);
    fn(c);
    c->esp = esp;
    return c->eax;
}
#define CALL9(type, slot, ...) call9(c, F9(type, slot), (int)(sizeof (uint32_t[]){__VA_ARGS__} / 4), (uint32_t[]){__VA_ARGS__})
/* scratch guest memory for converted structures: well below the arguments call9 pushes (the caller's stack) */
static uint32_t scratch(Ctx *c, uint32_t n) { return ((c->esp - 0x200u - n) & ~15u); }

static int d8_log = -1;
/* D3D8_LOG=1: each method's first 3 calls; D3D8_LOG=<n>: its first n */
static int log8(void) { if (d8_log < 0) { const char *e = getenv("D3D8_LOG"); d8_log = e ? (atoi(e) > 1 ? atoi(e) : 3) : 0; } return d8_log; }
#define A(name, n) static void name(Ctx *c) { enum { nargs_ = n }; (void)nargs_; \
    { static int calls_; if (log8() && calls_++ < log8()) fprintf(stderr, "d3d8: %s(%08x %08x %08x %08x %08x)\n", #name, ARG(1), ARG(2), ARG(3), ARG(4), ARG(5)); }
#define END8 }
#define RET9(v) RET(v, nargs_)

/* ---- pure conversions (tests/d3d8_test.c) ---- */
/* D3DPRESENT_PARAMETERS: Direct3D 8's 13 DWORDs -> Direct3D 9's 14 (MultiSampleQuality 0 after MultiSampleType);
 * D3DSWAPEFFECT_COPY_VSYNC (4) is COPY in Direct3D 9 */
void d8_pp_to9(const uint32_t p8[13], uint32_t p9[14])
{
    for (int k = 0; k < 5; k++) p9[k] = p8[k];
    p9[5] = 0;
    for (int k = 5; k < 13; k++) p9[k + 1] = p8[k];
    if (p9[6] == 4) p9[6] = 3;
}
void d8_pp_from9(const uint32_t p9[14], uint32_t p8[13], uint32_t swap8)   /* what the device filled in (sizes, format) */
{
    for (int k = 0; k < 5; k++) p8[k] = p9[k];
    for (int k = 5; k < 13; k++) p8[k] = p9[k + 1];
    p8[5] = swap8;
}
/* D3DSURFACE_DESC: Direct3D 9's {Format, Type, Usage, Pool, MultiSampleType, MultiSampleQuality, Width, Height} ->
 * Direct3D 8's {Format, Type, Usage, Pool, Size, MultiSampleType, Width, Height} */
void d8_surface_desc(const uint32_t d9[8], uint32_t d8[8])
{
    d8[0] = d9[0]; d8[1] = d9[1]; d8[2] = d9[2]; d8[3] = d9[3];
    d8[4] = d9_size(d9[0], d9[6], d9[7]); d8[5] = d9[4]; d8[6] = d9[6]; d8[7] = d9[7];
}
/* D3DVOLUME_DESC: {Format, Type, Usage, Pool, Width, Height, Depth} -> Direct3D 8's, with Size after Pool */
void d8_volume_desc(const uint32_t d9[7], uint32_t d8[8])
{
    for (int k = 0; k < 4; k++) d8[k] = d9[k];
    d8[4] = d9_size(d9[0], d9[4], d9[5]) * d9[6]; d8[5] = d9[4]; d8[6] = d9[5]; d8[7] = d9[6];
}
/* D3DCAPS8 is D3DCAPS9's first 53 DWORDs (to PixelShader1xMaxValue). Shader versions are taken away unless asked for. */
void d8_caps(const uint32_t c9[76], uint32_t c8[53], int shaders)
{
    memcpy(c8, c9, 53 * 4);
    if (!shaders) { c8[49] = 0xfffe0000u; c8[50] = 0; c8[51] = 0xffff0000u; c8[52] = 0; }   /* vs_0_0, ps_0_0 */
}
/* D3DADAPTER_IDENTIFIER8: Driver[512], Description[512], then DriverVersion (8 bytes), VendorId, DeviceId, SubSysId,
 * Revision, DeviceIdentifier (GUID), WHQLLevel: Direct3D 9's without DeviceName[32] */
void d8_identifier(const uint8_t *i9, uint8_t *i8)
{
    memcpy(i8, i9, 1024);
    memcpy(i8 + 1024, i9 + 1056, 1068 - 1024);
}
/* sampler states Direct3D 8 sets as texture-stage states: D3DTSS_* -> D3DSAMP_* (0: a texture-stage state) */
int d8_tss_sampler(uint32_t tss)
{
    switch (tss) {
    case 13: return 1; case 14: return 2; case 25: return 3; case 15: return 4; case 16: return 5; case 17: return 6;
    case 18: return 7; case 19: return 8; case 20: return 9; case 21: return 10;
    }
    return 0;
}
/* a vertex shader declaration (D3DVSD tokens) -> D3DVERTEXELEMENT9s (8 bytes each, D3DDECL_END last) in out[] (room
 * for 64), and the constants it loads (D3DVSD_CONST: up to 96 registers) in consts[] as (register, 4 floats) runs.
 * Input registers name the fixed-function data: D3DVSDE_POSITION 0, BLENDWEIGHT 1, BLENDINDICES 2, NORMAL 3, PSIZE 4,
 * DIFFUSE 5, SPECULAR 6, TEXCOORD0-7 7-14, POSITION2 15, NORMAL2 16. Returns the number of elements, -1 if malformed.
 * *ntok gets the declaration's length in tokens, D3DVSD_END included. */
int d8_decl_to9(const uint32_t *t, int max_tokens, uint8_t out[65][8], uint32_t consts[][5], int *nconsts, int *ntok)
{
    static const uint8_t usage[17][2] = {{0, 0}, {1, 0}, {2, 0}, {3, 0}, {4, 0}, {10, 0}, {10, 1}, {5, 0}, {5, 1}, {5, 2}, {5, 3},
                                         {5, 4}, {5, 5}, {5, 6}, {5, 7}, {0, 1}, {3, 1}};
    static const uint8_t size[8] = {4, 8, 12, 16, 4, 4, 4, 8};
    int n = 0, k = 0; uint32_t stream = 0, off = 0; *nconsts = 0;
    for (;;) {
        if (k >= max_tokens) return -1;
        uint32_t v = t[k++];
        if (v == 0xffffffffu) break;                             /* D3DVSD_END */
        switch (v >> 29) {
        case 0: break;                                           /* D3DVSD_NOP */
        case 1: stream = v & 0xf; off = 0; break;                /* D3DVSD_STREAM(n) (tessellator streams: bit 28) */
        case 2:
            if (v & 0x10000000u) { off += 4 * ((v >> 16) & 0xf); break; }   /* D3DVSD_SKIP(n DWORDs) */
            {
                uint32_t type = (v >> 16) & 0xf, reg = v & 0x1f;
                if (type > 7 || reg > 16 || n >= 64) return -1;
                uint8_t *e = out[n++];
                e[0] = (uint8_t)stream; e[1] = 0; e[2] = (uint8_t)off; e[3] = (uint8_t)(off >> 8);
                e[4] = (uint8_t)type; e[5] = 0; e[6] = usage[reg][0]; e[7] = usage[reg][1];
                off += size[type];
            }
            break;
        case 3: break;                                           /* D3DVSD_TESSNORMAL / TESSUV: no tessellation */
        case 4: {                                                /* D3DVSD_CONST(address, count) then count x 4 DWORDs */
            uint32_t count = (v >> 25) & 0xf, addr = v & 0x7f;
            if (k + 4 * (int)count > max_tokens) return -1;
            for (uint32_t r = 0; r < count; r++) {
                if (*nconsts < 96) { consts[*nconsts][0] = addr + r; memcpy(&consts[*nconsts][1], &t[k + 4 * (int)r], 16); (*nconsts)++; }
            }
            k += 4 * (int)count; break;
        }
        case 5: k += (int)((v >> 24) & 0x1f); break;             /* D3DVSD_EXT: data to skip */
        default: return -1;
        }
    }
    uint8_t *e = out[n]; e[0] = 0xff; e[1] = 0; e[2] = e[3] = 0; e[4] = 17; e[5] = e[6] = e[7] = 0;   /* D3DDECL_END */
    *ntok = k;
    return n;
}

/* ---- per-device Direct3D 8 state ---- */
typedef struct VS8 { int used; uint32_t decl, vs; uint32_t (*consts)[5]; int nconsts; uint32_t *dtok, ndtok, *ftok, nftok; } VS8;
#define NVS8 4096
static VS8 vs8[NVS8];
static uint32_t base_vertex, cur_vs;
static pthread_mutex_t vs_lock = PTHREAD_MUTEX_INITIALIZER;
static int shaders_on(void) { static int v = -1; if (v < 0) v = getenv("D3D8_SHADERS") && atoi(getenv("D3D8_SHADERS")); return v; }

/* ---- IDirect3D8 ---- */
A(i8_GetAdapterIdentifier, 4)                          /* (adapter, flags, D3DADAPTER_IDENTIFIER8 *) */
    uint32_t s = scratch(c, 1104), out = ARG(3), a = ARG(1), f = ARG(2);
    uint32_t r = CALL9(O9_D3D, 5, ARG(0), a, f, s);
    if (!r) d8_identifier(GP(s), GP(out));
    RET9(r);
END8
A(i8_GetAdapterModeCount, 2) RET9(CALL9(O9_D3D, 6, ARG(0), ARG(1), 22)); END8                 /* X8R8G8B8 modes */
A(i8_EnumAdapterModes, 4) RET9(CALL9(O9_D3D, 7, ARG(0), ARG(1), 22, ARG(2), ARG(3))); END8    /* (adapter, index, mode *) */
A(i8_CheckDeviceMultiSampleType, 6) RET9(CALL9(O9_D3D, 11, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), 0)); END8
A(i8_GetDeviceCaps, 4)                                 /* (adapter, device type, D3DCAPS8 *) */
    uint32_t s = scratch(c, 304), out = ARG(3), a = ARG(1), t = ARG(2);
    uint32_t r = CALL9(O9_D3D, 14, ARG(0), a, t, s);
    if (!r) d8_caps((const uint32_t *)GP(s), (uint32_t *)GP(out), shaders_on());
    RET9(r);
END8
A(i8_CreateDevice, 7)                                  /* (adapter, type, focus window, behaviour, D3DPRESENT_PARAMETERS8 *, device **) */
    uint32_t pp8 = ARG(5), s = scratch(c, 56); uint32_t p8[13], p9[14];
    memcpy(p8, GP(pp8), 52); d8_pp_to9(p8, p9); memcpy(GP(s), p9, 56);
    uint32_t a1 = ARG(1), a2 = ARG(2), a3 = ARG(3), a4 = ARG(4), out = ARG(6);
    uint32_t r = CALL9(O9_D3D, 16, ARG(0), a1, a2, a3, a4, s, out);
    if (!r) { memcpy(p9, GP(s), 56); d8_pp_from9(p9, p8, p8[5]); memcpy(GP(pp8), p8, 52); base_vertex = 0; cur_vs = 0; }
    RET9(r);
END8

/* ---- IDirect3DDevice8 ---- */
A(dv8_ResourceManagerDiscardBytes, 2) RET9(CALL9(O9_DEV, 5, ARG(0))); END8
A(dv8_GetDeviceCaps, 2)
    uint32_t s = scratch(c, 304), out = ARG(1); uint32_t r = CALL9(O9_DEV, 7, ARG(0), s);
    if (!r) d8_caps((const uint32_t *)GP(s), (uint32_t *)GP(out), shaders_on());
    RET9(r);
END8
A(dv8_GetDisplayMode, 2) RET9(CALL9(O9_DEV, 8, ARG(0), 0, ARG(1))); END8
static uint32_t with_pp(Ctx *c, uint32_t pp8, int slot, uint32_t extra)   /* Reset (pp) or CreateAdditionalSwapChain (pp, out) */
{
    uint32_t s = scratch(c, 56); uint32_t p8[13], p9[14];
    memcpy(p8, GP(pp8), 52); d8_pp_to9(p8, p9); memcpy(GP(s), p9, 56);
    uint32_t r = slot == 16 ? CALL9(O9_DEV, 16, ARG(0), s) : CALL9(O9_DEV, 13, ARG(0), s, extra);
    if (!r) { memcpy(p9, GP(s), 56); d8_pp_from9(p9, p8, p8[5]); memcpy(GP(pp8), p8, 52); }
    return r;
}
A(dv8_CreateAdditionalSwapChain, 3) RET9(with_pp(c, ARG(1), 13, ARG(2))); END8
A(dv8_Reset, 2) uint32_t r = with_pp(c, ARG(1), 16, 0); if (!r) { base_vertex = 0; cur_vs = 0; } RET9(r); END8
A(dv8_GetBackBuffer, 4) RET9(CALL9(O9_DEV, 18, ARG(0), 0, ARG(1), ARG(2), ARG(3))); END8        /* (index, type, surface **) */
A(dv8_GetRasterStatus, 2) RET9(CALL9(O9_DEV, 19, ARG(0), 0, ARG(1))); END8
A(dv8_SetGammaRamp, 3) RET9(CALL9(O9_DEV, 21, ARG(0), 0, ARG(1), ARG(2))); END8
A(dv8_GetGammaRamp, 2) RET9(CALL9(O9_DEV, 22, ARG(0), 0, ARG(1))); END8
A(dv8_CreateTexture, 8) RET9(CALL9(O9_DEV, 23, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), ARG(6), ARG(7), 0)); END8
A(dv8_CreateVolumeTexture, 9) RET9(CALL9(O9_DEV, 24, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), ARG(6), ARG(7), ARG(8), 0)); END8
A(dv8_CreateCubeTexture, 7) RET9(CALL9(O9_DEV, 25, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), ARG(6), 0)); END8
A(dv8_CreateVertexBuffer, 6) RET9(CALL9(O9_DEV, 26, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), 0)); END8
A(dv8_CreateIndexBuffer, 6) RET9(CALL9(O9_DEV, 27, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), 0)); END8
A(dv8_CreateRenderTarget, 7)                           /* (w, h, format, multisample, lockable, surface **) */
    RET9(CALL9(O9_DEV, 28, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), 0, ARG(5), ARG(6), 0));
END8
A(dv8_CreateDepthStencilSurface, 6)                    /* (w, h, format, multisample, surface **) */
    RET9(CALL9(O9_DEV, 29, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), 0, 0, ARG(5), 0));
END8
A(dv8_CreateImageSurface, 5)                           /* (w, h, format, surface **): lockable, in system memory */
    RET9(CALL9(O9_DEV, 36, ARG(0), ARG(1), ARG(2), ARG(3), 2, ARG(4), 0));
END8
/* CopyRects(src, rects, n, dst, points): rectangles of one surface copied into another of the same format, at the
 * given points (none: the same place); n 0 copies the whole surface. Through the surfaces' locks, so render targets
 * are read back first and the destination is sent to the renderer after. */
A(dv8_CopyRects, 6)
    Surf9 *s = obj(ARG(1), O9_SURF), *t = obj(ARG(4), O9_SURF);
    if (!s || !t || s->fmt != t->fmt) RET9(D3DERR_INVALIDCALL);
    uint32_t rects = ARG(2), n = ARG(3), points = ARG(5), lk = scratch(c, 16);
    int bpp = d9_fmt_bytes(s->fmt), blk = d9_fmt_block(s->fmt);
    if (!bpp && !blk) RET9(D3DERR_INVALIDCALL);
    if (d9_surf_lock(s, lk, 0, LOCK_READONLY)) RET9(D3DERR_INVALIDCALL);
    uint32_t sp = rt_r32(G_MEM, lk), sm = rt_r32(G_MEM, lk + 4);
    if (d9_surf_lock(t, lk, 0, 0)) { d9_surf_unlock(s); RET9(D3DERR_INVALIDCALL); }
    uint32_t tp = rt_r32(G_MEM, lk), tm = rt_r32(G_MEM, lk + 4);
    for (uint32_t k = 0; k < (n ? n : 1); k++) {
        int32_t r[4] = {0, 0, (int32_t)s->w, (int32_t)s->h}, at[2];
        if (n && rects) memcpy(r, GP(rects + 16 * k), 16);
        if (n && points) memcpy(at, GP(points + 8 * k), 8); else { at[0] = r[0]; at[1] = r[1]; }
        if (r[0] < 0 || r[1] < 0 || r[2] > (int32_t)s->w || r[3] > (int32_t)s->h || r[2] <= r[0] || r[3] <= r[1]) continue;
        int32_t w = r[2] - r[0], h = r[3] - r[1];
        if (at[0] < 0 || at[1] < 0 || at[0] + w > (int32_t)t->w || at[1] + h > (int32_t)t->h) continue;
        uint32_t unit = blk ? 4u : 1u, bytes = blk ? (uint32_t)blk : (uint32_t)bpp;   /* block formats: 4x4 blocks */
        uint32_t rows = ((uint32_t)h + unit - 1) / unit, row = ((uint32_t)w + unit - 1) / unit * bytes;
        for (uint32_t y = 0; y < rows; y++)
            memmove(GP(tm + ((uint32_t)at[1] / unit + y) * tp + (uint32_t)at[0] / unit * bytes),
                    GP(sm + ((uint32_t)r[1] / unit + y) * sp + (uint32_t)r[0] / unit * bytes), row);
    }
    d9_surf_unlock(s); d9_surf_unlock(t);
    RET9(D3D_OK);
END8
A(dv8_GetFrontBuffer, 2) RET9(CALL9(O9_DEV, 33, ARG(0), 0, ARG(1))); END8
A(dv8_SetRenderTarget, 3)                              /* (render target or 0 to keep it, depth buffer or 0 for none) */
    uint32_t dev = ARG(0), ds = ARG(2), r = 0;
    if (ARG(1)) r = CALL9(O9_DEV, 37, dev, 0, ARG(1));
    if (!r) r = CALL9(O9_DEV, 39, dev, ds);
    RET9(r);
END8
A(dv8_GetRenderTarget, 2) RET9(CALL9(O9_DEV, 38, ARG(0), 0, ARG(1))); END8
A(dv8_SetRenderState, 3)
    if (ARG(1) == 47) {                                                 /* D3DRS_ZBIAS (Direct3D 8, 0..16): n units of 24-bit depth towards the camera, as the D3D9 DEPTHBIAS float */
        float f = -(float)(int32_t)ARG(2) / 16777216.0f; uint32_t u; memcpy(&u, &f, 4);
        RET9(CALL9(O9_DEV, 57, ARG(0), 195, u));
    }
    if (ARG(1) == 153) RET9(CALL9(O9_DEV, 77, ARG(0), ARG(2)));        /* D3DRS_SOFTWAREVERTEXPROCESSING */
    RET9(CALL9(O9_DEV, 57, ARG(0), ARG(1), ARG(2)));                    /* the rest: the renderer's (Direct3D 7) numbering */
END8
A(dv8_GetRenderState, 3)
    if (ARG(1) == 47) {                                                 /* the inverse of SetRenderState's ZBIAS translation */
        uint32_t s = scratch(c, 4); CALL9(O9_DEV, 58, ARG(0), 195, s); uint32_t u = rt_r32(G_MEM, s); float f; memcpy(&f, &u, 4);
        float n = -f * 16777216.0f; rt_w32(G_MEM, ARG(2), (uint32_t)(int32_t)(n + (n < 0 ? -0.5f : 0.5f))); RET9(D3D_OK);
    }
    if (ARG(1) == 153) { uint32_t out = ARG(2); rt_w32(G_MEM, out, CALL9(O9_DEV, 78, ARG(0))); RET9(D3D_OK); }
    RET9(CALL9(O9_DEV, 58, ARG(0), ARG(1), ARG(2)));
END8
/* state blocks: the token is the IDirect3DStateBlock9 */
A(dv8_EndStateBlock, 2) RET9(CALL9(O9_DEV, 61, ARG(0), ARG(1))); END8
A(dv8_ApplyStateBlock, 2) RET9(ARG(1) ? CALL9(O9_SB, 5, ARG(1)) : D3DERR_INVALIDCALL); END8
A(dv8_CaptureStateBlock, 2) RET9(ARG(1) ? CALL9(O9_SB, 4, ARG(1)) : D3DERR_INVALIDCALL); END8
A(dv8_DeleteStateBlock, 2) if (ARG(1)) CALL9(O9_SB, 2, ARG(1)); RET9(D3D_OK); END8
A(dv8_CreateStateBlock, 3) RET9(CALL9(O9_DEV, 59, ARG(0), ARG(1), ARG(2))); END8
A(dv8_GetTextureStageState, 4)
    int smp = d8_tss_sampler(ARG(2));
    RET9(smp ? CALL9(O9_DEV, 68, ARG(0), ARG(1), (uint32_t)smp, ARG(3)) : CALL9(O9_DEV, 66, ARG(0), ARG(1), ARG(2), ARG(3)));
END8
A(dv8_SetTextureStageState, 4)
    int smp = d8_tss_sampler(ARG(2));
    RET9(smp ? CALL9(O9_DEV, 69, ARG(0), ARG(1), (uint32_t)smp, ARG(3)) : CALL9(O9_DEV, 67, ARG(0), ARG(1), ARG(2), ARG(3)));
END8
A(dv8_GetInfo, 4) RET9(S_FALSE_); END8                 /* no device information queries */
A(dv8_DrawIndexedPrimitive, 6)                         /* (type, min index, vertices, start index, primitives): SetIndices' base */
    RET9(CALL9(O9_DEV, 82, ARG(0), ARG(1), base_vertex, ARG(2), ARG(3), ARG(4), ARG(5)));
END8
A(dv8_ProcessVertices, 6) RET9(CALL9(O9_DEV, 85, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), 0, ARG(5))); END8

/* vertex shaders */
static uint32_t handle_of(int k) { return (uint32_t)k << 1 | 1u; }
static VS8 *vs_of(uint32_t h) { uint32_t k = h >> 1; return (h & 1) && k > 0 && k < NVS8 && vs8[k].used ? &vs8[k] : 0; }
A(dv8_CreateVertexShader, 5)                           /* (declaration, function or 0, handle *, usage) */
    uint32_t dev = ARG(0), decl = ARG(1), fn = ARG(2), out = ARG(3);
    uint8_t el[65][8]; uint32_t (*consts)[5] = calloc(96, sizeof *consts); int nconsts = 0, ntok = 0;
    int n = decl ? d8_decl_to9((const uint32_t *)GP(decl), 4096, el, consts, &nconsts, &ntok) : -1;
    if (n < 0) { free(consts); fprintf(stderr, "d3d8: CreateVertexShader: declaration not understood\n"); RET9(D3DERR_INVALIDCALL); }
    uint32_t s = scratch(c, 8 * 65 + 16); memcpy(GP(s), el, 8 * (size_t)(n + 1));
    uint32_t r = CALL9(O9_DEV, 86, dev, s, s + 8 * 65);
    if (r) { free(consts); RET9(r); }
    uint32_t d9decl = rt_r32(G_MEM, s + 8 * 65), d9vs = 0;
    if (fn) {
        r = CALL9(O9_DEV, 91, dev, fn, s + 8 * 65);
        if (r) { CALL9(O9_DECL, 2, d9decl); free(consts); RET9(r); }
        d9vs = rt_r32(G_MEM, s + 8 * 65);
    }
    pthread_mutex_lock(&vs_lock);
    int k = 1; while (k < NVS8 && vs8[k].used) k++;
    if (k == NVS8) { pthread_mutex_unlock(&vs_lock); free(consts); RET9(D3DERR_INVALIDCALL); }
    VS8 *v = &vs8[k]; memset(v, 0, sizeof *v); v->used = 1; v->decl = d9decl; v->vs = d9vs; v->consts = consts; v->nconsts = nconsts;
    v->ndtok = (uint32_t)ntok; v->dtok = malloc(4u * v->ndtok); memcpy(v->dtok, GP(decl), 4u * v->ndtok);
    if (fn) { uint32_t len = 0; while (len < 65536 && rt_r32(G_MEM, fn + 4 * len) != 0x0000ffffu) len++; v->nftok = len + 1; v->ftok = malloc(4u * v->nftok); memcpy(v->ftok, GP(fn), 4u * v->nftok); }
    pthread_mutex_unlock(&vs_lock);
    rt_w32(G_MEM, out, handle_of(k));
    if (log8()) fprintf(stderr, "d3d8: vertex shader %u: %d elements, %d constants, %s\n", handle_of(k), n, nconsts, fn ? "programmable" : "fixed function");
    RET9(D3D_OK);
END8
A(dv8_SetVertexShader, 2)                              /* an FVF code (even) or a CreateVertexShader handle (odd) */
    uint32_t dev = ARG(0), h = ARG(1);
    if (!(h & 1)) { CALL9(O9_DEV, 92, dev, 0); cur_vs = h; RET9(CALL9(O9_DEV, 89, dev, h)); }
    VS8 *v = vs_of(h); if (!v) RET9(D3DERR_INVALIDCALL);
    CALL9(O9_DEV, 87, dev, v->decl); CALL9(O9_DEV, 92, dev, v->vs);
    for (int k = 0; k < v->nconsts; k++) {
        uint32_t s = scratch(c, 16); memcpy(GP(s), &v->consts[k][1], 16); CALL9(O9_DEV, 94, dev, v->consts[k][0], s, 1);
    }
    cur_vs = h; RET9(D3D_OK);
END8
A(dv8_GetVertexShader, 2) rt_w32(G_MEM, ARG(1), cur_vs); RET9(D3D_OK); END8
A(dv8_DeleteVertexShader, 2)
    VS8 *v = vs_of(ARG(1)); if (!v) RET9(D3DERR_INVALIDCALL);
    uint32_t decl = v->decl, vs = v->vs;
    pthread_mutex_lock(&vs_lock); free(v->consts); free(v->dtok); free(v->ftok); memset(v, 0, sizeof *v); pthread_mutex_unlock(&vs_lock);
    if (cur_vs == ARG(1)) cur_vs = 0;
    CALL9(O9_DECL, 2, decl); if (vs) CALL9(O9_VS, 2, vs);
    RET9(D3D_OK);
END8
A(dv8_SetVertexShaderConstant, 4) RET9(CALL9(O9_DEV, 94, ARG(0), ARG(1), ARG(2), ARG(3))); END8
A(dv8_GetVertexShaderConstant, 4) RET9(CALL9(O9_DEV, 95, ARG(0), ARG(1), ARG(2), ARG(3))); END8
static uint32_t tokens_out(uint32_t *tok, uint32_t n, uint32_t data, uint32_t size)   /* (data or 0, in/out byte size) */
{
    uint32_t have = rt_r32(G_MEM, size); rt_w32(G_MEM, size, 4 * n);
    if (!data) return D3D_OK;
    if (have < 4 * n) return D3DERR_INVALIDCALL;
    memcpy(GP(data), tok, 4 * n); return D3D_OK;
}
A(dv8_GetVertexShaderDeclaration, 4) VS8 *v = vs_of(ARG(1)); RET9(v ? tokens_out(v->dtok, v->ndtok, ARG(2), ARG(3)) : D3DERR_INVALIDCALL); END8
A(dv8_GetVertexShaderFunction, 4) VS8 *v = vs_of(ARG(1)); RET9(v && v->ftok ? tokens_out(v->ftok, v->nftok, ARG(2), ARG(3)) : D3DERR_INVALIDCALL); END8
A(dv8_SetStreamSource, 4) RET9(CALL9(O9_DEV, 100, ARG(0), ARG(1), ARG(2), 0, ARG(3))); END8   /* (stream, buffer, stride) */
A(dv8_GetStreamSource, 4) uint32_t s = scratch(c, 4); RET9(CALL9(O9_DEV, 101, ARG(0), ARG(1), ARG(2), s, ARG(3))); END8
A(dv8_SetIndices, 3) uint32_t r = CALL9(O9_DEV, 104, ARG(0), ARG(1)); if (!r) base_vertex = ARG(2); RET9(r); END8
A(dv8_GetIndices, 3) uint32_t out = ARG(2), r = CALL9(O9_DEV, 105, ARG(0), ARG(1)); if (!r && out) rt_w32(G_MEM, out, base_vertex); RET9(r); END8
/* pixel shaders: the handle is the IDirect3DPixelShader9 */
A(dv8_CreatePixelShader, 3) RET9(CALL9(O9_DEV, 106, ARG(0), ARG(1), ARG(2))); END8
A(dv8_SetPixelShader, 2) RET9(CALL9(O9_DEV, 107, ARG(0), ARG(1))); END8
A(dv8_GetPixelShader, 2)
    uint32_t out = ARG(1), r = CALL9(O9_DEV, 108, ARG(0), out);
    if (!r && rt_r32(G_MEM, out)) CALL9(O9_PS, 2, rt_r32(G_MEM, out));   /* a handle: no reference kept */
    RET9(r);
END8
A(dv8_DeletePixelShader, 2) if (ARG(1)) CALL9(O9_PS, 2, ARG(1)); RET9(D3D_OK); END8
A(dv8_SetPixelShaderConstant, 4) RET9(CALL9(O9_DEV, 109, ARG(0), ARG(1), ARG(2), ARG(3))); END8
A(dv8_GetPixelShaderConstant, 4) RET9(CALL9(O9_DEV, 110, ARG(0), ARG(1), ARG(2), ARG(3))); END8
A(dv8_GetPixelShaderFunction, 4) RET9(ARG(1) ? CALL9(O9_PS, 4, ARG(1), ARG(2), ARG(3)) : D3DERR_INVALIDCALL); END8

/* ---- surfaces, textures, volumes: descriptions with a Size ---- */
A(sf8_GetDesc, 2)
    uint32_t s = scratch(c, 32), out = ARG(1), r = CALL9(O9_SURF, 12, ARG(0), s);
    if (!r) d8_surface_desc((const uint32_t *)GP(s), (uint32_t *)GP(out));
    RET9(r);
END8
static uint32_t level_desc(Ctx *c, int type, uint32_t level, uint32_t out)
{
    uint32_t s = scratch(c, 32), r = CALL9(type, 17, ARG(0), level, s);
    if (r) return r;
    if (type == O9_VOLTEX) d8_volume_desc((const uint32_t *)GP(s), (uint32_t *)GP(out));
    else d8_surface_desc((const uint32_t *)GP(s), (uint32_t *)GP(out));
    return D3D_OK;
}
A(tx8_GetLevelDesc, 3) RET9(level_desc(c, O9_TEX, ARG(1), ARG(2))); END8
A(cb8_GetLevelDesc, 3) RET9(level_desc(c, O9_CUBE, ARG(1), ARG(2))); END8
A(vt8_GetLevelDesc, 3) RET9(level_desc(c, O9_VOLTEX, ARG(1), ARG(2))); END8

/* ---- vtables (Direct3D 8's method order) ---- */
static uint32_t vtable8(const char *iface, const Fn *fns, int n)
{
    uint32_t t = heap_alloc(w32_process_heap, 8, 4u * (uint32_t)n);
    for (int k = 0; k < n; k++) {
        char nm[96]; snprintf(nm, sizeof nm, "d3d8!%s.%d", iface, k);
        if (!fns[k]) { fprintf(stderr, "d3d8: %s method %d missing\n", iface, k); abort(); }
        rt_w32(G_MEM, t + 4u * (uint32_t)k, w32_thunk_register(nm, fns[k]));
    }
    return t;
}
#define D(slot) F9(O9_DEV, slot)
static void init_vtables8(void)
{
    const Fn d3d[] = { F9(O9_D3D, 0), F9(O9_D3D, 1), F9(O9_D3D, 2), F9(O9_D3D, 3), F9(O9_D3D, 4), i8_GetAdapterIdentifier,
        i8_GetAdapterModeCount, i8_EnumAdapterModes, F9(O9_D3D, 8), F9(O9_D3D, 9), F9(O9_D3D, 10), i8_CheckDeviceMultiSampleType,
        F9(O9_D3D, 12), i8_GetDeviceCaps, F9(O9_D3D, 15), i8_CreateDevice };
    const Fn dev[] = {
        D(0), D(1), D(2), D(3), D(4), dv8_ResourceManagerDiscardBytes, D(6), dv8_GetDeviceCaps, dv8_GetDisplayMode, D(9),
        D(10), D(11), D(12), dv8_CreateAdditionalSwapChain, dv8_Reset, D(17), dv8_GetBackBuffer, dv8_GetRasterStatus,
        dv8_SetGammaRamp, dv8_GetGammaRamp, dv8_CreateTexture, dv8_CreateVolumeTexture, dv8_CreateCubeTexture,
        dv8_CreateVertexBuffer, dv8_CreateIndexBuffer, dv8_CreateRenderTarget, dv8_CreateDepthStencilSurface,
        dv8_CreateImageSurface, dv8_CopyRects, D(31), dv8_GetFrontBuffer, dv8_SetRenderTarget, dv8_GetRenderTarget, D(40),
        D(41), D(42), D(43), D(44), D(45), D(46), D(47), D(48), D(49), D(50), D(51), D(52), D(53), D(54), D(55), D(56),
        dv8_SetRenderState, dv8_GetRenderState, D(60), dv8_EndStateBlock, dv8_ApplyStateBlock, dv8_CaptureStateBlock,
        dv8_DeleteStateBlock, dv8_CreateStateBlock, D(62), D(63), D(64), D(65), dv8_GetTextureStageState,
        dv8_SetTextureStageState, D(70), dv8_GetInfo, D(71), D(72), D(73), D(74), D(81), dv8_DrawIndexedPrimitive, D(83),
        D(84), dv8_ProcessVertices, dv8_CreateVertexShader, dv8_SetVertexShader, dv8_GetVertexShader, dv8_DeleteVertexShader,
        dv8_SetVertexShaderConstant, dv8_GetVertexShaderConstant, dv8_GetVertexShaderDeclaration, dv8_GetVertexShaderFunction,
        dv8_SetStreamSource, dv8_GetStreamSource, dv8_SetIndices, dv8_GetIndices, dv8_CreatePixelShader, dv8_SetPixelShader,
        dv8_GetPixelShader, dv8_DeletePixelShader, dv8_SetPixelShaderConstant, dv8_GetPixelShaderConstant,
        dv8_GetPixelShaderFunction, D(115), D(116), D(117) };
    const Fn surf[] = { F9(O9_SURF, 0), F9(O9_SURF, 1), F9(O9_SURF, 2), F9(O9_SURF, 3), F9(O9_SURF, 4), F9(O9_SURF, 5),
        F9(O9_SURF, 6), F9(O9_SURF, 11), sf8_GetDesc, F9(O9_SURF, 13), F9(O9_SURF, 14) };
#define BASE8(t) F9(t, 0), F9(t, 1), F9(t, 2), F9(t, 3), F9(t, 4), F9(t, 5), F9(t, 6), F9(t, 7), F9(t, 8), F9(t, 9), F9(t, 10), \
        F9(t, 11), F9(t, 12), F9(t, 13)
    const Fn tex[] = { BASE8(O9_TEX), tx8_GetLevelDesc, F9(O9_TEX, 18), F9(O9_TEX, 19), F9(O9_TEX, 20), F9(O9_TEX, 21) };
    const Fn cube[] = { BASE8(O9_CUBE), cb8_GetLevelDesc, F9(O9_CUBE, 18), F9(O9_CUBE, 19), F9(O9_CUBE, 20), F9(O9_CUBE, 21) };
    const Fn vol[] = { BASE8(O9_VOLTEX), vt8_GetLevelDesc, F9(O9_VOLTEX, 18), F9(O9_VOLTEX, 19), F9(O9_VOLTEX, 20), F9(O9_VOLTEX, 21) };
    const Fn vb[] = { F9(O9_VB, 0), F9(O9_VB, 1), F9(O9_VB, 2), F9(O9_VB, 3), F9(O9_VB, 4), F9(O9_VB, 5), F9(O9_VB, 6), F9(O9_VB, 7),
        F9(O9_VB, 8), F9(O9_VB, 9), F9(O9_VB, 10), F9(O9_VB, 11), F9(O9_VB, 12), F9(O9_VB, 13) };
    const Fn swap[] = { F9(O9_SWAP, 0), F9(O9_SWAP, 1), F9(O9_SWAP, 2), F9(O9_SWAP, 3), F9(O9_SWAP, 5) };
    _Static_assert(sizeof d3d / sizeof *d3d == 16 && sizeof dev / sizeof *dev == 97 && sizeof surf / sizeof *surf == 11 &&
                   sizeof tex / sizeof *tex == 19 && sizeof cube / sizeof *cube == 19 && sizeof vol / sizeof *vol == 19 &&
                   sizeof vb / sizeof *vb == 14 && sizeof swap / sizeof *swap == 5, "d3d8 vtable sizes");
    vt[O9_D3D] = vtable8("IDirect3D8", d3d, 16); vt[O9_DEV] = vtable8("IDirect3DDevice8", dev, 97);
    vt[O9_SURF] = vtable8("IDirect3DSurface8", surf, 11); vt[O9_TEX] = vtable8("IDirect3DTexture8", tex, 19);
    vt[O9_CUBE] = vtable8("IDirect3DCubeTexture8", cube, 19); vt[O9_VOLTEX] = vtable8("IDirect3DVolumeTexture8", vol, 19);
    vt[O9_VB] = vtable8("IDirect3DVertexBuffer8", vb, 14); vt[O9_IB] = vtable8("IDirect3DIndexBuffer8", vb, 14);
    vt[O9_SWAP] = vtable8("IDirect3DSwapChain8", swap, 5);
}

IMPL(d3d8, Direct3DCreate8)                            /* (SDK version: 220 for the DirectX 8.1 SDK) */
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    d9_method(O9_D3D, 0);                              /* Direct3D 9's vtables first, then Direct3D 8's in their place */
    pthread_once(&once, init_vtables8);
    if (log8()) fprintf(stderr, "d3d8: Direct3DCreate8(%u)\n", ARG(0));
    void imp_d3d9_Direct3DCreate9(Ctx *);
    uint32_t sdk = ARG(0), r = call9(c, imp_d3d9_Direct3DCreate9, 1, (uint32_t[]){sdk});
    RET(r, 1);
}
