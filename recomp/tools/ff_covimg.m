// ff_covimg: image checks and contact sheets for tools/ff_coverage.py. Build: clang -fobjc-arc -framework AppKit.
//   ff_covimg stats <reference.png|-> <image.png>...   one line per image: path, mean brightness (0-255), the share of
//       pixels in the middle of the frame that differ from the reference by more than 24 (0-1; -1 without one), and
//       the share of the whole frame in its most common colour (a frame of one colour: black, a clear colour, garbage)
//   ff_covimg sheet <out.png> <columns> <label=image.png>...   the images in a grid at 320 x 240, each labelled
#import <AppKit/AppKit.h>

typedef struct { int w, h; uint8_t *px; } Img;
static Img load(const char *path)
{
    Img im = {0};
    NSImage *i = [[NSImage alloc] initWithContentsOfFile:@(path)]; if (!i) return im;
    CGImageRef c = [i CGImageForProposedRect:NULL context:nil hints:nil]; if (!c) return im;
    im.w = (int)CGImageGetWidth(c); im.h = (int)CGImageGetHeight(c); im.px = calloc((size_t)im.w * im.h, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef g = CGBitmapContextCreate(im.px, im.w, im.h, 8, (size_t)im.w * 4, cs, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGContextDrawImage(g, CGRectMake(0, 0, im.w, im.h), c); CGContextRelease(g); CGColorSpaceRelease(cs);
    return im;
}
static int stats(int argc, char **argv)
{
    Img ref = strcmp(argv[2], "-") ? load(argv[2]) : (Img){0};
    for (int k = 3; k < argc; k++) {
        Img im = load(argv[k]);
        if (!im.px) { printf("%s -1 -1 -1\n", argv[k]); continue; }
        double sum = 0; long n = (long)im.w * im.h, changed = 0, mid = 0;
        NSMutableDictionary<NSNumber *, NSNumber *> *hist = [NSMutableDictionary dictionary];
        for (long p = 0; p < n; p += 7) {          /* a sample of the pixels is enough */
            uint8_t *q = im.px + p * 4; sum += 0.299 * q[0] + 0.587 * q[1] + 0.114 * q[2];
            NSNumber *key = @((q[0] >> 3) << 10 | (q[1] >> 3) << 5 | (q[2] >> 3)); hist[key] = @(hist[key].intValue + 1);
        }
        int top = 0; for (NSNumber *v in hist.allValues) if (v.intValue > top) top = v.intValue;
        double diff = -1;
        if (ref.px && ref.w == im.w && ref.h == im.h) {   /* the middle third: where the camera puts what is tested */
            for (int y = im.h / 4; y < im.h * 3 / 4; y += 2) for (int x = im.w / 3; x < im.w * 2 / 3; x += 2) {
                uint8_t *a = im.px + ((long)y * im.w + x) * 4, *b = ref.px + ((long)y * im.w + x) * 4; mid++;
                if (abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) > 24 * 3) changed++;
            }
            diff = mid ? (double)changed / mid : 0;
        }
        printf("%s %.1f %.4f %.4f\n", argv[k], sum / ((n + 6) / 7), diff, (double)top / ((n + 6) / 7));
        free(im.px);
    }
    free(ref.px);
    return 0;
}
static int sheet(int argc, char **argv)
{
    int cols = atoi(argv[3]), count = argc - 4, rows = (count + cols - 1) / cols; const int W = 320, H = 240, L = 18;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:cols * W pixelsHigh:rows * (H + L)
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [[NSColor colorWithWhite:0.1 alpha:1] setFill]; NSRectFill(NSMakeRect(0, 0, cols * W, rows * (H + L)));
    NSDictionary *at = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:11], NSForegroundColorAttributeName: NSColor.whiteColor};
    for (int k = 0; k < count; k++) {
        char *arg = argv[4 + k], *eq = strchr(arg, '='); NSString *label = eq ? [[NSString alloc] initWithBytes:arg length:(NSUInteger)(eq - arg) encoding:NSUTF8StringEncoding] : @"";
        const char *path = eq ? eq + 1 : arg;
        int c = k % cols, r = k / cols; CGFloat y0 = (rows - 1 - r) * (H + L);
        NSImage *i = [[NSImage alloc] initWithContentsOfFile:@(path)];
        if (i) [i drawInRect:NSMakeRect(c * W, y0, W, H) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
        else { [[NSColor colorWithSRGBRed:0.5 green:0 blue:0 alpha:1] setFill]; NSRectFill(NSMakeRect(c * W, y0, W, H)); }
        [label drawInRect:NSMakeRect(c * W + 4, y0 + H + 2, W - 8, L - 3) withAttributes:at];
    }
    [NSGraphicsContext restoreGraphicsState];
    return [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[2]) atomically:YES] ? 0 : 1;
}
int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc >= 3 && !strcmp(argv[1], "stats")) return stats(argc, argv);
        if (argc >= 5 && !strcmp(argv[1], "sheet")) return sheet(argc, argv);
        fprintf(stderr, "usage: ff_covimg stats <reference|-> <image>... | sheet <out.png> <columns> <label=image>...\n"); return 2;
    }
}
