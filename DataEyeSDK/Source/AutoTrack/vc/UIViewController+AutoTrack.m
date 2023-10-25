#import "UIViewController+AutoTrack.h"
#import "DEAutoTrackManager.h"
#import "DELogging.h"

@implementation UIViewController (AutoTrack)

- (void)de_autotrack_viewWillAppear:(BOOL)animated {
    @try {
        [[DEAutoTrackManager sharedManager] viewControlWillAppear:self];
    } @catch (NSException *exception) {
        DELogError(@"%@ error: %@", self, exception);
    }
    [self de_autotrack_viewWillAppear:animated];
}

@end
