#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>

static void (*orig_didAddSubview)(id, SEL, UIView *);
static void new_didAddSubview(id self, SEL _cmd, UIView *subview) {
    orig_didAddSubview(self, _cmd, subview);
    
    NSString *className = NSStringFromClass([subview class]);
    
    if ([className containsString:@"UIKeyboardCornerView"] || 
        [className containsString:@"KeyboardDropShadow"] ||
        [className containsString:@"PredictionBackground"] ||
        [className containsString:@"RenderConfig"] ||
        [className containsString:@"SBKeyboard"] ||
        [className containsString:@"DimmingView"] ||
        [className containsString:@"ShadowView"]) {
        subview.hidden = YES;
        subview.alpha = 0.0;
        [subview removeFromSuperview];
    }
}

static void (*orig_layoutSubviews)(id, SEL);
static void new_layoutSubviews(id self, SEL _cmd) {
    orig_layoutSubviews(self, _cmd);
    
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"Window"] || 
        [className containsString:@"SBContext"] || 
        [className containsString:@"SBHomeScreen"] || 
        [className containsString:@"SBIconController"]) {
        
        for (UIView *subview in [(UIView *)self subviews]) {
            NSString *subName = NSStringFromClass([subview class]);
            if ([subName containsString:@"Dimming"] || 
                [subName containsString:@"Shadow"] || 
                [subName containsString:@"Backdrop"] || 
                [subName containsString:@"Blur"]) {
                
                if (subview.frame.size.height < [UIScreen mainScreen].bounds.size.height) {
                    subview.hidden = YES;
                    subview.alpha = 0.0;
                    [subview removeFromSuperview];
                }
            }
        }
    }
}

static void killRemainingShadows() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class keyboardClass = objc_getClass("UIKeyboardImpl");
        if (keyboardClass) {
            id sharedImpl = [keyboardClass performSelector:@selector(sharedInstance)];
            if (sharedImpl) {
                if ([sharedImpl respondsToSelector:@selector(dismissKeyboard)]) {
                    [sharedImpl performSelector:@selector(dismissKeyboard)];
                }
                if ([sharedImpl respondsToSelector:@selector(minimize)]) {
                    [sharedImpl performSelector:@selector(minimize)];
                }
            }
        }

        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            NSString *windowName = NSStringFromClass([window class]);
            if ([windowName containsString:@"Keyboard"] || 
                [windowName containsString:@"Effects"] || 
                [windowName containsString:@"Tracking"]) {
                window.hidden = YES;
                window.alpha = 0.0;
            }
            
            for (UIView *subview in [window subviews]) {
                NSString *subName = NSStringFromClass([subview class]);
                if ([subName containsString:@"Dimming"] || [subName containsString:@"Shadow"]) {
                    subview.hidden = YES;
                    subview.alpha = 0.0;
                    [subview removeFromSuperview];
                }
            }
        }
    });
}

__attribute__((constructor)) static void init() {
    Class viewClass = [UIView class];
    Method m1 = class_getInstanceMethod(viewClass, @selector(didAddSubview:));
    orig_didAddSubview = (void *)method_getImplementation(m1);
    method_setImplementation(m1, (IMP)new_didAddSubview);

    Method m2 = class_getInstanceMethod(viewClass, @selector(layoutSubviews));
    orig_layoutSubviews = (void *)method_getImplementation(m2);
    method_setImplementation(m2, (IMP)new_layoutSubviews);

    int token;
    notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state;
        notify_get_state(t, &state);
        if (state == 0) {
            for (int i = 1; i <= 5; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    killRemainingShadows();
                });
            }
        }
    });
}
