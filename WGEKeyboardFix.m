#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEAppTransitionActive = NO;
static BOOL gWGEUserIsInteracting = NO;
static BOOL gWGEAppIsLockedState = NO;

// 【核心新增】标记应用当前是否正处于“展示解锁界面（FaceID/密码）”的状态
// 当这个状态为 YES 时，允许代码自动拉起键盘，不进行任何拦截
static BOOL gWGEIsAppLockScreenShowing = YES; 

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
    // 如果处于系统锁屏状态，或者应用自身的解锁界面正在显示，绝对不要执行清理
    if (gWGEAppIsLockedState || gWGEIsAppLockScreenShowing) {
        return;
    }
    
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];

    for (UIWindow *w in WGEAllWindows()) {
        [w endEditing:YES];
        
        NSString *windowClassName = NSStringFromClass([w class]);
        
        // 过滤系统安全与远程输入窗口
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
    // 1. 如果应用自身的解锁页面正在展示，无条件放行，允许代码自动聚焦拉起键盘
    if (gWGEIsAppLockScreenShowing) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    // 2. 如果处于系统层面的锁屏/切后台状态，原路放行
    if (gWGEAppIsLockedState || gWGEAppTransitionActive) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    // 3. 正常业务状态下，如果没有用户触摸交互，则拦截并清理（防止无故乱弹键盘）
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
        
        // 监听应用自身解锁成功/收起的通知
        [center addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
    });
}

- (void)onLockOrBackground {
    gWGEAppIsLockedState = YES;
    gWGEAppTransitionActive = YES;
    // 重新回到锁屏或后台时，重置应用解锁状态，以便下次进来时能再次自动拉起
    gWGEIsAppLockScreenShowing = YES;
}

- (void)onUnlockOrActive {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEAppTransitionActive = NO;
        gWGEAppIsLockedState = NO;
        WGERunFullCleanup(); 
    });
}

// 【核心新增】当用户成功通过 FaceID 或 密码解锁，进入首页时触发
- (void)onAppUnlockSuccess {
    // 1. 关闭解锁页面特权状态
    gWGEIsAppLockScreenShowing = NO;
    
    // 2. 强行执行一次深度清理，把解锁页面的光标、键盘实体、动画阴影全部连根拔起
    // 这样能确保进入首页时绝对是一张白纸，不会有任何键盘或残影自动弹起
    WGERunFullCleanup();
}

@end
