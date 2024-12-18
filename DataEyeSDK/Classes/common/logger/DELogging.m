#import "DELogging.h"

#import <os/log.h>
#import "DEOSLog.h"

@implementation DELogging

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)logCallingFunction:(DELoggingLevel)type format:(id)messageFormat, ... {
    if (messageFormat) {
        va_list formatList;
        va_start(formatList, messageFormat);
        NSString *formattedMessage = [[NSString alloc] initWithFormat:messageFormat arguments:formatList];
        va_end(formatList);
        
#ifdef __IPHONE_10_0
        if (@available(iOS 10.0, *)) {
            [DEOSLog log:NO message:formattedMessage type:type];
        }
#else
        NSLog(@"[DataEye] %@", formattedMessage);
#endif
    }
}

@end

