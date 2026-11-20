// ff_art <work folder> <art folder>: composes what tools/ff_art.py took from the player's game into the launch window's
// art (install.sh). Build: clang -fobjc-arc -framework AppKit. The main menu's 3 x 2 tile scenes become one picture each,
// cut to the band the menu shows (the tiles above and below hold the menu's black bars):
//   heroes.png   the team, with transparency      nebula.png  the pink nebula behind them
//   blue.png     the Load Game screen's nebula     logo.png    the logo: Steam's if fetched, else the game's two tiles
//   keyart.jpg   GOG Galaxy's banner, copied as it is
// Nothing here is game data itself; the outputs stay in the data folder and the app.
#import <AppKit/AppKit.h>

static const int TILE = 256, BAND_Y = 104, BAND_H = 332;     /* the menu's band in the 768 x 512 scene (measured: the black bars above and below are cut off) */

static NSBitmapImageRep *canvas(int w, int h)
{
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
}
static BOOL save(NSBitmapImageRep *r, NSString *path)
{
    return [[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
/* tiles <prefix>_1.. in rows of `cols`, the band [y0, y0 + h) of the whole (top-down) */
static BOOL compose(NSString *dir, NSString *prefix, int cols, int rows, int y0, int h, NSString *out)
{
    NSBitmapImageRep *r = canvas(cols * TILE, h);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:r];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationNone;
    for (int k = 0; k < cols * rows; k++) {
        NSImage *t = [[NSImage alloc] initWithContentsOfFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%d.tga", prefix, k + 1]]];
        if (!t) { [NSGraphicsContext restoreGraphicsState]; return NO; }
        int x = (k % cols) * TILE, top = (k / cols) * TILE - y0;              /* the tile's top, from the band's top */
        [t drawInRect:NSMakeRect(x, h - top - TILE, TILE, TILE) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    }
    [NSGraphicsContext restoreGraphicsState];
    return save(r, out);
}
static BOOL logo_tiles(NSString *dir, NSString *out)
{
    NSBitmapImageRep *r = canvas(2 * TILE, TILE);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:r];
    for (int k = 0; k < 2; k++) {
        NSImage *t = [[NSImage alloc] initWithContentsOfFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"ff_logo_0%d.tga", k + 1]]];
        if (!t) { [NSGraphicsContext restoreGraphicsState]; return NO; }
        [t drawInRect:NSMakeRect(k * TILE, 0, TILE, TILE) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    }
    [NSGraphicsContext restoreGraphicsState];
    return save(r, out);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: ff_art <work folder> <art folder>\n"); return 2; }
        NSString *in = @(argv[1]), *out = @(argv[2]), *menu = [in stringByAppendingPathComponent:@"menu"];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
        NSMutableArray *made = [NSMutableArray array];
        if (compose(menu, @"char", 3, 2, BAND_Y, BAND_H, [out stringByAppendingPathComponent:@"heroes.png"])) [made addObject:@"heroes"];
        if (compose(menu, @"back", 3, 2, BAND_Y, BAND_H, [out stringByAppendingPathComponent:@"nebula.png"])) [made addObject:@"nebula"];
        if (compose([in stringByAppendingPathComponent:@"blue"], @"back", 3, 2, BAND_Y, BAND_H, [out stringByAppendingPathComponent:@"blue.png"])) [made addObject:@"blue"];
        NSString *steam = [in stringByAppendingPathComponent:@"steam_logo.png"], *logo = [out stringByAppendingPathComponent:@"logo.png"];
        [fm removeItemAtPath:logo error:nil];
        if ([[NSImage alloc] initWithContentsOfFile:steam] && [fm copyItemAtPath:steam toPath:logo error:nil]) [made addObject:@"logo (Steam)"];
        else if (logo_tiles(menu, logo)) [made addObject:@"logo (the game's)"];
        NSString *key = [in stringByAppendingPathComponent:@"keyart.jpg"], *keyOut = [out stringByAppendingPathComponent:@"keyart.jpg"];
        [fm removeItemAtPath:keyOut error:nil];
        if ([fm copyItemAtPath:key toPath:keyOut error:nil]) [made addObject:@"key art"];
        printf("art: %s\n", made.count ? [made componentsJoinedByString:@", "].UTF8String : "none: the launch window draws its title");
        return 0;
    }
}
