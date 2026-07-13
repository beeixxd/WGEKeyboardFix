#import <UIKit/UIKit.h>

static void WGEHandleUnlockShadowSuppression(void) {
    UIApplication *app = [UIApplication sharedApplication];
    NSArray *allWindows = nil;
    
    if ([app respondsToSelector:@selector(windows)]) {
        allWindows = [app performSelector:@selector(windows)];
    }
    
    if (!allWindows || allWindows.count == 0) {
        if (@available(iOS 13.0, *)) {
            NSMutableArray *sceneWindows = [NSMutableArray array];
            for (id scene in [app performSelector:@selector(connectedScenes)]) {
                if ([[scene class] isKindOfClass:NSClassFromString(@"UIWindowScene")]) {
                    NSArray *wins = [scene performSelector:@selector(windows)];
                    if (wins) [sceneWindows addObjectsFromArray:wins];
                }
            }
            allWindows = sceneWindows;
        }
    }
    
    for (id w in allWindows) {
        NSString *className = NSStringFromClass([w class]);
        if ([className containsString:@"TextEffects"] || [className containsString:@"Keyboard"]) {
            if ([w respondsToSelector:@selector(setWindowLevel:)]) {
                NSMethodSignature *sig = [w methodSignatureForSelector:@selector(setWindowLevel:)];
                if (sig) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setSelector:@selector(setWindowLevel:)];
                    [inv setTarget:w];
                    double lowLevel = -1.0;
                    [inv setArgument:&lowLevel atIndex:2];
                    [inv invoke];
                }
            }
        }
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray *restoreWindows = nil;
        if ([app respondsToSelector:@selector(windows)]) {
            restoreWindows = [app performSelector:@selector(windows)];
        }
        for (id w in restoreWindows) {
            NSString *className = NSStringFromClass([w class]);
            if ([className containsString:@"TextEffects"] || [className containsString:@"Keyboard"]) {
                if ([w respondsToSelector:@selector(setWindowLevel:)]) {
                    NSMethodSignature *sig = [w methodSignatureForSelector:@selector(setWindowLevel:)];
                    if (sig) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setSelector:@selector(setWindowLevel:)];
                        [inv setTarget:w];
                        double normalLevel = 10.0;
                        if ([className containsString:@"Keyboard"]) {
                            normalLevel = 1000.0;
                        }
                        [inv setArgument:&normalLevel atIndex:2];
                        [inv invoke];
                    }
                }
            }
        }
    });
}

__attribute__((constructor)) static void initializeWGEKeyboardShadowZIndexFixer(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:@"WGEAppUnlockScreenDidDismissNotification"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            WGEHandleUnlockShadowSuppression();
        }];
    });
}
