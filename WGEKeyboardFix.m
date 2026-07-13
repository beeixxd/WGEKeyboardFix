#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEAppTransitionActive = NO;
static BOOL gWGEUserIsInteracting = NO;
static BOOL gWGEAppIsLockedState = NO;
static BOOL gWGEIsAppLockScreenShowing = YES;
static UIWindow *gWGEGuardWindow = nil;
static UITextField *gWGEGuardField = nil;

@interface UIView (WGEKeyboardFix)
- (BOOL)wge_becomeFirstResponder;
@end

@implementation UIView (WGEKeyboardFix)

- (BOOL)wge_becomeFirstResponder {
    if (gWGEIsAppLockScreenShowing || self == gWGEGuardField) {
        return [self wge_becomeFirstResponder];
    }
    if (gWGEAppIsLockedState || gWGEAppTransitionActive) {
        return [self wge_becomeFirstResponder];
    }
    if (!gWGEUserIsInteracting) {
        return NO;
    }
    return [self wge_becomeFirstResponder];
}

@end

@interface UIWindow (WGEKeyboardFix)
- (void)wge_sendEvent:(UIEvent *)event;
@end

@implementation UIWindow (WGEKeyboardFix)

- (void)wge_sendEvent:(UIEvent *)event {
    if (event && event.type == UIEventTypeTouches) {
        gWGEUserIsInteracting = YES;
    }
    [self wge_sendEvent:event];
    if (event && event.type == UIEventTypeTouches) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gWGEUserIsInteracting = NO;
        });
    }
}

@end

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
        Method m2 = class_getInstanceMethod(viewClass, @selector(wge_becomeFirstResponder));
        if (m1 && m2) {
            method_exchangeImplementations(m1, m2);
        }
        
        Class windowClass = [UIWindow class];
        Method m3 = class_getInstanceMethod(windowClass, @selector(sendEvent:));
        Method m4 = class_getInstanceMethod(windowClass, @selector(wge_sendEvent:));
        if (m3 && m4) {
            method_exchangeImplementations(m3, m4);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
            [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
            [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
            [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
            [center addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
            
            gWGEGuardWindow = [[UIWindow alloc] initWithFrame:CGRectZero];
            gWGEGuardWindow.windowLevel = -1.0;
            gWGEGuardWindow.hidden = YES;
            
            gWGEGuardField = [[UITextField alloc] initWithFrame:CGRectZero];
            [gWGEGuardWindow addSubview:gWGEGuardField];
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
    UIWindow *previousKeyWindow = [UIApplication sharedApplication].keyWindow;
    
    if (gWGEGuardWindow && gWGEGuardField) {
        gWGEGuardWindow.hidden = NO;
        [gWGEGuardWindow makeKeyWindow];
        [gWGEGuardField wge_becomeFirstResponder];
        [gWGEGuardField resignFirstResponder];
        gWGEGuardWindow.hidden = YES;
    }
    
    if (previousKeyWindow) {
        [previousKeyWindow makeKeyWindow];
        [previousKeyWindow endEditing:YES];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEIsAppLockScreenShowing = NO;
        if (previousKeyWindow) {
            [previousKeyWindow endEditing:YES];
        }
    });
}

@end
