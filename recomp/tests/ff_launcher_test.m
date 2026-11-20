#import "../host/ff_launcher.m"
#include <assert.h>
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *root=@(argv[1]), *game=[root stringByAppendingPathComponent:@"install"], *overlay=[root stringByAppendingPathComponent:@"scratch/game"];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSArray *names=@[@"captions.dat",@"speech.dat",@"strings.dat"];
    for (NSString *lang in @[@"English/bak",@"German",@"French"]) {
        NSString *dir=[game stringByAppendingPathComponent:[@"Data/Lang/" stringByAppendingString:lang]];
        assert([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
        for (NSString *n in names) assert([[lang dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[dir stringByAppendingPathComponent:n] atomically:YES]);
    }
    for (NSString *lang in @[@"German",@"French",@"English"]) {
        assert(ff_language(game,overlay,lang,NULL));
        for (NSString *n in names) {
            NSString *v=[NSString stringWithContentsOfFile:[[overlay stringByAppendingPathComponent:@"data/Lang/English"] stringByAppendingPathComponent:n] encoding:NSUTF8StringEncoding error:nil];
            assert([v isEqual:[lang isEqual:@"English"] ? @"English/bak" : lang]);
        }
    }
    assert(!ff_language(game,overlay,@"../French",NULL));
    assert(!ff_language(@"/nonexistent-install",overlay,@"German",NULL));
    NSString *original=[NSString stringWithContentsOfFile:[game stringByAppendingPathComponent:@"Data/Lang/English/bak/strings.dat"] encoding:NSUTF8StringEncoding error:nil];
    assert([original isEqual:@"English/bak"]);
    assert([ff_game_arguments(@"French", nil) isEqual:@"-language french"]);
    assert([ff_game_arguments(@"German", @"-test untouched") isEqual:@"-language german -test untouched"]);
    NSDictionary *s=ff_settings(@{@"resolution":@"1440x900",@"fullscreen":@NO,@"notch":@"around",@"frameRate":@"60",@"vsync":@NO,@"language":@"German"});
    ff_apply_settings(s);
    assert(!strcmp(getenv("DS_RESOLUTION"),"1440x900") && !strcmp(getenv("DS_WINDOWED"),"1"));
    assert(!strcmp(getenv("DS_NOTCH"),"around") && !strcmp(getenv("DSR_FPSCAP"),"60"));
    assert(!strcmp(getenv("DSR_VSYNC"),"0") && !strcmp(getenv("FF_LANGUAGE"),"German"));
    s=ff_settings(@{@"resolution":@"1x2",@"frameRate":@"oops",@"language":@"Russian",@"fullscreen":@"no"});
    assert([s[@"resolution"] isEqual:@"display"] && [s[@"language"] isEqual:@"English"] && [s[@"fullscreen"] boolValue]);
    int play=ff_session_lock(root,NO); assert(play>=0 && ff_session_lock(root,YES)<0); close(play);
    int update=ff_session_lock(root,YES); assert(update>=0 && ff_session_lock(root,NO)<0); close(update);
    [NSApplication sharedApplication];
    /* the window: rows cycle by arrow keys and clicks, groups open and close, and every choice lands in the settings
     * as ff_settings reads them back */
    NSMutableDictionary *set=[ff_settings(@{@"language":@"English",@"fullscreen":@YES,@"vsync":@YES}) mutableCopy];
    FFLaunchView *view=ff_launch_view(set,root);
    __block BOOL quit=NO, played=NO; view.onQuit=^{ quit=YES; }; view.onPlay=^{ played=YES; };
    assert(view.top.count==2 && view.sections.count==4 && view.open==-1 && [view items]==6);
    assert([view key:0x7d] && view.focus==1);                                   /* down: Language */
    assert([view key:0x7c] && [set[@"language"] isEqual:@"German"]);           /* right: the next language */
    assert([view key:0x7b] && [view key:0x7b] && [set[@"language"] isEqual:@"French"]);   /* left wraps round */
    NSRect a=[view arrow:0 right:YES]; NSInteger h=[view hit:NSMakePoint(NSMidX(a),NSMidY(a))]; assert(h==2);
    [view press:h]; assert(![set[@"resolution"] isEqual:@"display"] && [ff_settings(set)[@"resolution"] isEqual:set[@"resolution"]]);
    [view press:[view hit:NSMakePoint(NSMidX([view arrow:0 right:NO]),NSMidY([view arrow:0 right:NO]))]]; assert([set[@"resolution"] isEqual:@"display"]);
    NSRect d=[view sectionRect:0]; assert([view hit:NSMakePoint(NSMidX(d),NSMidY(d))]==HIT_SECTION);
    view.focus=2; assert([view key:0x24] && view.open==0 && view.focus==0);   /* Return on Display opens it */
    assert([view.sections[0].title isEqual:@"Display"] && [view.rows.firstObject.key isEqual:@"fullscreen"]);
    assert([view key:0x7c] && [set[@"fullscreen"] isEqual:@NO] && ![ff_settings(set)[@"fullscreen"] boolValue]);
    FFRow *vs=nil; for (FFRow *r in view.rows) if ([r.key isEqual:@"vsync"]) vs=r;
    view.focus=(NSInteger)[view.rows indexOfObject:vs]; assert([view key:0x7c] && ![ff_settings(set)[@"vsync"] boolValue]);
    assert([view.sections[0].summary() containsString:@"Window"] && [view.sections[0].summary() containsString:@"No VSync"]);
    NSRect q=view.quitRect; assert([view hit:NSMakePoint(NSMidX(q),NSMidY(q))]==HIT_BACK);
    assert([view key:0x35] && view.open==-1 && !quit);                          /* Escape closes the group */
    assert(view.focus==2);                                                      /* back on its button */
    view.focus=3; assert([view key:0x24] && view.open==1 && view.sections[1].guide.count>=6);   /* the Key Guide */
    assert([view key:0x35] && view.open==-1);
    view.focus=4; assert([view key:0x24] && view.open==2 && view.rows.count==3 && view.rows[0].activate);   /* Files: buttons, not choices */
    NSRect v=[view valueRect:0]; assert([view hit:NSMakePoint(NSMidX(v),NSMidY(v))]==1 && [view hit:NSMakePoint(NSMidX([view arrow:0 right:YES]),NSMidY([view arrow:0 right:YES]))]==HIT_NONE);
    assert([view key:0x35] && view.focus==4); view.focus=0; assert([view key:0x24] && played);   /* Return on a row at the top level plays */
    assert([view key:0x35] && quit);
    NSDictionary *saved=ff_settings(set); assert([saved[@"language"] isEqual:@"French"] && ![saved[@"fullscreen"] boolValue] && ![saved[@"vsync"] boolValue]);
    NSString *pl=[root stringByAppendingPathComponent:@"launcher.plist"]; assert([set writeToFile:pl atomically:YES]);
    assert([ff_settings([NSDictionary dictionaryWithContentsOfFile:pl]) isEqual:saved]);   /* the saved file reads back the same */
    puts("Freedom Force launcher: settings, language overlay/restoration, invalid input, game/update exclusion, and the window's rows, groups, keys and clicks passed");
} return 0; }
