// ff_audiocorr <capture.wav> <reference.wav>... : does a capture of what the port played (W32_AUDIO_DUMP: 16-bit stereo
// 44100 Hz) contain a reference recording (the same sound decoded by macOS: afconvert -d LEI16@44100)? For three windows of
// the capture's loud part, finds the best reference and offset (coarse at 11025 Hz over each whole reference, then
// sample-exact at 44100 Hz) and prints the normalised correlation (1.0 = identical up to gain). A sound the port plays
// right scores well above 0.9 at offsets that advance with the window; a wrong rate, gaps or garbage score low.
// Standard C and Accelerate only (no numpy or ffmpeg on the Mac). Build: clang -O2 -framework Accelerate.
#include <Accelerate/Accelerate.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { float *s; long n; } Mono;
static Mono wav(const char *path)       /* the data chunk of a 16-bit stereo WAV, mixed to mono floats */
{
    Mono m = {0};
    FILE *f = fopen(path, "rb"); if (!f) return m;
    char id[4]; uint32_t len; fseek(f, 12, SEEK_SET);
    while (fread(id, 1, 4, f) == 4 && fread(&len, 4, 1, f) == 1) {
        if (memcmp(id, "data", 4)) { fseek(f, len + (len & 1), SEEK_CUR); continue; }
        int16_t *raw = malloc(len); len = (uint32_t)fread(raw, 1, len, f);
        m.n = len / 4; m.s = malloc(sizeof(float) * (m.n ? m.n : 1));
        for (long i = 0; i < m.n; i++) m.s[i] = (raw[2 * i] + raw[2 * i + 1]) * 0.5f;
        free(raw); break;
    }
    fclose(f); return m;
}
static Mono decimate(Mono a, int k)
{
    Mono d = {malloc(sizeof(float) * (a.n / k + 1)), a.n / k};
    for (long i = 0; i < d.n; i++) { float t = 0; for (int j = 0; j < k; j++) t += a.s[i * k + j]; d.s[i] = t / k; }
    return d;
}
/* the offset in ref where win correlates best (normalised), and that correlation */
static double best(const float *win, long w, const float *ref, long n, long lo, long hi, long *at)
{
    if (hi > n - w) hi = n - w; if (lo < 0) lo = 0; if (hi <= lo) { *at = -1; return 0; }
    long m = hi - lo; float *dot = malloc(sizeof(float) * m);
    vDSP_conv(ref + lo, 1, win, 1, dot, 1, (vDSP_Length)m, (vDSP_Length)w);     /* correlation: win slides along ref */
    double ww = 0; for (long i = 0; i < w; i++) ww += (double)win[i] * win[i];
    double e = 0; for (long i = lo; i < lo + w; i++) e += (double)ref[i] * ref[i];
    double bc = -2; long bi = -1;
    for (long i = 0; i < m; i++) {
        double c = dot[i] / (sqrt(ww * e) + 1e-9);
        if (c > bc) { bc = c; bi = lo + i; }
        if (i + 1 < m) { double a = ref[lo + i], b = ref[lo + i + w]; e += b * b - a * a; if (e < 0) e = 0; }
    }
    free(dot); *at = bi; return bc;
}
/* --find: each reference's first loud 1.5 s searched for along the whole capture (a voice line inside a mix) */
static int find(int argc, char **argv)
{
    Mono cap = wav(argv[2]); if (!cap.n) { fprintf(stderr, "no audio in %s\n", argv[2]); return 1; }
    Mono cap4 = decimate(cap, 4); int found = 0;
    for (int r = 3; r < argc; r++) {
        Mono ref = wav(argv[r]); long s = 0; while (s < ref.n && fabsf(ref.s[s]) < 600) s++;
        long w = (long)(1.5 * 44100); if (s + w > ref.n) { w = ref.n - s; } if (w < 22050) { printf("%s: too short\n", argv[r]); continue; }
        Mono win = {ref.s + s, w}, win4 = decimate(win, 4); long at;
        double c4 = best(win4.s, win4.n, cap4.s, cap4.n, 0, cap4.n, &at);
        long at1 = -1; double c = best(win.s, w, cap.s, cap.n, at * 4 - 16, at * 4 + 16, &at1);
        if (c > 0.5) found++;
        printf("%s: at %.2f s of the capture, correlation %.4f (coarse %.3f)\n", argv[r], (at1 - s) / 44100.0, c, c4);
        free(win4.s); free(ref.s);
    }
    printf("%d of %d found (> 0.5: the line is there, mixed with the rest)\n", found, argc - 3);
    return 0;
}
int main(int argc, char **argv)
{
    if (argc >= 4 && !strcmp(argv[1], "--find")) return find(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: ff_audiocorr <capture.wav> <reference.wav>... | --find <capture.wav> <reference.wav>...\n"); return 2; }
    Mono cap = wav(argv[1]); if (!cap.n) { fprintf(stderr, "no audio in %s\n", argv[1]); return 1; }
    int nref = argc - 2; Mono *ref = calloc(nref, sizeof *ref), *ref4 = calloc(nref, sizeof *ref4);
    for (int r = 0; r < nref; r++) { ref[r] = wav(argv[2 + r]); ref4[r] = decimate(ref[r], 4); }
    long first = 0, last = cap.n - 1;      /* the loud part of the capture */
    while (first < cap.n && fabsf(cap.s[first]) < 300) first++;
    while (last > first && fabsf(cap.s[last]) < 300) last--;
    printf("capture %.1f s, loud from %.1f s to %.1f s\n", cap.n / 44100.0, first / 44100.0, last / 44100.0);
    const long W = 3 * 44100;
    int good = 0, tried = 0;
    for (int k = 1; k <= 3; k++) {
        long s = first + (last - first - W) * k / 4; if (s < first || s + W > cap.n) continue;
        double rms = 0; for (long i = 0; i < W; i++) rms += (double)cap.s[s + i] * cap.s[s + i]; rms = sqrt(rms / W);
        if (rms < 100) { printf("  %6.1f s: quiet\n", s / 44100.0); continue; }
        Mono w = {cap.s + s, W}, w4 = decimate(w, 4);
        double bc = -2; long bo = -1; int br = -1;
        for (int r = 0; r < nref; r++) { long at; double c = best(w4.s, w4.n, ref4[r].s, ref4[r].n, 0, ref4[r].n, &at); if (c > bc) { bc = c; bo = at; br = r; } }
        free(w4.s);
        long at = -1; double c = br >= 0 ? best(w.s, W, ref[br].s, ref[br].n, bo * 4 - 16, bo * 4 + 16, &at) : 0;   /* sample-exact */
        tried++; if (c > 0.9) good++;
        printf("  %6.1f s of the capture -> %s at %.3f s: correlation %.4f (coarse %.3f)\n", s / 44100.0, br >= 0 ? argv[2 + br] : "-", at / 44100.0, c, bc);
    }
    printf("%d of %d windows above 0.9\n", good, tried);
    return tried && good == tried ? 0 : 1;
}
