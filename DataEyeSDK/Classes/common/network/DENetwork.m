#import "DENetwork.h"

#import "NSData+DEGzip.h"
#import "DEJSONUtil.h"
#import "DELogging.h"
#import "DESecurityPolicy.h"
#import "DEToastView.h"
static NSString *kDEIntegrationType = @"DE-Integration-Type";
static NSString *kDEIntegrationVersion = @"DE-Integration-Version";
static NSString *kDEIntegrationCount = @"DE-Integration-Count";
static NSString *kDEIntegrationExtra = @"DE-Integration-Extra";

@implementation DENetwork

- (NSURLSession *)sharedURLSession {
    static NSURLSession *sharedSession = nil;
    @synchronized(self) {
        if (sharedSession == nil) {
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            sharedSession = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
        }
    }
    return sharedSession;
}

- (NSString *)URLEncode:(NSString *)string {
    return [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
}

- (int)flushDebugEvents:(NSDictionary *)record withAppid:(NSString *)appid {
    __block int debugResult = -1;
    NSMutableDictionary *recordDic = [record mutableCopy];
    NSMutableDictionary *properties = [[recordDic objectForKey:@"properties"] mutableCopy];
    
    if ([DataEyeSDK isTrackEvent:[record objectForKey:@"#type"]]) {
        [properties addEntriesFromDictionary:[DEDeviceInfo sharedManager].staticAutomaticData];
        [properties addEntriesFromDictionary:[DEDeviceInfo sharedManager].dynamicAutomaticData];
    }
    [recordDic setObject:properties forKey:@"properties"];
    NSString *jsonString = [DEJSONUtil JSONStringForObject:recordDic];
    NSMutableURLRequest *request = [self buildDebugRequestWithJSONString:jsonString withAppid:appid withDeviceId:[[DEDeviceInfo sharedManager].staticAutomaticData objectForKey:@"#device_id"]];
    dispatch_semaphore_t flushSem = dispatch_semaphore_create(0);

    void (^block)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
            debugResult = -2;
            DELogError(@"Debug Networking error:%@", error);
            dispatch_semaphore_signal(flushSem);
            return;
        }

        NSHTTPURLResponse *urlResponse = (NSHTTPURLResponse *)response;
        if ([urlResponse statusCode] == 200) {
            NSError *err;
            NSDictionary *retDic = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&err];
            if (err) {
                DELogError(@"Debug data json error:%@", err);
                debugResult = -2;
            } else if ([[retDic objectForKey:@"errorLevel"] isEqualToNumber:[NSNumber numberWithInt:1]]) {
                debugResult = 1;
                NSArray* errorProperties = [retDic objectForKey:@"errorProperties"];
                NSMutableString *errorStr = [NSMutableString string];
                for (id obj in errorProperties) {
                    NSString *errorReasons = [obj objectForKey:@"errorReason"];
                    NSString *propertyName = [obj objectForKey:@"propertyName"];
                    [errorStr appendFormat:@" propertyName:%@ errorReasons:%@\n", propertyName, errorReasons];
                }
                DELogError(@"Debug data error:%@", errorStr);
            } else if ([[retDic objectForKey:@"errorLevel"] isEqualToNumber:[NSNumber numberWithInt:2]]) {
                debugResult = 2;
                NSString *errorReasons = [[retDic objectForKey:@"errorReasons"] componentsJoinedByString:@" "];
                DELogError(@"Debug data error:%@", errorReasons);
            } else if ([[retDic objectForKey:@"errorLevel"] isEqualToNumber:[NSNumber numberWithInt:0]]) {
                debugResult = 0;
                DELogDebug(@"Verify data success.");
            } else if ([[retDic objectForKey:@"errorLevel"] isEqualToNumber:[NSNumber numberWithInt:-1]]) {
                debugResult = -1;
                NSString *errorReasons = [[retDic objectForKey:@"errorReasons"] componentsJoinedByString:@" "];
                DELogError(@"Debug mode error:%@", errorReasons);
            }
            
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                if (debugResult == 0 || debugResult == 1 || debugResult == 2) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIWindow *window = [UIApplication sharedApplication].keyWindow;
                        [DEToastView showInWindow:window text:[NSString stringWithFormat:@"当前模式为:%@", self.debugMode == DataEyeDebugOnly ? @"DebugOnly(数据不入库)\n测试联调阶段开启\n正式上线前请关闭Debug功能" : @"Debug"] duration:2.0];
                    });
                }
            });
        } else {
            debugResult = -2;
            NSString *urlResponse = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            DELogError(@"%@", [NSString stringWithFormat:@"Debug %@ network failed with response '%@'.", self, urlResponse]);
        }
        dispatch_semaphore_signal(flushSem);
    };

    NSURLSessionDataTask *task = [[self sharedURLSession] dataTaskWithRequest:request completionHandler:block];
    [task resume];

    dispatch_semaphore_wait(flushSem, DISPATCH_TIME_FOREVER);
    return debugResult;
}

- (BOOL)flushEvents:(NSArray<NSDictionary *> *)recordArray {
    __block BOOL flushSucc = YES;
    
    NSDictionary *flushDic = @{
        @"data": recordArray,
        @"automaticData": [DEDeviceInfo sharedManager].staticAutomaticData,
        @"#app_id": self.appid,
    };
//    NSDictionary *flushDic = @{
//        @"data": recordArray,
//        @"automaticData": [TDDeviceInfo sharedManager].automaticData,
//        @"#app_id": self.appid,
//    };
//    NSMutableDictionary *flushDic = [[TDDeviceInfo sharedManager].automaticData mutableCopy];
//    flushDic[@"data"] = recordArray;
//    flushDic[@"#app_id"] = self.appid;
    
    NSString *jsonString = [DEJSONUtil JSONStringForObject:flushDic];
    NSMutableURLRequest *request = [self buildRequestWithJSONString:jsonString];
    [request addValue:[DEDeviceInfo sharedManager].libName forHTTPHeaderField:kDEIntegrationType];
    [request addValue:[DEDeviceInfo sharedManager].libVersion forHTTPHeaderField:kDEIntegrationVersion];
    [request addValue:@(recordArray.count).stringValue forHTTPHeaderField:kDEIntegrationCount];
    [request addValue:@"iOS" forHTTPHeaderField:kDEIntegrationExtra];
    
    dispatch_semaphore_t flushSem = dispatch_semaphore_create(0);

    void (^block)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
            flushSucc = NO;
            DELogError(@"Networking error:%@", error);
            dispatch_semaphore_signal(flushSem);
            return;
        }

        NSHTTPURLResponse *urlResponse = (NSHTTPURLResponse *)response;
        if ([urlResponse statusCode] == 200) {
            flushSucc = YES;
            DELogDebug(@"flush success sendContent---->:%@",flushDic);
            id result = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
            DELogDebug(@"flush success responseData---->%@",result);
        } else {
            flushSucc = NO;
            NSString *urlResponse = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            DELogError(@"%@", [NSString stringWithFormat:@"%@ network failed with response '%@'.", self, urlResponse]);
        }

        dispatch_semaphore_signal(flushSem);
    };

    NSURLSessionDataTask *task = [[self sharedURLSession] dataTaskWithRequest:request completionHandler:block];
    [task resume];
    dispatch_semaphore_wait(flushSem, DISPATCH_TIME_FOREVER);
    return flushSucc;
}

- (NSMutableURLRequest *)buildRequestWithJSONString:(NSString *)jsonString {
    NSData *zippedData = [NSData gzipData:[jsonString dataUsingEncoding:NSUTF8StringEncoding]];
//    NSString *postBody = [zippedData base64EncodedStringWithOptions:0];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.serverURL];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:zippedData];
    NSString *contentType = [NSString stringWithFormat:@"text/plain"];
    [request addValue:contentType forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
    [request setTimeoutInterval:60.0];
    return request;
}

- (NSMutableURLRequest *)buildDebugRequestWithJSONString:(NSString *)jsonString withAppid:(NSString *)appid withDeviceId:(NSString *)deviceId {
    // dryRun=0，如果校验通过就会入库。 dryRun=1，不会入库
    int dryRun = _debugMode == DataEyeDebugOnly ? 1 : 0;
    NSString *postData = [NSString stringWithFormat:@"appid=%@&source=client&dryRun=%d&deviceId=%@&data=%@", appid, dryRun, deviceId, [self URLEncode:jsonString]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.serverDebugURL];
    [request setHTTPMethod:@"POST"];
    request.HTTPBody = [postData dataUsingEncoding:NSUTF8StringEncoding];
    return request;
}

- (void)fetchRemoteConfig:(DEFlushConfigBlock)handler {
    void (^block)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
            DELogError(@"Fetch remote config network failed:%@", error);
            return;
        }
        NSError *err;
        NSDictionary *ret = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&err];
        if (err) {
            DELogError(@"Fetch remote config json error:%@", err);
            if(handler){
                handler([NSDictionary dictionary], err);
            }
        } else if ([ret isKindOfClass:[NSDictionary class]] && [ret[@"code"] isEqualToNumber:[NSNumber numberWithInt:10000]]) {
            DELogDebug(@"Fetch remote config : %@", [ret objectForKey:@"data"]);
            if(handler){
                handler([ret objectForKey:@"data"], error);
            }
        } else {
            DELogError(@"Fetch remote config failed");
        }
    };
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.serverURL];
    [request setHTTPMethod:@"Get"];
    NSURLSessionDataTask *task = [[self sharedURLSession] dataTaskWithRequest:request completionHandler:block];
    [task resume];
}

#pragma mark - NSURLSessionDelegate
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;

    if (self.sessionDidReceiveAuthenticationChallenge) {
        disposition = self.sessionDidReceiveAuthenticationChallenge(session, challenge, &credential);
    } else {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
                if (credential) {
                    disposition = NSURLSessionAuthChallengeUseCredential;
                } else {
                    disposition = NSURLSessionAuthChallengePerformDefaultHandling;
                }
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }

    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

@end
