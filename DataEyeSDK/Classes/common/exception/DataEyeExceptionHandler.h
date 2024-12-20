#import <Foundation/Foundation.h>

#import "DataEyeSDKPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface DataEyeExceptionHandler : NSObject

+ (instancetype)sharedHandler;
- (void)addDataEyeInstance:(DataEyeSDK *)instance;

@end

NS_ASSUME_NONNULL_END
