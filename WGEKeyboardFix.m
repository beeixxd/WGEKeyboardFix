#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEAppTransitionActive = NO;
static BOOL gWGEUserIsInteracting = NO;
static BOOL gWGEAppIsLockedState = NO;
static BOOL gWGEIsAppLockScreenShowing = YES;

static NSArray<UIWindow *> *WGEAllWindows(void) {
    NSMutableArray<UIWindow *> *result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w) [result addObject:w];
            }
        }
    }
    if (result.count == 0) {
        NSArray *legacyWindows = [UIApplication sharedApplication].windows;
        if (legacyWindows) [result addObjectsFromArray:legacyWindows];
    }
    return result;
}

static void WGERunFullCleanup(void) {
    if (gWGEAppIsLockedState) {
        return;
    }
    
    if (!gWGEIsAppLockScreenShowing && !gWGEUserIsInteracting) {
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    }

    for (UIWindow *w in WGEAllWindows()) {
        NSString *windowClassName = NSStringFromClass([w class]);
        if ([windowClassName rangeOfString:@"Passcode"].location != NSNotFound ||
            [windowClassName rangeOfString:@"Secure"].location != NSNotFound) {
            continue;
        }

        BOOL isKeyboardWindow = [windowClassName containsString:@"TextEffects"] || [windowClassName containsString:@"Keyboard"];
        if (isKeyboardWindow) {
            if (!gWGEIsAppLockScreenShowing && !gWGEUserIsInteracting) {
                w.hidden = YES;
                w.alpha = 0.0;
                for (UIView *subview in [w subviews]) {
                    subview.hidden = YES;
                    subview.alpha = 0.0;
                }
            } else if (gWGEIsAppLockScreenShowing && w.frame.size.height < 100) {
                w.alpha = 0.0;
            }
        }
    }
}

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (gWGEIsAppLockScreenShowing) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    if (gWGEAppIsLockedState || gWGEAppTransitionActive) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    if (!gWGEUserIsInteracting) {
        WGERunFullCleanup();
        return NO;
    }
    
    return orig_becomeFirstResponder(self, _cmd);
}

static void (*orig_windowSendEvent)(id, SEL, UIEvent *);
static void new_windowSendEvent(id self, SEL _cmd, UIEvent *event) {
    if (event && event.type == UIEventTypeTouches) {
        gWGEUserIsInteracting = YES;
    }
    orig_windowSendEvent(self, _cmd, event);
    if (event && event.type == UIEventTypeTouches) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gWGEUserIsInteracting = NO;
        });
    }
}

@interface WGEKeyboardUltimatePerfectFixer : NSObject
@end

@implementation WGEKeyboardUltimatePerfectFixer

+ (void)load {
    static WGEKeyboardUltimatePerfectFixer *fixer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fixer = [[WGEKeyboardUltimatePerfectFixer alloc] init];
        
        Class viewClass = [UIView class];
        Method m1 = class_getInstanceMethod(viewClass, @selector(becomeFirstResponder));
        if (m1) {
            orig_becomeFirstResponder = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)new_becomeFirstResponder);
        }
        
        Class windowClass = [UIWindow class];
        Method m2 = class_getInstanceMethod(windowClass, @selector(sendEvent:));
        if (m2) {
            orig_windowSendEvent = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)new_windowSendEvent);
        }
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        
        [center addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
    });
}

- (void)onLockOrBackground {
    gWGEAppIsLockedState = YES;
    gWGEAppTransitionActive = YES;
    gWGEIsAppLockScreenShowing = YES;
}

- (void)onUnlockOrActive {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEAppTransitionActive = NO;
        gWGEAppIsLockedState = NO;
        WGERunFullCleanup(); 
    });
}

- (void)onAppUnlockSuccess {
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    gWGEIsAppLockScreenShowing = NO;
    WGERunFullCleanup();
    
    for (int i = 1; i <= 6; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WGERunFullCleanup();
        });
    }
}

@end
