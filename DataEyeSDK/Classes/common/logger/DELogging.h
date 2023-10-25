#import <Foundation/Foundation.h>

#import "DataEyeSDK.h"

NS_ASSUME_NONNULL_BEGIN

#define DELogDebug(message, ...)  DELogWithType(DELoggingLevelDebug, message, ##__VA_ARGS__)
#define DELogInfo(message,  ...)  DELogWithType(DELoggingLevelInfo, message, ##__VA_ARGS__)
#define DELogError(message, ...)  DELogWithType(DELoggingLevelError, message, ##__VA_ARGS__)

#define DELogWithType(type, message, ...) \
{ \
if ([DELogging sharedInstance].loggingLevel != DELoggingLevelNone && type <= [DELogging sharedInstance].loggingLevel) \
{ \
[[DELogging sharedInstance] logCallingFunction:type format:(message), ##__VA_ARGS__]; \
} \
}

@interface DELogging : NSObject

@property (class, nonatomic, readonly) DELogging *sharedInstance;
@property (assign, nonatomic) DELoggingLevel loggingLevel;
- (void)logCallingFunction:(DELoggingLevel)type format:(id)messageFormat, ...;

@end

NS_ASSUME_NONNULL_END
