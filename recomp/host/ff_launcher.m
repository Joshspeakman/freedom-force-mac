// Freedom Force's launch window, laid out like the other ports' (Dungeon Siege, The Sims 2, Delta Force): a banner (the
// game's logo over its art), the Resolution and Language rows, and a button for each group of settings (Display, Key
// Guide, Files, Updates) that opens it as a panel. It is dressed in the game's own interface: yellow comic-book buttons
// with black outlines and hard shadows, pale yellow title bars, the main menu's nebula and heroes.
// The art is composed at install time from the player's own copy (tools/ff_art.py and ff_art.m: the main menu's tiles in
// Data/art.ff, GOG Galaxy's banner, the Steam store logo) into <data>/art and a copy in the app; nothing from the game
// is stored in this project, and without the art the window draws its title.
// Choices are remembered in <data>/launcher.plist (the keys of ff_launch_settings.h) and passed to the game as
// environment by ff_apply_settings. DS_LAUNCHER_SHOT=<png> renders the window to an image (DS_LAUNCHER_OPEN=<group>
// with that group open; FF_BANNER=keyart|menu picks the banner art).
#import <AppKit/AppKit.h>
#import "ff_launch_settings.h"
#ifndef DS_BUILD
#define DS_BUILD "dev"
#endif

// ---------------------------------------------------------------- the game's colours and lettering
static NSColor *rgb(int r, int g, int b) { return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }
static NSColor *yellow(void) { return rgb(255, 222, 0); }           /* the menu buttons */
static NSColor *yellow_hot(void) { return rgb(255, 238, 92); }
static NSColor *pale(void) { return rgb(255, 245, 168); }           /* the dialogs' title bars */
static NSColor *ink(void) { return rgb(8, 8, 14); }                 /* the outlines */
static NSColor *red(void) { return rgb(214, 34, 38); }              /* Minuteman's coat */
static NSColor *red_hot(void) { return rgb(240, 62, 54); }
static NSColor *navy(void) { return rgb(10, 16, 46); }
static NSColor *cream(void) { return rgb(250, 244, 226); }
static NSColor *dim(void) { return rgb(176, 184, 214); }
static NSFont *heavy(CGFloat n) { return [NSFont fontWithName:@"AvenirNextCondensed-HeavyItalic" size:n] ?: [NSFont boldSystemFontOfSize:n]; }
static NSFont *demi(CGFloat n) { return [NSFont fontWithName:@"AvenirNextCondensed-DemiBold" size:n] ?: [NSFont systemFontOfSize:n weight:NSFontWeightSemibold]; }
static NSFont *medium(CGFloat n) { return [NSFont fontWithName:@"AvenirNextCondensed-Medium" size:n] ?: [NSFont systemFontOfSize:n]; }

/* text in a rectangle; `outline` > 0 draws it filled with a black outline (comic lettering) */
static void draw_text(NSString *s, NSFont *f, NSColor *c, NSRect r, NSTextAlignment al, CGFloat kern, CGFloat outline, NSShadow *sh)
{
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = al; ps.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *a = [@{NSFontAttributeName: f, NSForegroundColorAttributeName: c, NSParagraphStyleAttributeName: ps, NSKernAttributeName: @(kern)} mutableCopy];
    if (sh) a[NSShadowAttributeName] = sh;
    if (outline > 0) {   /* the outline under the fill, so it doesn't eat into thin letters */
        NSMutableDictionary *o = [a mutableCopy]; o[NSStrokeColorAttributeName] = ink(); o[NSStrokeWidthAttributeName] = @(outline * 100 / f.pointSize);
        [s drawInRect:r withAttributes:o]; [a removeObjectForKey:NSShadowAttributeName];
    }
    [s drawInRect:r withAttributes:a];
}
static NSShadow *soft_shadow(void)
{
    NSShadow *s = [NSShadow new]; s.shadowColor = [NSColor colorWithWhite:0 alpha:0.85]; s.shadowOffset = NSMakeSize(0, -1.5); s.shadowBlurRadius = 3; return s;
}
static void star(NSPoint c, CGFloat radius, NSColor *fill)
{
    NSBezierPath *p = [NSBezierPath bezierPath];
    for (int i = 0; i < 10; i++) {
        double a = -M_PI / 2 + i * M_PI / 5, r = i % 2 ? radius * 0.42 : radius;
        NSPoint q = NSMakePoint(c.x + cos(a) * r, c.y + sin(a) * r); if (i) [p lineToPoint:q]; else [p moveToPoint:q];
    }
    [p closePath]; [fill setFill]; [p fill]; [ink() setStroke]; p.lineWidth = 1.5; [p stroke];
}
/* a comic panel: the solid black shadow below and to the right, the fill, the black outline */
static void comic_box(NSRect r, NSColor *fill, CGFloat lift, CGFloat line)
{
    if (lift > 0) { [ink() setFill]; NSRectFill(NSOffsetRect(r, lift, lift)); }
    [fill setFill]; NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
    [ink() setStroke]; NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(r, line / 2, line / 2)]; b.lineWidth = line; [b stroke];
}
/* an image filling a rectangle, its aspect kept (cropped about `anchor`: 0..1 of the spare width and height) */
static void draw_cover(NSImage *img, NSRect r, NSPoint anchor, CGFloat fraction)
{
    NSSize is = img.size; CGFloat sc = MAX(r.size.width / is.width, r.size.height / is.height), w = r.size.width / sc, h = r.size.height / sc;
    [img drawInRect:r fromRect:NSMakeRect((is.width - w) * anchor.x, (is.height - h) * (1 - anchor.y), w, h) operation:NSCompositingOperationSourceOver
           fraction:fraction respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}

// ---------------------------------------------------------------- settings rows and groups
@interface FFRow : NSObject
@property NSString *title, *key; @property NSArray<NSDictionary *> *choices; @property NSInteger index;
@property (copy) void (^activate)(void);       /* a row that runs something instead of cycling (Files) */
@end
@implementation FFRow @end

/* A group's button opens it as a panel over the window, with Back where Quit was. Key Guide shows `guide`; Updates
 * runs its own `activate`. */
@interface FFSection : NSObject
@property NSString *title; @property NSArray<FFRow *> *rows; @property NSArray<NSArray<NSString *> *> *guide;
@property (copy) void (^activate)(void); @property (copy) NSString *(^summary)(void);
@end
@implementation FFSection @end

static NSInteger index_of(NSArray<NSDictionary *> *c, id v, NSInteger dflt)
{
    for (NSUInteger k = 0; k < c.count; k++) if ([c[k][@"value"] isEqual:v]) return (NSInteger)k;
    return dflt;
}
static int notch_height(void) { if (@available(macOS 12.0, *)) return (int)NSScreen.mainScreen.safeAreaInsets.top; return 0; }
/* the game's screen: this display (below the notch unless the picture goes around it), or a common size, scaled to fill */
static NSArray<NSDictionary *> *resolution_choices(NSString *saved)
{
    NSScreen *s = NSScreen.mainScreen; int W = (int)s.frame.size.width, H = (int)s.frame.size.height;
    NSMutableArray *a = [NSMutableArray arrayWithObject:@{@"value": @"display", @"label": @"This Display",
        @"note": [NSString stringWithFormat:@"%d × %d, the whole screen (recommended)", W, H - (notch_height() > 0 ? notch_height() : 0)]}];
    static const int std[][2] = {{2560,1600},{2560,1440},{1920,1200},{1920,1080},{1680,1050},{1600,900},{1440,900},{1280,800},{1280,720},{1024,768},{800,600},{640,480}};
    NSMutableArray *values = [NSMutableArray array];
    for (size_t k = 0; k < sizeof std / sizeof *std; k++) if (std[k][0] <= W && std[k][1] <= H) [values addObject:[NSString stringWithFormat:@"%dx%d", std[k][0], std[k][1]]];
    if ([saved isKindOfClass:NSString.class] && ![saved isEqual:@"display"] && ![values containsObject:saved]) [values insertObject:saved atIndex:0];
    for (NSString *v in values) {
        int w = 0, h = 0; sscanf(v.UTF8String, "%dx%d", &w, &h);
        NSString *note = w * 3 == h * 4 ? @"The original 4:3 shape, with bars at the sides" : w == 640 ? @"As the game first shipped" : @"Widescreen, scaled to fill the screen";
        [a addObject:@{@"value": v, @"label": [NSString stringWithFormat:@"%d × %d", w, h], @"note": note}];
    }
    return a;
}
static NSArray<NSDictionary *> *language_choices(void)
{
    return @[@{@"value": @"English", @"label": @"English", @"note": @"The game as GOG installs it"},
             @{@"value": @"German", @"label": @"Deutsch", @"note": @"German text and the German menus' layouts"},
             @{@"value": @"French", @"label": @"Français", @"note": @"French text and the French menus' layouts"}];
}
static NSArray<NSDictionary *> *window_choices(void)
{
    return @[@{@"value": @YES, @"label": @"Full Screen", @"note": @"macOS full screen, with Game Mode"},
             @{@"value": @NO, @"label": @"Window", @"note": @"A window you can move and resize"}];
}
static NSArray<NSDictionary *> *notch_choices(void)
{
    return @[@{@"value": @"below", @"label": @"Below the Notch", @"note": @"The picture under the camera, a black band beside it"},
             @{@"value": @"around", @"label": @"Around the Notch", @"note": @"The whole display; the notch covers a little of the top"}];
}
static NSArray<NSDictionary *> *framerate_choices(void)
{
    NSInteger hz = NSScreen.mainScreen.maximumFramesPerSecond; if (hz <= 0) hz = 60;
    NSMutableArray *a = [NSMutableArray array];
    if (hz >= 120) [a addObject:@{@"value": @"120", @"label": @"120 FPS", @"note": @"As smooth as this display shows (recommended)"}];
    [a addObject:@{@"value": @"60", @"label": @"60 FPS", @"note": hz >= 120 ? @"Cooler and quieter, longer on battery" : @"As smooth as this display shows (recommended)"}];
    [a addObject:@{@"value": @"30", @"label": @"30 FPS", @"note": @"Lightest: for long sessions on battery"}];
    [a addObject:@{@"value": @"unlimited", @"label": @"Unlimited", @"note": @"No cap: as fast as the Mac can draw"}];
    return a;
}
static NSArray<NSDictionary *> *vsync_choices(void)
{
    return @[@{@"value": @YES, @"label": @"On", @"note": @"Frames wait for the display: no tearing"},
             @{@"value": @NO, @"label": @"Off", @"note": @"Lowest delay; fast pans may tear"}];
}
/* the Key Guide: the game's default controls (Options > Control, where they can be changed) */
static NSArray<NSArray<NSString *> *> *key_guide(void)
{
    return @[@[@"CLICK", @"Select a hero; click the ground to move, a foe to attack"],
             @[@"SHIFT", @"Add heroes to the selection"],
             @[@"CONTROL", @"Force the default attack"],
             @[@"W A S D", @"Move the camera; the arrow keys too"],
             @[@"WHEEL", @"Zoom the camera in and out"],
             @[@"TAB", @"Fade the buildings in the way"],
             @[@"F11  F12", @"Quick save and quick load (with fn on a Mac keyboard)"],
             @[@"ESC", @"The mission menu: save, load, options"]];
}

// ---------------------------------------------------------------- the view
@interface FFLaunchView : NSView
@property NSArray<FFRow *> *top; @property NSArray<FFSection *> *sections; @property NSInteger open;   /* the open group, -1 none */
@property NSInteger focus, hover, pressed;
@property NSImage *nebula, *heroes, *blue, *keyart, *logo, *backdrop; @property BOOL useKeyart;
@property NSString *subtitle, *note, *footer;
@property (copy) void (^onPlay)(void); @property (copy) void (^onQuit)(void); @property (copy) void (^onChange)(void);
@property BOOL starting;
@end

enum { HIT_NONE = -1, HIT_PLAY = 100, HIT_QUIT = 101, HIT_BACK = 102, HIT_SECTION = 200 };   /* rows: 10*row + 0 (left arrow) / 1 (value) / 2 (right arrow) */
enum { WIN_W = 780, WIN_H = 860, BANNER_H = 268, TOP_Y = 292, ROW_H = 74 };

@implementation FFLaunchView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (NSArray<FFRow *> *)rows { return self.open >= 0 ? self.sections[self.open].rows : self.top; }
- (NSInteger)items { return (NSInteger)self.rows.count + (self.open >= 0 ? 0 : (NSInteger)self.sections.count); }   /* what the keyboard moves between */
- (NSRect)topPanel { return NSMakeRect(52, TOP_Y, self.bounds.size.width - 104, ROW_H * (CGFloat)self.top.count + 16); }
- (NSRect)flyRect   /* an open group's panel, as tall as what it holds, centred above Back and Play */
{
    NSRect b = self.bounds; FFSection *s = self.open >= 0 ? self.sections[self.open] : nil;
    CGFloat need = s.guide ? 84 + 44 * (CGFloat)s.guide.count + 56 : 76 + ROW_H * (CGFloat)s.rows.count + 18;
    CGFloat top = 150, bottom = b.size.height - 124, h = MIN(MAX(need, 260), bottom - top);
    return NSMakeRect(44, round(top + (bottom - top - h) / 2), b.size.width - 88, h);
}
- (NSRect)rowRect:(NSInteger)k
{
    CGFloat y = self.open >= 0 ? self.flyRect.origin.y + 76 : TOP_Y + 12;
    return NSMakeRect(80, y + ROW_H * k, self.bounds.size.width - 160, 62);
}
- (NSRect)arrow:(NSInteger)k right:(BOOL)right { NSRect r = [self rowRect:k]; return NSMakeRect(right ? NSMaxX(r) - 32 : NSMaxX(r) - 334, r.origin.y + 5, 32, 32); }
- (NSRect)valueRect:(NSInteger)k { NSRect r = [self rowRect:k]; return NSMakeRect(NSMaxX(r) - 298, r.origin.y + 5, 262, 32); }
- (NSRect)sectionRect:(NSInteger)i
{
    NSInteger n = (NSInteger)self.sections.count, per = 2, line = i / per, inLine = MIN(per, n - line * per), col = i % per;
    CGFloat w = 300, g = 34, x0 = (self.bounds.size.width - (inLine * w + (inLine - 1) * g)) / 2;
    return NSMakeRect(x0 + col * (w + g), NSMaxY(self.topPanel) + 40 + line * 104, w, 56);
}
- (NSRect)playRect { NSRect b = self.bounds; return NSMakeRect(NSMidX(b) + 14, b.size.height - 92, 230, 58); }
- (NSRect)quitRect { NSRect b = self.bounds; return NSMakeRect(NSMidX(b) - 244, b.size.height - 92, 230, 58); }
- (NSInteger)hit:(NSPoint)p
{
    if (NSPointInRect(p, self.playRect)) return HIT_PLAY;
    if (NSPointInRect(p, self.quitRect)) return self.open >= 0 ? HIT_BACK : HIT_QUIT;
    if (self.open < 0) for (NSInteger i = 0; i < (NSInteger)self.sections.count; i++) if (NSPointInRect(p, [self sectionRect:i])) return HIT_SECTION + i;
    for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
        if (self.rows[k].activate) { if (NSPointInRect(p, [self valueRect:k])) return 10 * k + 1; continue; }
        if (NSPointInRect(p, [self arrow:k right:NO])) return 10 * k;
        if (NSPointInRect(p, [self arrow:k right:YES])) return 10 * k + 2;
        if (NSPointInRect(p, [self valueRect:k])) return 10 * k + 1;
    }
    if (self.open >= 0 && !NSPointInRect(p, self.flyRect)) return HIT_BACK;   /* a click outside the panel closes it */
    return HIT_NONE;
}
- (void)openSection:(NSInteger)i
{
    FFSection *s = self.sections[i]; self.focus = (NSInteger)self.top.count + i;
    if (s.activate) { s.activate(); self.needsDisplay = YES; return; }
    self.open = i; self.focus = 0; self.hover = HIT_NONE; self.needsDisplay = YES;
}
- (void)closeSection { if (self.open < 0) return; self.focus = (NSInteger)self.top.count + self.open; self.open = -1; self.hover = HIT_NONE; self.needsDisplay = YES; }
- (void)updateTrackingAreas
{
    for (NSTrackingArea *t in self.trackingAreas) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
    [super updateTrackingAreas];
}
- (void)mouseMoved:(NSEvent *)e { if (self.starting) return; NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]]; if (h != self.hover) { self.hover = h; self.needsDisplay = YES; } }
- (void)mouseDown:(NSEvent *)e { if (self.starting) return; self.pressed = [self hit:[self convertPoint:e.locationInWindow fromView:nil]]; self.needsDisplay = YES; }
- (void)mouseUp:(NSEvent *)e
{
    if (self.starting) return;
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]], p = self.pressed; self.pressed = HIT_NONE; self.needsDisplay = YES;
    if (h != p || h == HIT_NONE) return;
    [self press:h];
}
- (void)press:(NSInteger)h
{
    if (h == HIT_PLAY) { if (self.onPlay) self.onPlay(); return; }
    if (h == HIT_QUIT) { if (self.onQuit) self.onQuit(); return; }
    if (h == HIT_BACK) { [self closeSection]; return; }
    if (h >= HIT_SECTION) { [self openSection:h - HIT_SECTION]; return; }
    NSInteger k = h / 10; self.focus = k;
    if (self.rows[k].activate) { self.rows[k].activate(); self.needsDisplay = YES; return; }
    [self step:k by:(h % 10 == 0) ? -1 : 1];
}
- (void)step:(NSInteger)k by:(NSInteger)dir
{
    if (k >= (NSInteger)self.rows.count) { NSInteger n = [self items]; self.focus = (self.focus + dir + n) % n; self.needsDisplay = YES; return; }   /* the group buttons */
    FFRow *r = self.rows[k]; NSInteger n = (NSInteger)r.choices.count;
    if (r.activate) return;
    r.index = (r.index + dir + n) % n; self.needsDisplay = YES;
    if (self.onChange) self.onChange();
}
- (BOOL)key:(unsigned short)code
{
    if (self.starting) return NO;
    NSInteger n = [self items], rc = (NSInteger)self.rows.count;
    switch (code) {
    case 0x24: case 0x4c:                                                /* Return, Enter */
        if (self.focus >= rc) { [self openSection:self.focus - rc]; return YES; }
        if (rc && self.rows[self.focus].activate) { self.rows[self.focus].activate(); self.needsDisplay = YES; return YES; }
        if (self.open >= 0) { [self closeSection]; return YES; }
        if (self.onPlay) self.onPlay();
        return YES;
    case 0x35: if (self.open >= 0) { [self closeSection]; return YES; }  /* Escape */
               if (self.onQuit) self.onQuit();
               return YES;
    case 0x30: case 0x7d: if (n) { self.focus = (self.focus + 1) % n; self.needsDisplay = YES; } return YES;   /* Tab, down */
    case 0x7e: if (n) { self.focus = (self.focus + n - 1) % n; self.needsDisplay = YES; } return YES;
    case 0x7b: [self step:self.focus by:-1]; return YES;
    case 0x7c: [self step:self.focus by:1]; return YES;
    }
    return NO;
}
- (void)keyDown:(NSEvent *)e { if (![self key:e.keyCode]) [super keyDown:e]; }

// ---------------------------------------------------------------- drawing
/* a yellow menu button as the game draws them, black capitals; PLAY in Minuteman's red */
- (void)drawButton:(NSRect)r title:(NSString *)title code:(NSInteger)code primary:(BOOL)primary focused:(BOOL)focused
{
    BOOL hot = self.hover == code && !self.starting, down = self.pressed == code && hot;
    CGFloat lift = down ? 1.5 : hot ? 7 : 5; NSRect f = down ? NSOffsetRect(r, 3.5, 3.5) : hot ? NSOffsetRect(r, -1, -1) : r;
    NSColor *fill = primary ? (hot ? red_hot() : red()) : (hot ? yellow_hot() : yellow());
    comic_box(f, fill, lift, 3);
    NSGradient *shine = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:1 alpha:0.38], 0.0, [NSColor colorWithWhite:1 alpha:0.0], 0.55,
                         [NSColor colorWithWhite:0 alpha:0.10], 1.0, nil];
    [shine drawInRect:NSInsetRect(f, 3, 3) angle:-90];
    if (focused) { [cream() setStroke]; NSBezierPath *ring = [NSBezierPath bezierPathWithRect:NSInsetRect(f, -6, -6)]; ring.lineWidth = 2.5;
                   CGFloat dash[] = {9, 5}; [ring setLineDash:dash count:2 phase:0]; [ring stroke]; }
    NSFont *font = heavy(primary ? 32 : 26);
    NSDictionary *at = @{NSFontAttributeName: font, NSKernAttributeName: @1.5};
    CGFloat w = [title sizeWithAttributes:at].width, y = round(NSMidY(f) - font.ascender + font.capHeight / 2 + 1);
    if (primary) {
        draw_text(title, font, NSColor.whiteColor, NSMakeRect(NSMidX(f) - w / 2 - 4, y, w + 12, font.ascender - font.descender + 2), NSTextAlignmentCenter, 1.5, 3, nil);
        star(NSMakePoint(NSMidX(f) - w / 2 - 26, NSMidY(f)), 10, NSColor.whiteColor); star(NSMakePoint(NSMidX(f) + w / 2 + 26, NSMidY(f)), 10, NSColor.whiteColor);
    } else draw_text(title, font, ink(), NSMakeRect(NSMidX(f) - w / 2 - 4, y, w + 12, font.ascender - font.descender + 2), NSTextAlignmentCenter, 1.5, 0, nil);
}
- (void)drawArrow:(NSRect)r right:(BOOL)right lit:(BOOL)lit
{
    NSBezierPath *p = [NSBezierPath bezierPath]; CGFloat x0 = r.origin.x + 8, x1 = NSMaxX(r) - 8, y0 = r.origin.y + 5, y1 = NSMaxY(r) - 5, ym = NSMidY(r);
    if (right) { [p moveToPoint:NSMakePoint(x0, y0)]; [p lineToPoint:NSMakePoint(x1, ym)]; [p lineToPoint:NSMakePoint(x0, y1)]; }
    else { [p moveToPoint:NSMakePoint(x1, y0)]; [p lineToPoint:NSMakePoint(x0, ym)]; [p lineToPoint:NSMakePoint(x1, y1)]; }
    [p closePath];
    NSBezierPath *s = [p copy]; NSAffineTransform *t = [NSAffineTransform transform]; [t translateXBy:2.5 yBy:2.5]; [s transformUsingAffineTransform:t];
    [ink() setFill]; [s fill];
    [(lit ? NSColor.whiteColor : yellow()) setFill]; [p fill]; [ink() setStroke]; p.lineWidth = 2; p.lineJoinStyle = NSLineJoinStyleRound; [p stroke];
}
- (void)drawRows
{
    NSShadow *sh = soft_shadow();
    for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
        FFRow *row = self.rows[k]; NSRect r = [self rowRect:k]; NSDictionary *ch = row.choices[row.index];
        if (k == self.focus) { [[NSColor colorWithWhite:1 alpha:0.09] setFill]; NSRectFillUsingOperation(NSInsetRect(r, -14, -4), NSCompositingOperationSourceOver);
                               [yellow() setFill]; NSRectFill(NSMakeRect(r.origin.x - 14, r.origin.y - 4, 4, r.size.height + 8)); }
        draw_text(row.title.uppercaseString, heavy(24), yellow(), NSMakeRect(r.origin.x + 4, r.origin.y + 6, 300, 34), NSTextAlignmentLeft, 1.2, 3, sh);
        if (row.activate) {   /* a button in the row instead of a choice */
            NSRect v = NSInsetRect([self valueRect:k], 30, 0); BOOL hot = self.hover == 10 * k + 1, down = hot && self.pressed == 10 * k + 1;
            NSRect f = down ? NSOffsetRect(v, 2, 2) : v; comic_box(f, hot ? yellow_hot() : yellow(), down ? 1 : 4, 2.5);
            draw_text([ch[@"label"] uppercaseString], heavy(18), ink(), NSMakeRect(f.origin.x, f.origin.y + 4, f.size.width, 26), NSTextAlignmentCenter, 1, 0, nil);
        } else {
            [self drawArrow:[self arrow:k right:NO] right:NO lit:self.hover == 10 * k];
            [self drawArrow:[self arrow:k right:YES] right:YES lit:self.hover == 10 * k + 2];
            draw_text(ch[@"label"], demi(23), self.hover == 10 * k + 1 ? NSColor.whiteColor : cream(), [self valueRect:k], NSTextAlignmentCenter, 0.4, 0, sh);
        }
        draw_text(ch[@"note"] ?: @"", medium(14), dim(), NSMakeRect(NSMaxX(r) - 346, r.origin.y + 40, 360, 20), NSTextAlignmentCenter, 0.2, 0, sh);
        if (k + 1 < (NSInteger)self.rows.count) { [[NSColor colorWithWhite:1 alpha:0.12] setFill]; NSRectFillUsingOperation(NSMakeRect(r.origin.x, NSMaxY(r) + 5, r.size.width, 1), NSCompositingOperationSourceOver); }
    }
}
- (void)drawGuide:(NSArray<NSArray<NSString *> *> *)guide in:(NSRect)f
{
    NSShadow *sh = soft_shadow(); CGFloat y = f.origin.y + 84;
    for (NSArray<NSString *> *g in guide) {
        NSDictionary *at = @{NSFontAttributeName: heavy(17), NSKernAttributeName: @1};
        CGFloat w = MAX([g[0] sizeWithAttributes:at].width + 22, 56);
        NSRect cap = NSMakeRect(f.origin.x + 196 - w, y, w, 30); comic_box(cap, yellow(), 3, 2);   /* the key, right-aligned in its column */
        draw_text(g[0], heavy(17), ink(), NSMakeRect(cap.origin.x, y + 4, w, 24), NSTextAlignmentCenter, 1, 0, nil);
        draw_text(g[1], demi(18), cream(), NSMakeRect(f.origin.x + 220, y + 3, f.size.width - 250, 26), NSTextAlignmentLeft, 0.3, 0, sh);
        y += 44;
    }
    draw_text(@"Change them in the game: Options > Control.", medium(15), dim(), NSMakeRect(f.origin.x, NSMaxY(f) - 40, f.size.width, 22), NSTextAlignmentCenter, 0.2, 0, sh);
}
/* the window's art, drawn once: the Load Game screen's nebula under halftone dots, the banner over it */
- (NSImage *)renderBackdrop
{
    NSSize sz = self.bounds.size;
    return [NSImage imageWithSize:sz flipped:YES drawingHandler:^BOOL(NSRect dst) {
        [navy() setFill]; NSRectFill(dst);
        if (self.blue) draw_cover(self.blue, dst, NSMakePoint(0.5, 0.6), 0.42);
        NSGradient *vig = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:0.15], 0.0, [NSColor colorWithWhite:0 alpha:0.72], 1.0, nil];
        [vig drawInRect:dst relativeCenterPosition:NSMakePoint(0, 0.1)];
        [[NSColor colorWithWhite:0 alpha:0.28] setFill];       /* Ben-Day dots, larger towards the bottom */
        for (CGFloat y = BANNER_H + 6; y < sz.height; y += 9) for (CGFloat x = ((int)(y / 9) % 2) * 4.5; x < sz.width; x += 9) {
            CGFloat d = 1.2 + 2.6 * (y - BANNER_H) / (sz.height - BANNER_H); [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - d / 2, y - d / 2, d, d)] fill];
        }
        [self drawBanner:NSMakeRect(0, 0, sz.width, BANNER_H)];
        return YES;
    }];
}
- (void)drawBanner:(NSRect)br
{
    [NSGraphicsContext saveGraphicsState]; NSRectClip(br);
    [ink() setFill]; NSRectFill(br);
    if (self.useKeyart && self.keyart) {   /* GOG's banner: the team charging; its bottom fades to white for GOG's page, so shade it */
        draw_cover(self.keyart, br, NSMakePoint(0.62, 0.0), 1);
        NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:0], 0.0, [NSColor colorWithWhite:0 alpha:0.35], 0.45,
                         navy(), 1.0, nil];
        [g drawInRect:br angle:90];
    } else {
        if (self.nebula) draw_cover(self.nebula, br, NSMakePoint(0.5, 0.5), 1);
        else {   /* no art: a comic starburst in the game's blue and red */
            [navy() setFill]; NSRectFill(br); NSPoint c = NSMakePoint(br.size.width * 0.78, br.size.height * 0.45);
            for (int i = 0; i < 24; i++) {
                double a0 = i * M_PI / 12, a1 = a0 + M_PI / 24; NSBezierPath *ray = [NSBezierPath bezierPath];
                [ray moveToPoint:c]; [ray lineToPoint:NSMakePoint(c.x + 900 * cos(a0), c.y + 900 * sin(a0))]; [ray lineToPoint:NSMakePoint(c.x + 900 * cos(a1), c.y + 900 * sin(a1))];
                [ray closePath]; [(i % 3 == 0 ? [red() colorWithAlphaComponent:0.55] : rgb(28, 42, 118)) setFill]; [ray fill];
            }
            star(c, 64, cream()); star(NSMakePoint(c.x - 130, c.y + 70), 18, yellow()); star(NSMakePoint(c.x + 120, c.y - 60), 22, yellow());
        }
        if (self.heroes) {   /* the main menu's heroes on the right, fading out towards the logo */
            NSSize hs = self.heroes.size; CGFloat h = br.size.height + 8, w = h * hs.width / hs.height;
            NSRect hr = NSMakeRect(br.size.width - w + 26, br.size.height - 5 - h, w, h);
            NSImage *layer = [NSImage imageWithSize:hr.size flipped:YES drawingHandler:^BOOL(NSRect d) {
                [self.heroes drawInRect:d fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
                NSGradient *fade = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:1], 0.0, [NSColor colorWithWhite:0 alpha:0.0], 0.30, nil];
                [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationDestinationOut];
                [fade drawInRect:d angle:0];
                return YES;
            }];
            NSShadow *s = [NSShadow new]; s.shadowColor = [NSColor colorWithWhite:0 alpha:0.7]; s.shadowOffset = NSMakeSize(-4, -4); s.shadowBlurRadius = 8;
            [NSGraphicsContext saveGraphicsState]; [s set];
            [layer drawInRect:hr fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
            [NSGraphicsContext restoreGraphicsState];
        }
        NSGradient *left = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:0.55], 0.0, [NSColor colorWithWhite:0 alpha:0], 0.5, nil];
        [left drawInRect:br angle:0];
    }
    NSRect lr = NSMakeRect(22, 14, 360, 200);   /* the logo on the left, the subtitle under it */
    if (self.logo) {
        CGFloat h = lr.size.height, w = h * self.logo.size.width / self.logo.size.height; if (w > lr.size.width) { w = lr.size.width; h = w * self.logo.size.height / self.logo.size.width; }
        NSShadow *glow = [NSShadow new]; glow.shadowColor = [NSColor colorWithWhite:0 alpha:0.9]; glow.shadowOffset = NSMakeSize(3, -4); glow.shadowBlurRadius = 10;
        [NSGraphicsContext saveGraphicsState]; [glow set];
        [self.logo drawInRect:NSMakeRect(NSMidX(lr) - w / 2, lr.origin.y + (lr.size.height - h) / 2, w, h) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        [NSGraphicsContext restoreGraphicsState];
    } else {
        draw_text(@"FREEDOM", heavy(72), cream(), NSMakeRect(lr.origin.x, 30, lr.size.width, 84), NSTextAlignmentCenter, 2, 5, soft_shadow());
        draw_text(@"FORCE", heavy(80), yellow(), NSMakeRect(lr.origin.x, 104, lr.size.width, 92), NSTextAlignmentCenter, 2, 5, soft_shadow());
    }
    draw_text(self.subtitle ?: @"NATIVE EDITION FOR macOS", heavy(19), yellow(), NSMakeRect(lr.origin.x - 20, NSMaxY(lr) + 10, lr.size.width + 40, 28), NSTextAlignmentCenter, 3, 3, soft_shadow());
    [ink() setFill]; NSRectFill(NSMakeRect(0, BANNER_H - 5, br.size.width, 5));        /* the panel border, as the menu's black bars */
    [yellow() setFill]; NSRectFill(NSMakeRect(0, BANNER_H - 7, br.size.width, 2));
    [NSGraphicsContext restoreGraphicsState];
}
- (void)drawSectionTitle:(NSString *)title in:(NSRect)f
{
    NSRect bar = NSMakeRect(f.origin.x, f.origin.y, f.size.width, 48);   /* the game's dialog title bar: pale yellow, black text */
    comic_box(bar, pale(), 0, 3);
    draw_text(title.uppercaseString, heavy(27), ink(), NSMakeRect(bar.origin.x + 22, bar.origin.y + 7, bar.size.width - 44, 36), NSTextAlignmentLeft, 1.5, 0, nil);
    star(NSMakePoint(NSMaxX(bar) - 30, NSMidY(bar)), 11, red());
}
- (void)drawRect:(NSRect)dirty
{
    NSRect b = self.bounds; NSShadow *sh = soft_shadow();
    if (!self.backdrop || !NSEqualSizes(self.backdrop.size, b.size)) self.backdrop = [self renderBackdrop];
    [self.backdrop drawInRect:b fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];
    /* the top level: the rows in a comic panel, then a button for each group with a summary under it */
    NSInteger fly = self.open, foc = self.focus, hov = self.hover; self.open = -1;
    if (fly >= 0) self.focus = self.hover = HIT_NONE;           /* under the panel: nothing lit */
    comic_box(self.topPanel, [navy() colorWithAlphaComponent:0.86], 7, 3);
    [[yellow() colorWithAlphaComponent:0.55] setStroke]; NSBezierPath *kl = [NSBezierPath bezierPathWithRect:NSInsetRect(self.topPanel, 6.5, 6.5)]; kl.lineWidth = 1; [kl stroke];
    [self drawRows];
    for (NSInteger i = 0; i < (NSInteger)self.sections.count; i++) {
        FFSection *s = self.sections[i]; NSRect r = [self sectionRect:i];
        [self drawButton:r title:s.title.uppercaseString code:HIT_SECTION + i primary:NO focused:fly < 0 && self.focus == (NSInteger)self.top.count + i];
        NSString *sum = s.summary ? s.summary() : nil;
        if (!sum) { NSMutableArray *l = [NSMutableArray array]; for (FFRow *row in s.rows) [l addObject:row.choices[row.index][@"label"]]; sum = [l componentsJoinedByString:@" · "]; }
        draw_text(sum, medium(14.5), cream(), NSMakeRect(r.origin.x - 14, NSMaxY(r) + 13, r.size.width + 28, 22), NSTextAlignmentCenter, 0.2, 0, sh);
    }
    if (self.note.length) draw_text(self.note, medium(14), dim(), NSMakeRect(52, b.size.height - 136, b.size.width - 104, 22), NSTextAlignmentCenter, 0.2, 0, sh);
    self.open = fly; self.focus = foc; self.hover = hov;
    if (self.open >= 0) {   /* an open group: a panel over the window */
        [[NSColor colorWithWhite:0 alpha:0.62] setFill]; NSRectFillUsingOperation(b, NSCompositingOperationSourceOver);
        NSRect f = self.flyRect; FFSection *s = self.sections[self.open];
        comic_box(f, [navy() colorWithAlphaComponent:0.97], 9, 3);
        [self drawSectionTitle:s.title in:f];
        if (s.guide) [self drawGuide:s.guide in:f]; else [self drawRows];
    }
    [self drawButton:self.quitRect title:self.open >= 0 ? @"BACK" : @"QUIT" code:self.open >= 0 ? HIT_BACK : HIT_QUIT primary:NO focused:NO];
    [self drawButton:self.playRect title:self.starting ? @"STARTING" : @"PLAY" code:HIT_PLAY primary:YES focused:NO];
    if (self.footer.length) draw_text(self.footer, medium(11.5), [dim() colorWithAlphaComponent:0.7], NSMakeRect(0, b.size.height - 24, b.size.width, 16), NSTextAlignmentCenter, 0.6, 0, nil);
}
@end

// ---------------------------------------------------------------- art, updates
/* the art: <data>/art, else the copy in the app (Resources/art) */
static NSImage *art(NSString *data, NSString *name)
{
    NSMutableArray *dirs = [NSMutableArray arrayWithObject:[data stringByAppendingPathComponent:@"art"]];
    if (NSBundle.mainBundle.resourcePath) [dirs addObject:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"art"]];
    for (NSString *d in dirs) for (NSString *ext in @[@"png", @"jpg"]) {
        NSImage *i = [[NSImage alloc] initWithContentsOfFile:[[d stringByAppendingPathComponent:name] stringByAppendingPathExtension:ext]];
        if (i.size.width > 16) return i;
    }
    return nil;
}
/* the part of an image with any opacity (Steam's logos come with empty margins) */
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
    NSImage *r = [[NSImage alloc] initWithCGImage:t size:NSZeroSize]; CGImageRelease(t);
    return r;
}

@interface FFBlockTarget : NSObject
@property (copy) void (^fire)(NSInteger);
@end
@implementation FFBlockTarget
- (void)clicked:(NSControl *)sender { self.fire(sender.tag); }
@end

/* install.sh gives each app an updater (Contents/MacOS/update, passed in DS_UPDATER): it fetches the branch the app
 * follows (main, or nightly for Nightly) from GitHub and rebuilds the app from it, keeping the game folder, saves and
 * settings. The launcher asks GitHub (in the background, each time it opens) whether that branch moved past the commit
 * the app was built from. */
enum { UPD_NONE, UPD_CHECKING, UPD_CURRENT, UPD_AVAILABLE, UPD_ERROR };
static void on_main(dispatch_block_t b) { CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, b); CFRunLoopWakeUp(CFRunLoopGetMain()); }
static NSString *short_commit(NSString *c) { return c.length > 7 ? [c substringToIndex:7] : (c ?: @""); }
static NSString *update_check(NSString *updater)   /* the newest commit of the branch on GitHub; nil if it can't be reached */
{
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"]; t.arguments = @[updater, @"--check"];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{ if (t.running) [t terminate]; });
    NSData *d = [p.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    NSString *out = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.terminationStatus != 0 || !out.length) return nil;
    if (out.length >= 40) return [out substringToIndex:40];   /* a commit (an app built from source) */
    return [out rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound ? out : nil;   /* a release's tag (the downloaded app) */
}
static NSString *update_summary(int state, NSString *branch, NSString *built, NSString *latest)
{
    switch (state) {
    case UPD_CHECKING: return [NSString stringWithFormat:@"Checking GitHub for the newest %@…", branch];
    case UPD_CURRENT: return [NSString stringWithFormat:@"Up to date · %@ %@", branch, short_commit(built)];
    case UPD_AVAILABLE: return [NSString stringWithFormat:@"Update ready: %@ → %@", short_commit(built), short_commit(latest)];
    case UPD_ERROR: return @"Couldn't reach GitHub · press to retry";
    }
    return @"Not installed from GitHub: no updates";
}
/* the phase of install.sh's output, in words */
static NSString *update_phase(NSString *line, NSString *branch)
{
    if ([branch isEqualToString:@"release"]) {   /* the downloaded app's updater (setup/update.sh) */
        if ([line hasPrefix:@"== downloading "]) return [NSString stringWithFormat:@"Downloading %@ from GitHub", [line substringFromIndex:15]];
        if ([line hasPrefix:@"== unpacking"]) return @"Unpacking it";
        if ([line hasPrefix:@"== installing"]) return @"Installing the new app";
        return nil;
    }
    if ([line hasPrefix:@"== fetching"]) return @"Downloading the update from GitHub";
    if ([line hasPrefix:[NSString stringWithFormat:@"== %@:", branch]]) return [@"Got " stringByAppendingString:[line substringFromIndex:branch.length + 4]];
    if ([line hasPrefix:@"== analysis"]) return @"Rebuilding from your game: analysing its code (1 of 4)";
    if ([line hasPrefix:@"== lifting"]) return @"Rebuilding from your game: translating to native code (2 of 4)";
    if ([line hasPrefix:@"== compiling"]) return @"Rebuilding from your game: compiling (3 of 4)";
    if ([line hasPrefix:@"== installing"]) return @"Installing the new app (4 of 4)";
    return nil;
}
/* runs the updater with a progress window (modal); returns YES when the app was rebuilt */
static BOOL update_run(NSWindow *parent, NSString *updater, NSString *branch, NSString *logPath)
{
    NSPanel *pn = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 170) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    pn.title = @"Updating";
    NSTextField *title = [NSTextField labelWithString:@"Updating to the newest version"]; title.font = [NSFont boldSystemFontOfSize:14]; title.frame = NSMakeRect(20, 128, 480, 22);
    NSTextField *status = [NSTextField wrappingLabelWithString:@"Starting..."]; status.frame = NSMakeRect(20, 64, 480, 56);
    NSProgressIndicator *spin = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 44, 480, 12)]; spin.indeterminate = YES; [spin startAnimation:nil];
    NSTextField *time = [NSTextField labelWithString:@"This takes a few minutes. Your saves and settings are kept."]; time.font = [NSFont systemFontOfSize:11]; time.textColor = NSColor.secondaryLabelColor; time.frame = NSMakeRect(20, 14, 360, 18);
    NSButton *btn = [NSButton buttonWithTitle:@"Close" target:nil action:nil]; btn.frame = NSMakeRect(400, 8, 100, 30); btn.hidden = YES;
    for (NSView *x in @[title, status, spin, time, btn]) [pn.contentView addSubview:x];
    if (parent) [pn setFrameOrigin:NSMakePoint(NSMidX(parent.frame) - 260, NSMidY(parent.frame) - 85)]; else [pn center];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath];
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"]; t.arguments = @[updater];
    NSPipe *pipe = [NSPipe pipe]; t.standardOutput = pipe; t.standardError = pipe;
    NSMutableString *pending = [NSMutableString new], *tail = [NSMutableString new];
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        [log writeData:d];
        NSString *chunk = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
        @synchronized (pending) {
            [pending appendString:chunk];
            NSRange nl;
            while ((nl = [pending rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [pending substringToIndex:nl.location]; [pending deleteCharactersInRange:NSMakeRange(0, nl.location + 1)];
                [tail appendFormat:@"%@\n", line]; if (tail.length > 600) [tail deleteCharactersInRange:NSMakeRange(0, tail.length - 600)];
                NSString *ph = update_phase(line, branch);
                if (ph) on_main(^{ status.stringValue = ph; });
            }
        }
    };
    __block BOOL ok = NO;
    __attribute__((objc_precise_lifetime)) FFBlockTarget *bt = [FFBlockTarget new];   /* a button's target is weak: kept here */
    bt.fire = ^(NSInteger tag) { (void)tag; [NSApp stopModal]; };
    btn.target = bt; btn.action = @selector(clicked:);
    t.terminationHandler = ^(NSTask *task) {
        int code = task.terminationStatus;
        on_main(^{
            pipe.fileHandleForReading.readabilityHandler = nil; [log closeFile];
            [spin stopAnimation:nil]; spin.hidden = YES; btn.hidden = NO;
            if (code == 0) { ok = YES; title.stringValue = @"Updated"; status.stringValue = @"The new version is installed. The app restarts when you press Restart."; btn.title = @"Restart"; }
            else {
                NSString *last; @synchronized (pending) { last = [[tail componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "]; }
                title.stringValue = @"The update didn't finish";
                status.stringValue = [NSString stringWithFormat:@"Nothing was changed if it stopped before installing. Details: %@  (%@)", logPath,
                                      last.length > 160 ? [last substringFromIndex:last.length - 160] : last];
                time.stringValue = @"";
            }
        });
    };
    if (![t launchAndReturnError:nil]) { [log closeFile]; return NO; }
    [pn makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:pn];
    [pn orderOut:nil];
    return ok;
}

// ---------------------------------------------------------------- the window
/* The rows and groups for the saved settings (ff_settings' keys); each change goes back into `settings`. */
static FFLaunchView *ff_launch_view(NSMutableDictionary *settings, NSString *data)
{
    FFLaunchView *v = [[FFLaunchView alloc] initWithFrame:NSMakeRect(0, 0, WIN_W, WIN_H)];
    FFRow *(^row)(NSString *, NSString *, NSArray *) = ^FFRow *(NSString *title, NSString *key, NSArray *choices) {
        FFRow *r = [FFRow new]; r.title = title; r.key = key; r.choices = choices; r.index = index_of(choices, settings[key], 0); return r;
    };
    FFRow *res = row(@"Resolution", @"resolution", resolution_choices(settings[@"resolution"])), *lang = row(@"Language", @"language", language_choices());
    FFRow *window = row(@"Window", @"fullscreen", window_choices()), *notch = row(@"Notch", @"notch", notch_choices());
    FFRow *fps = row(@"Frame Rate", @"frameRate", framerate_choices()), *vsync = row(@"Vertical Sync", @"vsync", vsync_choices());
    NSArray<FFRow *> *all = @[res, lang, window, notch, fps, vsync];
    for (FFRow *r in all) settings[r.key] = r.choices[r.index][@"value"];   /* a saved value no longer offered: the first choice */
    v.onChange = ^{ for (FFRow *r in all) settings[r.key] = r.choices[r.index][@"value"]; };
    FFSection *display = [FFSection new], *guide = [FFSection new], *files = [FFSection new], *updates = [FFSection new];
    display.title = @"Display"; display.rows = notch_height() > 0 ? @[window, notch, fps, vsync] : @[window, fps, vsync];
    NSArray<FFRow *> *shown = display.rows;
    display.summary = ^NSString * {
        NSMutableArray *l = [NSMutableArray array]; for (FFRow *r in shown) if (r != vsync) [l addObject:r.choices[r.index][@"label"]];
        [l addObject:[vsync.choices[vsync.index][@"value"] boolValue] ? @"VSync" : @"No VSync"]; return [l componentsJoinedByString:@" · "];
    };
    guide.title = @"Key Guide"; guide.guide = key_guide(); guide.summary = ^NSString * { return @"Mouse, camera and quick-save keys"; };
    FFRow *(^open)(NSString *, NSString *, NSString *, NSString *(^)(void)) = ^FFRow *(NSString *title, NSString *label, NSString *note, NSString *(^path)(void)) {
        FFRow *r = [FFRow new]; r.title = title; r.choices = @[@{@"value": @"", @"label": label, @"note": note}];
        r.activate = ^{ NSString *p = path(); if (p) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:p]]]; };
        return r;
    };
    files.title = @"Files"; files.summary = ^NSString * { return @"Saved games, settings and play logs"; };
    files.rows = @[open(@"Saved Games", @"Show", @"Your campaigns, kept across updates", ^NSString * {
                        NSString *p = [data stringByAppendingPathComponent:@"game/data/SaveGames"];
                        [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil]; return p; }),
                   open(@"Data Folder", @"Show", @"Settings, language files, crash reports", ^NSString * { return data; }),
                   open(@"Last Play Log", @"Show", @"What the last game wrote: for bug reports", ^NSString * {
                        NSString *l = getenv("DS_LOG_FILE") ? @(getenv("DS_LOG_FILE")) : nil;
                        if (l && [NSFileManager.defaultManager fileExistsAtPath:l]) return l;
                        NSAlert *a = [NSAlert new]; a.messageText = @"No play log yet"; a.informativeText = @"The app writes one each time the game runs. Press Play, then come back here.";
                        [a runModal]; return nil; })];
    updates.title = @"Updates";
    v.top = @[res, lang]; v.sections = @[display, guide, files, updates]; v.open = -1; v.hover = v.pressed = HIT_NONE;
    v.note = @"Sound, controls and detail: in the game's own Options. F11 and F12 quick save and load.";
    return v;
}

int ds_launcher_run(const char *game_dir, const char *data_dir)
{
    NSString *data = @(data_dir), *plist = [data stringByAppendingPathComponent:@"launcher.plist"]; (void)game_dir;
    NSMutableDictionary *settings = [ff_settings([NSDictionary dictionaryWithContentsOfFile:plist] ?: @{}) mutableCopy];
    const char *shot = getenv("DS_LAUNCHER_SHOT");
    if (getenv("DS_NO_LAUNCHER") && !shot) { ff_apply_settings(settings); return 1; }
    FFLaunchView *v = ff_launch_view(settings, data);
    NSString *updater = getenv("DS_UPDATER") ? @(getenv("DS_UPDATER")) : nil, *branch = getenv("DS_UPDATE_BRANCH") ? @(getenv("DS_UPDATE_BRANCH")) : @"main";
    NSString *built = getenv("DS_BUILT_COMMIT") ? @(getenv("DS_BUILT_COMMIT")) : @"";
    if (![NSFileManager.defaultManager isExecutableFileAtPath:updater ?: @""]) updater = nil;
    BOOL nightly = [branch isEqualToString:@"nightly"];
    v.subtitle = nightly ? @"NIGHTLY · NATIVE FOR macOS" : @"NATIVE EDITION FOR macOS";
    v.footer = [NSString stringWithFormat:@"BUILD %@ · METAL", built.length ? short_commit(built) : @DS_BUILD];
    v.nebula = art(data, @"nebula"); v.heroes = art(data, @"heroes"); v.blue = art(data, @"blue"); v.keyart = art(data, @"keyart");
    NSImage *logo = art(data, @"logo"); v.logo = logo ? trimmed(logo) : nil;
    v.useKeyart = getenv("FF_BANNER") ? !strcmp(getenv("FF_BANNER"), "keyart") : !v.heroes;
    FFSection *upd = v.sections.lastObject;
    __block int ustate = updater ? UPD_CHECKING : UPD_NONE; __block NSString *latest = nil;
    __weak FFLaunchView *wv = v;
    upd.summary = ^NSString * { return update_summary(ustate, branch, built, latest); };
    void (^check)(void) = ^{
        if (!updater) return;
        ustate = UPD_CHECKING; wv.needsDisplay = YES;
        void (^done)(NSString *) = ^(NSString *l) { latest = l; ustate = !l ? UPD_ERROR : [l isEqualToString:built] ? UPD_CURRENT : UPD_AVAILABLE; wv.needsDisplay = YES; };
        if (shot) { done(update_check(updater)); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ NSString *l = update_check(updater); on_main(^{ done(l); }); });
    };
    upd.activate = ^{
        if (ustate == UPD_CHECKING || !updater) return;
        if (ustate != UPD_AVAILABLE) { check(); return; }
        int lock = ff_session_lock(data, YES);
        if (lock < 0) { NSAlert *a = [NSAlert new]; a.messageText = @"Freedom Force is running"; a.informativeText = @"Quit the game before updating."; [a runModal]; return; }
        NSAlert *a = [NSAlert new];
        a.messageText = [NSString stringWithFormat:@"Update to the newest %@?", nightly ? @"Nightly" : @"version"];
        a.informativeText = [branch isEqualToString:@"release"] ? [NSString stringWithFormat:@"%@ is downloaded from GitHub and replaces this app. Your game, saves and settings are kept; if the game's code changed, it is rebuilt from your copy when the app starts again.", latest]
                          : [NSString stringWithFormat:@"The %@ branch (%@) is downloaded from GitHub and the app is rebuilt from your own copy of the game, "
                             "which takes a few minutes. Your game folder, saved games and settings are kept. The app restarts when it is done.", branch, short_commit(latest)];
        [a addButtonWithTitle:@"Update"]; [a addButtonWithTitle:@"Cancel"];
        if ([a runModal] != NSAlertFirstButtonReturn) { close(lock); return; }
        BOOL ok = update_run(wv.window, updater, branch, [data stringByAppendingPathComponent:@"update.log"]);
        close(lock);
        if (ok) {
            NSString *app = updater.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
            NSTask *o = [NSTask new]; o.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"]; o.arguments = @[@"-n", app];
            [o launchAndReturnError:nil]; [o waitUntilExit];
            exit(0);
        }
        check();
    };
    if (shot) {   /* development: the window as an image; no update is checked or installed */
        updater = nil; ustate = getenv("DS_UPDATER") ? UPD_CURRENT : UPD_NONE;
        const char *openName = getenv("DS_LAUNCHER_OPEN") ?: getenv("DS_LAUNCHER_SECTION");
        if (openName) for (NSInteger i = 0; i < (NSInteger)v.sections.count; i++) if ([v.sections[i].title caseInsensitiveCompare:@(openName)] == NSOrderedSame) v.open = i;
        if (getenv("DS_LAUNCHER_FOCUS")) v.focus = atoi(getenv("DS_LAUNCHER_FOCUS"));
        if (getenv("DS_LAUNCHER_HOVER")) v.hover = atoi(getenv("DS_LAUNCHER_HOVER"));
        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds]; [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        BOOL ok = [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(shot) atomically:YES];
        fprintf(stderr, "Freedom Force launcher preview: %s\n", ok ? "saved" : "failed");
        return 0;
    }
    NSWindow *w = [[NSWindow alloc] initWithContentRect:v.frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO; w.titlebarAppearsTransparent = YES; w.titleVisibility = NSWindowTitleHidden; w.movableByWindowBackground = YES;
    w.title = nightly ? @"Freedom Force Nightly" : @"Freedom Force"; w.backgroundColor = navy(); w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    w.contentView = v; [w center]; [w makeFirstResponder:v];
    __block int result = 0;
    v.onPlay = ^{
        NSError *error = nil;
        if (![settings writeToURL:[NSURL fileURLWithPath:plist] error:&error]) fprintf(stderr, "Freedom Force launcher: settings not saved: %s\n", error.localizedDescription.UTF8String);
        result = 1; [NSApp stopModal];
    };
    v.onQuit = ^{ result = 0; [NSApp stopModal]; };
    id closeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:w queue:nil usingBlock:^(NSNotification *n) { (void)n; [NSApp stopModal]; }];
    check();
    [NSApp activateIgnoringOtherApps:YES]; [w makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:w];
    [NSNotificationCenter.defaultCenter removeObserver:closeObserver];
    v.onPlay = nil; v.onQuit = nil; v.onChange = nil;
    if (result) { v.starting = YES; v.needsDisplay = YES; [w displayIfNeeded]; ff_apply_settings(settings); }
    [w orderOut:nil];
    return result;
}
