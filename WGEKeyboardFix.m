#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEAppTransitionActive = NO;
static BOOL gWGEUserIsInteracting = NO;
static BOOL gWGEAppIsLockedState = NO;

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
    // 如果处于锁屏或者后台状态，绝对不要执行任何清理，避免误伤系统锁屏密码框
    if (gWGEAppIsLockedState) {
        return;
    }
    
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];

    for (UIWindow *w in WGEAllWindows()) {
        [w endEditing:YES];
        
        NSString *windowClassName = NSStringFromClass([w class]);
        
        // 【核心修复】极大范围扩大白名单，锁屏密码窗口、系统安全窗口、远程输入法窗口一律放行
        if ([windowClassName rangeOfString:@"Passcode"].location != NSNotFound ||
            [windowClassName rangeOfString:@"Remote"].location != NSNotFound ||
            [windowClassName rangeOfString:@"Secure"].location != NSNotFound ||
            [windowClassName rangeOfString:@"Alert"].location != NSNotFound) {
            continue;
        }

        if ([windowClassName containsString:@"TextEffects"] || [windowClassName containsString:@"Keyboard"]) {
            w.hidden = YES;
            w.alpha = 0.0;
            CGRect frame = w.frame;
            frame.size.height = 0;
            w.frame = frame;
        }

        for (UIView *subview in [w subviews]) {
            NSString *subName = NSStringFromClass([subview class]);
            if ([subName containsString:@"Dimming"] || 
                [subName containsString:@"Shadow"] || 
                [subName containsString:@"Corner"] || 
                [subName containsString:@"Keyboard"]) {
                subview.hidden = YES;
                CGRect frame = subview.frame;
                frame.size.height = 0;
                subview.frame = frame;
                [subview removeFromSuperview];
            }
        }
    }
}

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    // 【核心修复】如果 App 处于锁屏或者正在切后台，说明当前是系统托管阶段，必须立刻原路放行，绝不拦截
    if (gWGEAppIsLockedState || gWGEAppTransitionActive) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    // 只有在非用户直接触摸交互、且 App 处于正常前台时，才为了防止防弹键盘而清理
    if (!gWGEUserIsInteracting) {
        WGERunFullCleanup();
        return NO;
    }
    
    return orig_becomeFirstResponder(self, _cmd);
}

static void (*orig_windowSendEvent)(id, SEL, UIEvent *);
static void new_windowSendEvent(id self, SEL _cmd, UIEvent *event) {
    if (event && event.type == UIEventTypeTouches) {
        gWGEUserIsInteracting = YES;
    }
    orig_windowSendEvent(self, _cmd, event);
    if (event && event.type == UIEventTypeTouches) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gWGEUserIsInteracting = NO;
        });
    }
}

static void (*orig_viewWillDisappear)(id, SEL, BOOL);
static void new_viewWillDisappear(id self, SEL _cmd, BOOL animated) {
    orig_viewWillDisappear(self, _cmd, animated);
    WGERunFullCleanup();
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
        
        Class windowClass = [UIWindow class];
        Method m2 = class_getInstanceMethod(windowClass, @selector(sendEvent:));
        if (m2) {
            orig_windowSendEvent = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)new_windowSendEvent);
        }
        
        Class vcClass = [UIViewController class];
        Method m3 = class_getInstanceMethod(vcClass, @selector(viewWillDisappear:));
        if (m3) {
            orig_viewWillDisappear = (void *)method_getImplementation(m3);
            method_setImplementation(m3, (IMP)new_viewWillDisappear);
        }
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    });
}

- (void)onLockOrBackground {
    gWGEAppIsLockedState = YES;
    gWGEAppTransitionActive = YES;
    // 【核心修复】锁屏时不要自作聪明去调用清理，完全让给系统，防止密码框被阉割
}

- (void)onUnlockOrActive {
    // 【核心修复】舍弃以前高频循环调用 WGERunFullCleanup 的做法，改为延时 0.15 秒温和重置状态
    // 给系统留出充足的从锁屏/后台返回并初始化 UI 的时间
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEAppTransitionActive = NO;
        gWGEAppIsLockedState = NO;
        WGERunFullCleanup(); // 此时 App 已完全前台掌控，清理残留即可
    });
}

@end
