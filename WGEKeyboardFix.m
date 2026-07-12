#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL g_autoFocusShieldActive = NO;

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (g_autoFocusShieldActive) {
        return NO;
    }
    return orig_becomeFirstResponder(self, _cmd);
}

static void applyShieldAndClean(void) {
    g_autoFocusShieldActive = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
        
        NSArray *windows = [[UIApplication sharedApplication] windows];
        for (UIWindow *window in windows) {
            NSString *name = NSStringFromClass([window class]);
            if ([name containsString:@"TextEffects"] || [name containsString:@"Keyboard"]) {
                window.hidden = YES;
                window.alpha = 0.0;
                
                NSArray *subviews = [window subviews];
                for (UIView *subview in subviews) {
                    NSString *subName = NSStringFromClass([subview class]);
                    if ([subName containsString:@"Dimming"] || [subName containsString:@"Shadow"] || [subName containsString:@"Corner"]) {
                        subview.hidden = YES;
                        [subview removeFromSuperview];
                    }
                }
            }
        }
    });
}

static void releaseShield(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        g_autoFocusShieldActive = NO;
    });
}

@interface WGEKeyboardUltimateFixer : NSObject
@end

@implementation WGEKeyboardUltimateFixer

+ (void)load {
    static WGEKeyboardUltimateFixer *fixer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fixer = [[WGEKeyboardUltimateFixer alloc] init];
        
        Class viewClass = [UIView class];
        Method m = class_getInstanceMethod(viewClass, @selector(becomeFirstResponder));
        if (m) {
            orig_becomeFirstResponder = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)new_becomeFirstResponder);
        }
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        
        [center addObserver:fixer selector:@selector(handleLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(handleLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        
        [center addObserver:fixer selector:@selector(handleUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(handleUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    });
}

- (void)handleLockOrBackground {
    applyShieldAndClean();
}

- (void)handleUnlockOrActive {
    applyShieldAndClean();
    
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            applyShieldAndClean();
        });
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        releaseShield();
    });
}

@end
