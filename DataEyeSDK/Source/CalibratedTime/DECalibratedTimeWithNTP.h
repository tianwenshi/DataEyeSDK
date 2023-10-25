#import <Foundation/Foundation.h>

#import "DECalibratedTime.h"

NS_ASSUME_NONNULL_BEGIN

@interface DECalibratedTimeWithNTP : DECalibratedTime

- (void)recalibrationWithNtps:(NSArray *)ntpServers;

@end

NS_ASSUME_NONNULL_END
