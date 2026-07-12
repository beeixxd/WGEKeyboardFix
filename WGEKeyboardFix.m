#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gWGEPasscodeRecentlyShown = NO;

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

static UIWindow *WGEKeyWindow(void) {
    for (UIWindow *w in WGEAllWindows()) {
        if (w.isKeyWindow) return w;
    }
    return [UIApplication sharedApplication].keyWindow;
}

static void WGEPostSyntheticKeyboardHide(void) {
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGRect endFrame = CGRectMake(0, screenBounds.size.height, screenBounds.size.width, 0);
    NSValue *frameValue = [NSValue valueWithCGRect:endFrame];
    NSDictionary *userInfo = @{
        UIKeyboardFrameBeginUserInfoKey: frameValue,
        UIKeyboardFrameEndUserInfoKey: frameValue,
        UIKeyboardAnimationDurationUserInfoKey: @(0.25),
        UIKeyboardAnimationCurveUserInfoKey: @(UIViewAnimationCurveEaseInOut),
        UIKeyboardIsLocalUserInfoKey: @YES,
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:UIKeyboardWillHideNotification
                                                          object:nil
                                                        userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:UIKeyboardDidHideNotification
                                                          object:nil
                                                        userInfo:userInfo];
}

static void WGEHideLeftoverPasscodeWindows(void) {
    UIWindow *keyWindow = WGEKeyWindow();
    for (UIWindow *w in WGEAllWindows()) {
        if (w == keyWindow) continue;
        if (w.isHidden) continue;

        NSMutableArray<UIViewController *> *chain = [NSMutableArray array];
        UIViewController *vc = w.rootViewController;
        if (vc) [chain addObject:vc];
        while (vc.presentedViewController) {
            vc = vc.presentedViewController;
            [chain addObject:vc];
        }

        BOOL isPasscodeWindow = NO;
        for (UIViewController *candidate in chain) {
            NSString *className = NSStringFromClass([candidate class]);
            if ([className rangeOfString:@"Passcode"].location != NSNotFound) {
                isPasscodeWindow = YES;
                break;
            }
        }

        NSString *windowClassName = NSStringFromClass([w class]);
        if ([windowClassName rangeOfString:@"Passcode"].location != NSNotFound) {
            isPasscodeWindow = YES;
        }

        if (isPasscodeWindow) {
            w.hidden = YES;
        }
    }
}

static void WGERunFullCleanup(void) {
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder)
                                                to:nil
                                              from:nil
                                          forEvent:nil];

    for (UIWindow *w in WGEAllWindows()) {
        [w endEditing:YES];
    }

    WGEHideLeftoverPasscodeWindows();
    WGEPostSyntheticKeyboardHide();

    UIWindow *keyWindow = WGEKeyWindow();
    [keyWindow setNeedsLayout];
    [keyWindow layoutIfNeeded];
}

static void WGEScheduleCleanup(NSTimeInterval delay) {
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_after(when, dispatch_get_main_queue(), ^{
        WGERunFullCleanup();
    });
}

static IMP gOrigPasscodeDealloc = NULL;
static IMP gOrigPasscodeViewWillDisappear = NULL;
static IMP gOrigPasscodeViewDidAppear = NULL;

static void WGEPasscodeDealloc(id self, SEL _cmd) {
    gWGEPasscodeRecentlyShown = YES;
    WGEScheduleCleanup(0.05);
    WGEScheduleCleanup(0.35);
    if (gOrigPasscodeDealloc) {
        ((void (*)(id, SEL))gOrigPasscodeDealloc)(self, _cmd);
    }
}

static void WGEPasscodeViewWillDisappear(id self, SEL _cmd, BOOL animated) {
    if (gOrigPasscodeViewWillDisappear) {
        ((void (*)(id, SEL, BOOL))gOrigPasscodeViewWillDisappear)(self, _cmd, animated);
    }
    gWGEPasscodeRecentlyShown = YES;
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

__attribute__((constructor))
static void WGEKeyboardFixInit(void) {
    Class passcodeClass = NSClassFromString(@"_TtC10PasscodeUI23PasscodeEntryController");
    if (passcodeClass) {
        WGESwizzleInstanceMethod(passcodeClass, sel_registerName("dealloc"),
                                  (IMP)WGEPasscodeDealloc, &gOrigPasscodeDealloc);
        WGESwizzleInstanceMethod(passcodeClass, @selector(viewWillDisappear:),
                                  (IMP)WGEPasscodeViewWillDisappear, &gOrigPasscodeViewWillDisappear);
        WGESwizzleInstanceMethod(passcodeClass, @selector(viewDidAppear:),
                                  (IMP)WGEPasscodeViewDidAppear, &gOrigPasscodeViewDidAppear);
    }

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification * _Nonnull note) {
        if (gWGEPasscodeRecentlyShown) {
            gWGEPasscodeRecentlyShown = NO;
            WGEScheduleCleanup(0.05);
            WGEScheduleCleanup(0.35);
        }
    }];
}
