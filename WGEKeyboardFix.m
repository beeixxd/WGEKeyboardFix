#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>

static void (*orig_didAddSubview)(id, SEL, UIView *);
static void new_didAddSubview(id self, SEL _cmd, UIView *subview) {
    orig_didAddSubview(self, _cmd, subview);
    
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"UIKeyboard"] || 
        [className containsString:@"TUIKeyboard"] || 
        [className containsString:@"EffectsWindow"]) {
        
        NSString *subName = NSStringFromClass([subview class]);
        if ([subName containsString:@"Corner"] || 
            [subName containsString:@"Shadow"] || 
            [subName containsString:@"Dimming"] || 
            [subName containsString:@"Prediction"]) {
            subview.hidden = YES;
            subview.alpha = 0.0;
            [subview removeFromSuperview];
        }
    }
}

static void killRemainingShadows() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class keyboardClass = objc_getClass("UIKeyboardImpl");
        if (keyboardClass) {
            id sharedImpl = [keyboardClass performSelector:@selector(sharedInstance)];
            if (sharedImpl && [sharedImpl respondsToSelector:@selector(dismissKeyboard)]) {
                [sharedImpl performSelector:@selector(dismissKeyboard)];
            }
        }

        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            NSString *windowName = NSStringFromClass([window class]);
            if ([windowName containsString:@"TextEffectsWindow"] || [windowName containsString:@"Keyboard"]) {
                for (UIView *subview in [window subviews]) {
                    NSString *subName = NSStringFromClass([subview class]);
                    if ([subName containsString:@"Dimming"] || [subName containsString:@"Shadow"] || [subName containsString:@"Backdrop"]) {
                        subview.hidden = YES;
                        subview.alpha = 0.0;
                        [subview removeFromSuperview];
                    }
                }
            }
        }
    });
}

__attribute__((constructor)) static void init() {
    Class windowClass = objc_getClass("UITextEffectsWindow");
    if (windowClass) {
        Method m1 = class_getInstanceMethod(windowClass, @selector(didAddSubview:));
        if (m1) {
            orig_didAddSubview = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)new_didAddSubview);
        }
    }

    int token;
    notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state;
        notify_get_state(t, &state);
        if (state == 0) {
            for (int i = 1; i <= 3; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    killRemainingShadows();
                });
            }
        }
    });
}
