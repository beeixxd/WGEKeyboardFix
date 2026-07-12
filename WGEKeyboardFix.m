#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL g_isAppTransitionActive = NO;

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (g_isAppTransitionActive) {
        return NO;
    }
    
    BOOL isProgrammatic = YES;
    id appClass = objc_getClass("UIApplication");
    if (appClass) {
        id sharedApp = [appClass performSelector:@selector(sharedInstance)];
        if (sharedApp) {
            SEL currentEventSel = objc_getSelector("currentEvent");
            if ([sharedApp respondsToSelector:currentEventSel]) {
                NSMethodSignature *sig = [sharedApp methodSignatureForSelector:currentEventSel];
                if (sig) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setSelector:currentEventSel];
                    [inv setTarget:sharedApp];
                    [inv invoke];
                    __unsafe_unretained UIEvent *currentEvent = nil;
                    [inv getReturnValue:&currentEvent];
                    
                    if (currentEvent && currentEvent.type == UIEventTypeTouches) {
                        isProgrammatic = NO;
                    }
                }
            }
        }
    }
    
    if (isProgrammatic) {
        return NO;
    }
    
    return orig_becomeFirstResponder(self, _cmd);
}

static void (*orig_viewWillDisappear)(id, SEL, BOOL);
static void new_viewWillDisappear(id self, SEL _cmd, BOOL animated) {
    orig_viewWillDisappear(self, _cmd, animated);
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
}

static void executeIronCladCleanup(void) {
    g_isAppTransitionActive = YES;
    
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

static void releaseTransitionShield(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        g_isAppTransitionActive = NO;
    });
}

@interface WGEKeyboardPerfectFixer : NSObject
@end

@implementation WGEKeyboardPerfectFixer

+ (void)load {
    static WGEKeyboardPerfectFixer *fixer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fixer = [[WGEKeyboardPerfectFixer alloc] init];
        
        Class viewClass = [UIView class];
        Method m1 = class_getInstanceMethod(viewClass, @selector(becomeFirstResponder));
        if (m1) {
            orig_becomeFirstResponder = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)new_becomeFirstResponder);
        }
        
        Class vcClass = [UIViewController class];
        Method m4 = class_getInstanceMethod(vcClass, @selector(viewWillDisappear:));
        if (m4) {
            orig_viewWillDisappear = (void *)method_getImplementation(m4);
            method_setImplementation(m4, (IMP)new_viewWillDisappear);
        }
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    });
}

- (void)onLockOrBackground {
    executeIronCladCleanup();
}

- (void)onUnlockOrActive {
    executeIronCladCleanup();
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            executeIronCladCleanup();
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        releaseTransitionShield();
    });
}

@end
