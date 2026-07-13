#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEBlockKeyboardToPreventShadow = NO;

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (gWGEBlockKeyboardToPreventShadow) {
        return NO;
    }
    return ((BOOL(*)(id, SEL))orig_becomeFirstResponder)(self, _cmd);
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
            orig_becomeFirstResponder = (BOOL(*)(id, SEL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)new_becomeFirstResponder);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
        });
    });
}

- (void)onAppUnlockSuccess {
    gWGEBlockKeyboardToPreventShadow = YES;
    
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                [w endEditing:YES];
            }
        }
    } else {
        [[UIApplication sharedApplication].keyWindow endEditing:YES];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEBlockKeyboardToPreventShadow = NO;
    });
}

@end
