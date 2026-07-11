#import <UIKit/UIKit.h>

@interface UIKeyboardCornerView : UIView
@end

%hook UIKeyboardCornerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        self.alpha = 0.0;
        self.hidden = YES;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)layoutSubviews {
    %orig;
    self.alpha = 0.0;
    self.hidden = YES;
}

- (void)setHidden:(BOOL)hidden {
    %orig(YES);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(0.0);
}

%end

%hook UIView

- (void)didAddSubview:(UIView *)subview {
    %orig;
    
    if ([subview isKindOfClass:objc_getClass("UIKeyboardCornerView")]) {
        subview.hidden = YES;
        subview.alpha = 0.0;
    }
    
    if ([NSStringFromClass([subview class]) containsString:@"KeyboardDropShadow"]) {
        subview.hidden = YES;
        [subview removeFromSuperview];
    }
}

%end
