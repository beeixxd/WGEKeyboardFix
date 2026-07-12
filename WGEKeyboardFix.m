#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEPasscodeRecentlyShown = NO;
static BOOL gWGEAppTransitionActive = NO;

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
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];

    for (UIWindow *w in WGEAllWindows()) {
        [w endEditing:YES];
        
        NSString *windowClassName = NSStringFromClass([w class]);
        if ([windowClassName rangeOfString:@"Passcode"].location != NSNotFound) {
            w.hidden = YES;
        }

        for (UIView *subview in [w subviews]) {
            NSString *subName = NSStringFromClass([subview class]);
            if ([subName containsString:@"Dimming"] || 
                [subName containsString:@"Shadow"] || 
                [subName containsString:@"Corner"] || 
                [subName containsString:@"Keyboard"]) {
                subview.hidden = YES;
                [subview removeFromSuperview];
            }
        }
    }
}

static void WGEScheduleCleanup(NSTimeInterval delay) {
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_after(when, dispatch_get_main_queue(), ^{
        WGERunFullCleanup();
    });
}

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    NSString *className = NSStringFromClass([self class]);
    
    if ([className containsString:@"Passcode"] || 
        [className containsString:@"PIN"] || 
        [className containsString:@"Secure"] || 
        [className containsString:@"Password"] || 
        [className containsString:@"Field"]) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    if (gWGEAppTransitionActive) {
        return NO;
    }
    
    return orig_becomeFirstResponder(self, _cmd);
}

static void (*orig_viewWillDisappear)(id, SEL, BOOL);
static void new_viewWillDisappear(id self, SEL _cmd, BOOL animated) {
    orig_viewWillDisappear(self, _cmd, animated);
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
}

static IMP gOrigPasscodeViewWillDisappear = NULL;
static IMP gOrigPasscodeViewDidAppear = NULL;

static void WGEPasscodeViewWillDisappear(id self, SEL _cmd, BOOL animated) {
    if (gOrigPasscodeViewWillDisappear) {
        ((void (*)(id, SEL, BOOL))gOrigPasscodeViewWillDisappear)(self, _cmd, animated);
    }
    gWGEPasscodeRecentlyShown = YES;
    gWGEAppTransitionActive = YES;
    WGEScheduleCleanup(0.05);
    WGEScheduleCleanup(0.15);
}

static void WGEPasscodeViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (gOrigPasscodeViewDidAppear) {
        ((void (*)(id, SEL, BOOL))gOrigPasscodeViewDidAppear)(self, _cmd, animated);
    }
    gWGEPasscodeRecentlyShown = YES;
}

static void WGESwizzleInstanceMethod(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    if (!cls) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    *originalOut = method_getImplementation(method);
    method_setImplementation(method, replacement);
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
        
        Class vcClass = [UIViewController class];
        Method m2 = class_getInstanceMethod(vcClass, @selector(viewWillDisappear:));
        if (m2) {
            orig_viewWillDisappear = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)new_viewWillDisappear);
        }
        
        Class passcodeClass = NSClassFromString(@"_TtC10PasscodeUI23PasscodeEntryController");
        if (passcodeClass) {
            WGESwizzleInstanceMethod(passcodeClass, @selector(viewWillDisappear:),
                                      (IMP)WGEPasscodeViewWillDisappear, &gOrigPasscodeViewWillDisappear);
            WGESwizzleInstanceMethod(passcodeClass, @selector(viewDidAppear:),
                                      (IMP)WGEPasscodeViewDidAppear, &gOrigPasscodeViewDidAppear);
        }
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    });
}

- (void)onLockOrBackground {
    gWGEAppTransitionActive = YES;
    WGERunFullCleanup();
}

- (void)onUnlockOrActive {
    WGERunFullCleanup();
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WGERunFullCleanup();
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEAppTransitionActive = NO;
        gWGEPasscodeRecentlyShown = NO;
    });
}

@end
