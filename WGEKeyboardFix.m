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
        [className containsString:@"RenderConfig"]) {
        subview.hidden = YES;
        subview.alpha = 0.0;
        [subview removeFromSuperview];
    }
}

static void (*orig_windowLayout)(id, SEL);
static void new_windowLayout(id self, SEL _cmd) {
    orig_windowLayout(self, _cmd);
    
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"UIKeyboardBindingsWindow"] || 
        [className containsString:@"UITextEffectsWindow"]) {
        for (UIView *subview in [(UIView *)self subviews]) {
            NSString *subName = NSStringFromClass([subview class]);
            if ([subName containsString:@"Background"] || [subName containsString:@"Shadow"] || [subName containsString:@"Backdrop"]) {
                subview.hidden = YES;
                subview.alpha = 0.0;
            }
        }
    }
}

static void forceHideKeyboardSystem() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class keyboardClass = objc_getClass("UIKeyboardImpl");
        if (keyboardClass) {
            id sharedImpl = [keyboardClass performSelector:@selector(sharedInstance)];
            if (sharedImpl) {
                if ([sharedImpl respondsToSelector:@selector(dismissKeyboard)]) {
                    [sharedImpl performSelector:@selector(dismissKeyboard)];
                }
            }
        }
        
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            NSString *windowName = NSStringFromClass([window class]);
            if ([windowName containsString:@"UIKeyboardBindingsWindow"] || 
                [windowName containsString:@"UITextEffectsWindow"]) {
                window.hidden = YES;
                window.alpha = 0.0;
            }
        }
    });
}

__attribute__((constructor)) static void init() {
    Class viewClass = [UIView class];
    Method m1 = class_getInstanceMethod(viewClass, @selector(didAddSubview:));
    orig_didAddSubview = (void *)method_getImplementation(m1);
    method_setImplementation(m1, (IMP)new_didAddSubview);

    Class windowClass = [UIWindow class];
    Method m2 = class_getInstanceMethod(windowClass, @selector(layoutSubviews));
    orig_windowLayout = (void *)method_getImplementation(m2);
    method_setImplementation(m2, (IMP)new_windowLayout);

    int token;
    notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state;
        notify_get_state(t, &state);
        if (state == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                forceHideKeyboardSystem();
            });
        }
    });
}
