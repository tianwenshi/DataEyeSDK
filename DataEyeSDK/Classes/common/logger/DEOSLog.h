#import <Foundation/Foundation.h>

#import "DataEyeSDK.h"

@class DELogMessage;
@protocol DELogger;

NS_ASSUME_NONNULL_BEGIN

@interface DEOSLog : NSObject

+ (void)log:(BOOL)asynchronous
    message:(NSString *)message
       type:(DELoggingLevel)type;

@end

@protocol DELogger <NSObject>

- (void)logMessage:(DELogMessage *)logMessage;

@optional

@property (nonatomic, strong, readonly) dispatch_queue_t loggerQueue;

@end

@interface DELogMessage : NSObject 

- (instancetype)initWithMessage:(NSString *)message
                           type:(DELoggingLevel)type;

@end

@interface DEAbstractLogger : NSObject <DELogger>

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
