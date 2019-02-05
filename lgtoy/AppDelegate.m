//
//  AppDelegate.m
//  lgtoy
//

//

#import "AppDelegate.h"
#import "GGMTLRenderer.h"
#import "LKGManager.h"

@import MetalKit;

@implementation AppDelegate {
    LKGManager *_lkgManager;
    uint8_t _buttons;

    MTKView *_mtlView;
    GGMTLRenderer *_renderer;    
}

- (void)log:(NSString*)message {
    // append a line
    NSAttributedString* attr = [[NSAttributedString alloc] initWithString:[message stringByAppendingString:@"\n"]];
    [[textView textStorage] appendAttributedString:attr];
    [textView scrollRangeToVisible:NSMakeRange([[textView string] length], 0)];
}

#pragma mark NSApplication delegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self log:@"Creates fullscreen window on LookingGlass screen..."];
    _lkgManager = [[LKGManager alloc] initWithDelegate:(id<LKGManagerProtocol>)self];
}

#pragma mark LKGManager delegate

- (void)LKGManager:(LKGManager*)manager calibration:(NSDictionary*)dict {
    [self log:(dict?@"Calibration loaded":@"Calibration missing")];
    if(dict) [_renderer loadCalibration:dict];
}

- (void)LKGManager:(LKGManager*)manager buttons:(uint8_t)buttons {
    const uint8_t change = _buttons ^ buttons;
    _buttons = buttons;
    const char *names[] = {"Square", "Left", "Right", "Circle"};
    for(int i = 0; i < 4; i++) {
        uint8_t mask = 1<<i;
        if(change&mask) [self log:[NSString stringWithFormat:@"Button %s %s", names[i], (buttons&mask)?"down":"up"]];
    }
}

- (void)LKGManager:(LKGManager*)manager screen:(NSScreen*)screen {
    [self log:(screen?@"Screen found":@"Screen missing")];
    if(screen) {
        NSRect screenFrame = [screen frame];
        if(!_mtlView) {
            // create fullscreen window
            NSRect frame = [NSWindow contentRectForFrameRect:screenFrame styleMask:NSWindowStyleMaskBorderless];
            NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES screen:screen];
            [window setFrame:screenFrame display:NO];
            window.level = NSScreenSaverWindowLevel;
            window.releasedWhenClosed = NO; // otherwise crashes on close
            
            // device for the screen
            CGDirectDisplayID display = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
            id<MTLDevice> device = CGDirectDisplayCopyCurrentMetalDevice(display);
            
            _mtlView = [[MTKView alloc] initWithFrame:NSRectToCGRect(frame) device:device];
            _mtlView.preferredFramesPerSecond = 60;
            window.contentView = _mtlView;
            
            _renderer = [[GGMTLRenderer alloc] initWithMetalKitView:_mtlView];
            [_renderer mtkView:_mtlView drawableSizeWillChange:_mtlView.drawableSize];
            _mtlView.delegate = _renderer;

            [window orderFront:nil];
        } else {
            // re-position
            NSWindow *window = _mtlView.window;
            [window setFrame:screenFrame display:NO];
        }
    } else {
        if(_mtlView) {
            // destroy
            NSWindow *window = _mtlView.window;
            [window close];
            
            _mtlView = nil;
            _renderer = nil;
        }
    }
}

@end
