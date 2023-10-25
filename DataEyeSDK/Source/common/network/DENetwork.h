#import <Foundation/Foundation.h>

#import "DataEyeSDKPrivate.h"


typedef void (^DEFlushConfigBlock)(NSDictionary *result, NSError * _Nullable error);

@interface DENetwork : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
/**
 应用唯一标识
 */
@property (nonatomic, copy) NSString *appid;
/**
 私有化服务器地址
 */
@property (nonatomic, strong) NSURL *serverURL;

@property (nonatomic, strong) NSURL *serverDebugURL;
@property (nonatomic, assign) DataEyeDebugMode debugMode;
@property (nonatomic, strong) DESecurityPolicy *securityPolicy;
@property (nonatomic, copy) DEURLSessionDidReceiveAuthenticationChallengeBlock sessionDidReceiveAuthenticationChallenge;

- (BOOL)flushEvents:(NSArray<NSDictionary *> *)events;
- (void)fetchRemoteConfig:(NSString *)appid handler:(DEFlushConfigBlock)handler;
- (int)flushDebugEvents:(NSDictionary *)record withAppid:(NSString *)appid;

@end

