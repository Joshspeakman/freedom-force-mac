// ff_icon <art folder> <out.png> [--nightly] [--layout hero|logo|both]: the app icon (hero, the default: Minuteman charging over the
// menu's nebula; the player chose it over the logo) (install.sh), from the launch
// window's banner art (tools/ff_art.m: the main menu's heroes and nebula, the logo), in macOS icon proportions
// (an 824 tile in 1024, corner radius 185), with the Nightly band of the other ports' Nightly apps when asked.
// Build: clang -fobjc-arc -framework AppKit. Without the art it exits 1 and install.sh keeps the game's own icon.
#import <AppKit/AppKit.h>

static NSImage *load(NSString *dir, NSString *name) { NSImage *i = [[NSImage alloc] initWithContentsOfFile:[dir stringByAppendingPathComponent:name]]; return i.size.width > 16 ? i : nil; }
static NSColor *rgb(int r, int g, int b) { return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }
/* the part of an image with any opacity (the Steam logo comes with margins) */
static NSImage *trimmed(NSImage *img)
{
    CGImageRef c = [img CGImageForProposedRect:NULL context:nil hints:nil]; if (!c) return img;
    size_t w = CGImageGetWidth(c), h = CGImageGetHeight(c); uint8_t *px = calloc(w * h, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB(); CGContextRef g = CGBitmapContextCreate(px, w, h, 8, w * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(g, CGRectMake(0, 0, w, h), c);
    size_t x0 = w, y0 = h, x1 = 0, y1 = 0;
    for (size_t y = 0; y < h; y++) for (size_t x = 0; x < w; x++) if (px[(y * w + x) * 4 + 3] > 8) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    CGContextRelease(g); CGColorSpaceRelease(cs); free(px);
    if (x1 < x0) return img;
    CGImageRef t = CGImageCreateWithImageInRect(c, CGRectMake(x0, y0, x1 - x0 + 1, y1 - y0 + 1));
    NSImage *r = [[NSImage alloc] initWithCGImage:t size:NSZeroSize]; CGImageRelease(t); return r;
}
/* `from` (in the image's own top-down pixels) drawn to fill `to` */
static void draw_part(NSImage *img, NSRect from, NSRect to)
{
    NSSize s = img.size; NSRect f = NSMakeRect(from.origin.x, s.height - NSMaxY(from), from.size.width, from.size.height);   /* AppKit images run bottom-up */
    [img drawInRect:to fromRect:f operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}
static void cover(NSImage *img, NSRect r, CGFloat ax, CGFloat ay)
{
    NSSize s = img.size; CGFloat sc = MAX(r.size.width / s.width, r.size.height / s.height), w = r.size.width / sc, h = r.size.height / sc;
    draw_part(img, NSMakeRect((s.width - w) * ax, (s.height - h) * ay, w, h), r);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: ff_icon <art folder> <out.png> [--nightly] [--layout hero|logo|both]\n"); return 2; }
        NSString *dir = @(argv[1]); BOOL nightly = NO; NSString *layout = @"hero";
        for (int k = 3; k < argc; k++) { if (!strcmp(argv[k], "--nightly")) nightly = YES; else if (!strcmp(argv[k], "--layout") && k + 1 < argc) layout = @(argv[++k]); }
        NSImage *nebula = load(dir, @"nebula.png"), *heroes = load(dir, @"heroes.png"), *logo = load(dir, @"logo.png");
        if (!nebula || (!heroes && !logo)) { fprintf(stderr, "ff_icon: no art in %s\n", argv[1]); return 1; }
        if (logo) logo = trimmed(logo);
        const CGFloat S = 1024;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)S pixelsHigh:(NSInteger)S bitsPerSample:8 samplesPerPixel:4
            hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
        NSRect tile = NSMakeRect(100, 100, 824, 824);
        NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:tile xRadius:185 yRadius:185];
        NSShadow *drop = [NSShadow new]; drop.shadowColor = [NSColor colorWithWhite:0 alpha:0.45]; drop.shadowOffset = NSMakeSize(0, -10); drop.shadowBlurRadius = 24;
        [NSGraphicsContext saveGraphicsState]; [drop set]; [NSColor.blackColor setFill]; [shape fill]; [NSGraphicsContext restoreGraphicsState];
        [NSGraphicsContext saveGraphicsState]; [shape addClip];

        cover(nebula, tile, 0.18, 0.5);                                        /* the menu's pink nebula */
        CGFloat floor = nightly ? 285 : 100;                                    /* the art sits above the band */
        BOOL hero = heroes && ![layout isEqualToString:@"logo"], withLogo = logo && ![layout isEqualToString:@"hero"];
        if (hero) {   /* Minuteman, from the heroes' picture: his head under the tile's top, his fist forward */
            NSRect to = NSMakeRect(100, withLogo ? floor + 40 : floor, 824, 924 - (withLogo ? floor + 40 : floor));
            CGFloat fw = withLogo ? 330 : 300, fh = fw * to.size.height / to.size.width;   /* his face (x 495) centred, its proportions kept */
            NSRect from = NSMakeRect(495 - fw / 2, 0, fw, fh);
            NSShadow *s = [NSShadow new]; s.shadowColor = [NSColor colorWithWhite:0 alpha:0.75]; s.shadowOffset = NSMakeSize(-10, -10); s.shadowBlurRadius = 18;
            [NSGraphicsContext saveGraphicsState]; [s set];
            draw_part(heroes, from, to);
            [NSGraphicsContext restoreGraphicsState];
        }
        if (withLogo) {   /* the logo across the bottom (alone: in the middle) */
            CGFloat w = hero ? 760 : 780, h = w * logo.size.height / logo.size.width;
            NSRect lr = hero ? NSMakeRect(512 - w / 2, floor + 14, w, h) : NSMakeRect(512 - w / 2, floor + (924 - floor - h) / 2, w, h);
            NSShadow *s = [NSShadow new]; s.shadowColor = [NSColor colorWithWhite:0 alpha:0.85]; s.shadowOffset = NSMakeSize(6, -10); s.shadowBlurRadius = 16;
            [NSGraphicsContext saveGraphicsState]; [s set];
            [logo drawInRect:lr fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
            [NSGraphicsContext restoreGraphicsState];
        }
        NSGradient *shade = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:0.0], 0.0, [NSColor colorWithWhite:0 alpha:0.0], 0.7,
                             [NSColor colorWithWhite:1 alpha:0.10], 1.0, nil];
        [shade drawInRect:tile angle:90];                                      /* a little light from above */
        if (nightly) {   /* the band, as on the other ports' Nightly apps */
            NSRect band = NSMakeRect(100, 100, 824, 185);
            NSGradient *fill = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.36 green:0.20 blue:0.78 alpha:1] endingColor:[NSColor colorWithSRGBRed:0.20 green:0.10 blue:0.52 alpha:1]];
            [fill drawInRect:band angle:-90];
            [rgb(8, 8, 14) setFill]; NSRectFill(NSMakeRect(100, 285, 824, 8));
            NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter;
            NSShadow *ts = [NSShadow new]; ts.shadowColor = [NSColor colorWithWhite:0 alpha:0.6]; ts.shadowOffset = NSMakeSize(0, -3); ts.shadowBlurRadius = 6;
            NSDictionary *at = @{NSFontAttributeName: [NSFont systemFontOfSize:104 weight:NSFontWeightHeavy], NSForegroundColorAttributeName: NSColor.whiteColor,
                                 NSParagraphStyleAttributeName: ps, NSKernAttributeName: @8, NSShadowAttributeName: ts};
            NSSize ls = [@"NIGHTLY" sizeWithAttributes:at];
            [@"NIGHTLY" drawInRect:NSMakeRect(100, NSMidY(band) + 12 - ls.height / 2, 824, ls.height) withAttributes:at];
        }
        [NSGraphicsContext restoreGraphicsState];
        [rgb(8, 8, 14) setStroke]; shape.lineWidth = 14; [shape stroke];      /* the comic outline, and the launcher's yellow keyline */
        NSBezierPath *key = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(tile, 14, 14) xRadius:172 yRadius:172];
        [[rgb(255, 222, 0) colorWithAlphaComponent:0.9] setStroke]; key.lineWidth = 5; [key stroke];
        [NSGraphicsContext restoreGraphicsState];
        if (![[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[2]) atomically:YES]) { fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    }
    return 0;
}
