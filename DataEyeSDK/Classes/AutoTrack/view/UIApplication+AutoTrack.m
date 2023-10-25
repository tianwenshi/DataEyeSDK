#import "UIApplication+AutoTrack.h"
#import "DEAutoTrackManager.h"

@implementation UIApplication (AutoTrack)

- (BOOL)de_sendAction:(SEL)action to:(id)to from:(id)from forEvent:(UIEvent *)event {
    if ([from isKindOfClass:[UIControl class]]) {
        //UISegmentedControl  UISwitch  UIStepper  UISlider
        if (([from isKindOfClass:[UISwitch class]] ||
            [from isKindOfClass:[UISegmentedControl class]] ||
            [from isKindOfClass:[UIStepper class]])) {
            [[DEAutoTrackManager sharedManager] trackEventView:from];
        }
        
        //UIButton UIPageControl UITabBarButton _UIButtonBarButton
        else if ([event isKindOfClass:[UIEvent class]] && event.type == UIEventTypeTouches && [[[event allTouches] anyObject] phase] == UITouchPhaseEnded) {
            [[DEAutoTrackManager sharedManager] trackEventView:from];
        }
    }
    
    return [self de_sendAction:action to:to from:from forEvent:event];
}

@end
