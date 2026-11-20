// Freedom Force launch settings shared by the window, host and synthetic tests.
#import <AppKit/AppKit.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
// The host holds a shared lock for its lifetime; an update holds the exclusive lock.
static int ff_session_lock(NSString *data, BOOL update)
{
    int fd = open([[data stringByAppendingPathComponent:@".game-session.lock"] fileSystemRepresentation], O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (fd >= 0 && flock(fd, (update ? LOCK_EX : LOCK_SH) | LOCK_NB)) { close(fd); return -1; }
    return fd;
}

static NSDictionary *ff_settings(NSDictionary *saved)
{
    NSMutableDictionary *s = [@{@"resolution": @"display", @"frameRate": @"120", @"notch": @"below",
                                 @"fullscreen": @YES, @"vsync": @YES, @"language": @"English"} mutableCopy];
    for (NSString *key in @[@"resolution", @"frameRate", @"notch", @"language"])
        if ([saved[key] isKindOfClass:NSString.class]) s[key] = saved[key];
    for (NSString *key in @[@"fullscreen", @"vsync"])
        if ([saved[key] isKindOfClass:NSNumber.class]) s[key] = @([saved[key] boolValue]);
    if (![@[@"English", @"German", @"French"] containsObject:s[@"language"]]) s[@"language"] = @"English";
    if (![@[@"below", @"around"] containsObject:s[@"notch"]]) s[@"notch"] = @"below";
    if (![@[@"30", @"60", @"120", @"unlimited"] containsObject:s[@"frameRate"]]) s[@"frameRate"] = @"120";
    int w = 0, h = 0; char extra;
    if (![s[@"resolution"] isEqual:@"display"] &&
        (sscanf([s[@"resolution"] UTF8String], "%dx%d%c", &w, &h, &extra) != 2 || w < 640 || h < 480 || w > 7680 || h > 4320)) s[@"resolution"] = @"display";
    return s;
}
static void ff_apply_settings(NSDictionary *s)
{
    NSString *res = s[@"resolution"];
    if ([res isEqual:@"display"]) {
        NSRect r = NSScreen.mainScreen.frame;
        if (@available(macOS 12.0, *)) if ([s[@"notch"] isEqual:@"below"]) r.size.height -= NSScreen.mainScreen.safeAreaInsets.top;
        res = [NSString stringWithFormat:@"%dx%d", (int)r.size.width, (int)r.size.height];
    }
    setenv("DS_RESOLUTION", res.UTF8String, 1);
    setenv("DS_WINDOWED", [s[@"fullscreen"] boolValue] ? "0" : "1", 1);
    setenv("DS_NOTCH", [s[@"notch"] UTF8String], 1);
    setenv("DSR_FPSCAP", [s[@"frameRate"] isEqual:@"unlimited"] ? "0" : [s[@"frameRate"] UTF8String], 1);
    setenv("DSR_VSYNC", [s[@"vsync"] boolValue] ? "1" : "0", 1);
    setenv("FF_LANGUAGE", [s[@"language"] UTF8String], 1);
    fprintf(stderr, "Freedom Force settings: resolution=%s windowed=%s notch=%s fps=%s vsync=%s language=%s\n",
            getenv("DS_RESOLUTION"), getenv("DS_WINDOWED"), getenv("DS_NOTCH"), getenv("DSR_FPSCAP"), getenv("DSR_VSYNC"), getenv("FF_LANGUAGE"));
}
// The engine's own option also chooses its localized dialog layouts (not just text files).
static NSString *ff_game_arguments(NSString *language, NSString *extra)
{
    return [NSString stringWithFormat:@"-language %@%@%@", language.lowercaseString,
            extra.length ? @" " : @"", extra ?: @""];
}
/* GOG language_setup.ini's three-file substitution, exclusively in the writable overlay.
 * Read all sources before writing, so a missing language leaves the previous selection intact. */
static BOOL ff_language(NSString *game, NSString *overlay, NSString *language, NSError **error)
{
    if (![@[@"English", @"German", @"French"] containsObject:language]) {
        if (error) *error = [NSError errorWithDomain:@"FreedomForce" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Unsupported language"}];
        return NO;
    }
    NSString *source = [game stringByAppendingPathComponent:[@"Data/Lang/" stringByAppendingString:language]];
    NSMutableArray<NSData *> *files = [NSMutableArray new];
    NSArray *names = @[@"captions.dat", @"speech.dat", @"strings.dat"];
    for (NSString *name in names) {
        NSString *path = [source stringByAppendingPathComponent:name];
        if ([language isEqual:@"English"] && [NSFileManager.defaultManager fileExistsAtPath:[source stringByAppendingPathComponent:@"bak"]])
            path = [[source stringByAppendingPathComponent:@"bak"] stringByAppendingPathComponent:name];
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
        if (!data) return NO;
        [files addObject:data];
    }
    NSString *target = [overlay stringByAppendingPathComponent:@"data/Lang/English"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    for (NSUInteger i = 0; i < names.count; i++) if (![files[i] writeToFile:[target stringByAppendingPathComponent:names[i]] options:NSDataWritingAtomic error:error]) return NO;
    fprintf(stderr, "Freedom Force language: %s (%s)\n", language.UTF8String, target.UTF8String);
    return YES;
}
