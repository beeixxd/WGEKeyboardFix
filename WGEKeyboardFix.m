#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void forceDismissKeyboard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (!keyWindow && [[UIApplication sharedApplication] windows].count > 0) {
            keyWindow = [[UIApplication sharedApplication] windows] firstObject;
        }
        
        if (keyWindow) {
            [keyWindow endEditing:YES];
        }
        
        Class keyboardClass = objc_getClass("UIKeyboardImpl");
        if (keyboardClass) {
            id sharedImpl = [keyboardClass performSelector:@selector(sharedInstance)];
            if (sharedImpl) {
                if ([sharedImpl respondsToSelector:@selector(dismissKeyboard)]) {
                    [sharedImpl performSelector:@selector(dismissKeyboard)];
                }
                if ([sharedImpl respondsToSelector:@selector(orderOutWithTrackedView:Duration:Notify:)]) {
                    [sharedImpl performSelector:@selector(orderOutWithTrackedView:Duration:Notify:) withObject:nil withObject:@(0.0) withObject:@(NO)];
                }
            }
        }
        
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            NSString *windowName = NSStringFromClass([window class]);
            if ([windowName containsString:@"TextEffectsWindow"] || [windowName containsString:@"Keyboard"]) {
                window.hidden = YES;
                window.alpha = 0.0;
                for (UIView *subview in [window subviews]) {
                    NSString *subName = NSStringFromClass([subview class]);
                    if ([subName containsString:@"Dimming"] || [subName containsString:@"Shadow"]) {
                        subview.hidden = YES;
                        [subview removeFromSuperview];
                    }
                }
            }
        }
    });
}

static void (*orig_willEnterForeground)(id, SEL, id);
static void new_willEnterForeground(id self, SEL _cmd, id notification) {
    orig_willEnterForeground(self, _cmd, notification);
    forceDismissKeyboard();
    for (int i = 1; i <= 3; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            forceDismissKeyboard();
        });
    }
}

static void (*orig_didBecomeActive)(id, SEL, id);
static void new_didBecomeActive(id self, SEL _cmd, id notification) {
    orig_didBecomeActive(self, _cmd, notification);
    forceDismissKeyboard();
}

__attribute__((constructor)) static void init() {
    Class appDelegate = objc_getClass("UIApplication");
    if (appDelegate) {
        Method m1 = class_getInstanceMethod(appDelegate, @selector(_applicationWillEnterForeground:));
        if (m1) {
            orig_willEnterForeground = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)new_willEnterForeground);
        }
        
        Method m2 = class_getInstanceMethod(appDelegate, @selector(_applicationDidBecomeActive:));
        if (m2) {
            orig_didBecomeActive = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)new_didBecomeActive);
        }
    }
}
