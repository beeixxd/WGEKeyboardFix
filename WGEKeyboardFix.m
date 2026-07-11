#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void (*orig_layoutSubviews)(id, SEL);
static void new_layoutSubviews(id self, SEL _cmd) {
    orig_layoutSubviews(self, _cmd);
    [self setAlpha:0.0];
    [self setHidden:YES];
}

static void (*orig_setHidden)(id, SEL, BOOL);
static void new_setHidden(id self, SEL _cmd, BOOL hidden) {
    orig_setHidden(self, _cmd, YES);
}

static void (*orig_setAlpha)(id, SEL, CGFloat);
static void new_setAlpha(id self, SEL _cmd, CGFloat alpha) {
    orig_setAlpha(self, _cmd, 0.0);
}

static void (*orig_didAddSubview)(id, SEL, UIView *);
static void new_didAddSubview(id self, SEL _cmd, UIView *subview) {
    orig_didAddSubview(self, _cmd, subview);
    if ([subview isKindOfClass:objc_getClass("UIKeyboardCornerView")]) {
        subview.hidden = YES;
        subview.alpha = 0.0;
    }
    if ([NSStringFromClass([subview class]) containsString:@"KeyboardDropShadow"]) {
        subview.hidden = YES;
        [subview removeFromSuperview];
    }
}

__attribute__((constructor)) static void init() {
    Class cornerView = objc_getClass("UIKeyboardCornerView");
    if (cornerView) {
        Method m1 = class_getInstanceMethod(cornerView, @selector(layoutSubviews));
        orig_layoutSubviews = (void *)method_getImplementation(m1);
        method_setImplementation(m1, (IMP)new_layoutSubviews);

        Method m2 = class_getInstanceMethod(cornerView, @selector(setHidden:));
        orig_setHidden = (void *)method_getImplementation(m2);
        method_setImplementation(m2, (IMP)new_setHidden);

        Method m3 = class_getInstanceMethod(cornerView, @selector(setAlpha:));
        orig_setAlpha = (void *)method_getImplementation(m3);
        method_setImplementation(m3, (IMP)new_setAlpha);
    }

    Class viewClass = [UIView class];
    Method m4 = class_getInstanceMethod(viewClass, @selector(didAddSubview:));
    orig_didAddSubview = (void *)method_getImplementation(m4);
    method_setImplementation(m4, (IMP)new_didAddSubview);
}
