#import "DEConfig.h"

#import "DENetwork.h"
#import "DataEyeSDKPrivate.h"
#import "DESecurityPolicy.h"
#import "DEFile.h"
#import "DEMarco.h"

#define DESDKSETTINGS_PLIST_SETTING_IMPL(TYPE, PLIST_KEY, GETTER, SETTER, DEFAULT_VALUE, ENABLE_CACHE) \
static TYPE *g_##PLIST_KEY = nil; \
+ (TYPE *)GETTER \
{ \
  if (!g_##PLIST_KEY && ENABLE_CACHE) { \
    g_##PLIST_KEY = [[[NSUserDefaults standardUserDefaults] objectForKey:@#PLIST_KEY] copy]; \
  } \
  if (!g_##PLIST_KEY) { \
    g_##PLIST_KEY = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@#PLIST_KEY] copy] ?: DEFAULT_VALUE; \
  } \
  return g_##PLIST_KEY; \
} \
+ (void)SETTER:(TYPE *)value { \
  g_##PLIST_KEY = [value copy]; \
  if (ENABLE_CACHE) { \
    if (value) { \
      [[NSUserDefaults standardUserDefaults] setObject:value forKey:@#PLIST_KEY]; \
    } else { \
      [[NSUserDefaults standardUserDefaults] removeObjectForKey:@#PLIST_KEY]; \
    } \
  } \
}

static DEConfig * _defaultTDConfig;

@implementation DEConfig

DESDKSETTINGS_PLIST_SETTING_IMPL(NSNumber, DataEyeMaxCacheSize, _maxNumEventsNumber, _setMaxNumEventsNumber, @10000, NO);
DESDKSETTINGS_PLIST_SETTING_IMPL(NSNumber, DataEyeExpirationDays, _expirationDaysNumber, _setExpirationDaysNumber, @10, NO);

+ (DEConfig *)defaultTDConfig {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _defaultTDConfig = [DEConfig new];
    });
    return _defaultTDConfig;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _trackRelaunchedInBackgroundEvents = NO;
        _autoTrackEventType = DataEyeEventTypeNone;
        _networkTypePolicy = DataEyeNetworkTypeWIFI | DataEyeNetworkType3G | DataEyeNetworkType4G | DataEyeNetworkType2G | DataEyeNetworkType5G;
        _securityPolicy = [DESecurityPolicy defaultPolicy];
        _defaultTimeZone = [NSTimeZone localTimeZone];
    }
    return self;
}

- (instancetype)initWithAppId:(NSString *)appId serverUrl:(NSString *)serverUrl
{
    self = [self init];
    if (self) {
        _appid = appId;
        _configureURL = serverUrl;
    }
    return self;
}



- (void)updateConfig:(DESettingCallback)callback {
    NSString *serverUrlStr = [NSString stringWithFormat:@"%@/v1/settings?app_id=%@",self.baseUrl, self.appid];
    DENetwork *network = [[DENetwork alloc] init];
    network.serverURL = [NSURL URLWithString:serverUrlStr];
    network.securityPolicy = _securityPolicy;
    
    
    [network fetchRemoteConfig:^(NSDictionary * _Nonnull result, NSError * _Nullable error) {
        DELogInfo(@"fetchRemoteConfig, error = %@", [error description]);
        if (!error) {
            NSMutableDictionary * resultConfig = [NSMutableDictionary dictionary];
            DELogInfo(@"fetchRemoteConfig, result = %@", result);
            DEFile *file = [[DEFile alloc] initWithAppid:self.appid];
            NSDictionary * prdInfo = [result objectForKey:@"prd_info"];
            if(prdInfo){
            
                BOOL appStatus = [[prdInfo objectForKey:@"status"] boolValue];
                if(appStatus){
                    [file archiveAppStatus:1];
                    [resultConfig setValue:[NSNumber numberWithInteger:1] forKey:@"status"];
                }else{
                    [file archiveAppStatus:-1];
                    [resultConfig setValue:[NSNumber numberWithInteger:-1] forKey:@"status"];
                }
                
                NSString * upUrl = [prdInfo objectForKey:@"up-url"];
                [resultConfig setValue:upUrl forKey:@"up-url"];
                if(!DE_NSSTRING_NOT_NULL(upUrl)){
                    [file archiveUpUrl:upUrl];
                }
                DELogInfo(@"fetchRemoteConfig, appStatus = %ld, upUrl = %@", appStatus, upUrl);
            }
            
            NSInteger uploadInterval = [[result objectForKey:@"sync_interval"] integerValue];
            NSInteger uploadSize = [[result objectForKey:@"sync_batch_size"] integerValue];
            if (uploadInterval != [self->_uploadInterval integerValue] || uploadSize != [self->_uploadSize integerValue]) {
            
                if (uploadInterval > 0) {
                    self.uploadInterval = [NSNumber numberWithInteger:uploadInterval];
                    [file archiveUploadInterval:self.uploadInterval];
                    [[DataEyeSDK sharedInstanceWithAppid:self.appid] startFlushTimer];
                }
                if (uploadSize > 0) {
                    self.uploadSize = [NSNumber numberWithInteger:uploadSize];
                    [file archiveUploadSize:self.uploadSize];
                }
            }
            self.disableEvents = [result objectForKey:@"disable_event_list"];
            
            if(callback) {
                callback(resultConfig, nil);
            }
        }else{
            if(callback) {
                callback(nil, error);
            }
        }
    }];
}

- (void)setNetworkType:(DENetworkType)type {
    if (type == DENetworkTypeDefault) {
        _networkTypePolicy = DataEyeNetworkTypeWIFI | DataEyeNetworkType3G | DataEyeNetworkType4G | DataEyeNetworkType2G | DataEyeNetworkType5G;
    } else if (type == DENetworkTypeOnlyWIFI) {
        _networkTypePolicy = DataEyeNetworkTypeWIFI;
    } else if (type == DENetworkTypeALL) {
        _networkTypePolicy = DataEyeNetworkTypeWIFI | DataEyeNetworkType3G | DataEyeNetworkType4G | DataEyeNetworkType2G | DataEyeNetworkType5G;
    }
}

#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone {
    DEConfig *config = [[[self class] allocWithZone:zone] init];
    config.trackRelaunchedInBackgroundEvents = self.trackRelaunchedInBackgroundEvents;
    config.autoTrackEventType = self.autoTrackEventType;
    config.networkTypePolicy = self.networkTypePolicy;
    config.launchOptions = [self.launchOptions copyWithZone:zone];
    config.debugMode = self.debugMode;
    config.securityPolicy = [self.securityPolicy copyWithZone:zone];
    config.defaultTimeZone = [self.defaultTimeZone copyWithZone:zone];
    return config;
}

#pragma mark - SETTINGS
+ (NSInteger)maxNumEvents {
    NSInteger maxNumEvents = [self _maxNumEventsNumber].integerValue;
    if (maxNumEvents < 5000) {
        maxNumEvents = 5000;
    }
    return maxNumEvents;
}

+ (void)setMaxNumEvents:(NSInteger)maxNumEventsNumber {
    [self _setMaxNumEventsNumber:@(maxNumEventsNumber)];
}

+ (NSInteger)expirationDays {
    NSInteger maxNumEvents = [self _expirationDaysNumber].integerValue;
    return maxNumEvents >= 0 ? maxNumEvents : 10;
}

+ (void)setExpirationDays:(NSInteger)expirationDays {
    [self _setExpirationDaysNumber:@(expirationDays)];
}

@end
