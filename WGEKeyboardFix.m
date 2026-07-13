#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEAppTransitionActive = NO;
static BOOL gWGEUserIsInteracting = NO;
static BOOL gWGEAppIsLockedState = NO;
static BOOL gWGEIsAppLockScreenShowing = YES;

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (gWGEIsAppLockScreenShowing) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    if (gWGEAppIsLockedState || gWGEAppTransitionActive) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    if (!gWGEUserIsInteracting) {
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
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
            [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
            [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
            [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
            
            [center addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
        });
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
    });
}

- (void)onAppUnlockSuccess {
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                [w endEditing:YES];
            }
        }
    } else {
        [[UIApplication sharedApplication].keyWindow endEditing:YES];
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            [w endEditing:YES];
        }
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEIsAppLockScreenShowing = NO;
    });
    
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((2 + i) * 0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        [w endEditing:YES];
                    }
                }
            }
        });
    }
}

@end
