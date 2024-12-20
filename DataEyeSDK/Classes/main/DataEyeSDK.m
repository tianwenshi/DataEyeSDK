#import "DataEyeSDKPrivate.h"

#import "DEAutoTrackManager.h"
#import "DECalibratedTimeWithNTP.h"
#import "DEConfig.h"
#import "DEPublicConfig.h"
#import "DEFile.h"
#import "DENetwork.h"
#import "DEMarco.h"

#if !__has_feature(objc_arc)
#error The DataEyeSDK library must be compiled with ARC enabled
#endif

@interface DEPresetProperties (DataEye)

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (void)updateValuesWithDictionary:(NSDictionary *)dict;

@end

@interface DataEyeSDK ()
@property (atomic, strong)   DENetwork *network;
@property (atomic, strong)   DEAutoTrackManager *autoTrackManager;
@property (strong,nonatomic) DEFile *file;

@property (nonatomic, assign) NSInteger appStatus;
@end

@implementation DataEyeSDK

static NSMutableDictionary *instances;
static NSString *defaultProjectAppid;
static BOOL isWifi;
static BOOL isWwan;
static DECalibratedTime *calibratedTime;
static dispatch_queue_t serialQueue;
static dispatch_queue_t networkQueue;

+ (nullable DataEyeSDK *)sharedInstance {
    if (instances.count == 0) {
        DELogError(@"sharedInstance called before creating a DataEye instance");
        return nil;
    }
    
    return instances[defaultProjectAppid];
}

+ (DataEyeSDK *)sharedInstanceWithAppid:(NSString *)appid {
    if (instances[appid]) {
        return instances[appid];
    } else {
        DELogError(@"sharedInstanceWithAppid called before creating a DataEye instance");
        return nil;
    }
}

+ (DataEyeSDK *)startWithAppId:(NSString *)appId withUrl:(NSString *)url withConfig:(DEConfig *)config {
    if (instances[appId]) {
        return instances[appId];
    } else if (![url isKindOfClass:[NSString class]] || url.length == 0) {
        return nil;
    }
    
    return [[self alloc] initWithAppkey:appId withServerURL:url withConfig:config];
}

+ (DataEyeSDK *)startWithAppId:(NSString *)appId withUrl:(NSString *)url {
    return [DataEyeSDK startWithAppId:appId withUrl:url withConfig:nil];
}

+ (DataEyeSDK *)startWithConfig:(nullable DEConfig *)config {
    return [DataEyeSDK startWithAppId:config.appid withUrl:config.configureURL withConfig:config];
}

- (instancetype)init:(NSString *)appID {
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            instances = [NSMutableDictionary dictionary];
            defaultProjectAppid = appID;
        });
    }
    
    return self;
}

+ (void)initialize {
    static dispatch_once_t DayaEyeOnceToken;
    dispatch_once(&DayaEyeOnceToken, ^{
        NSString *queuelabel = [NSString stringWithFormat:@"cn.thinkingdata.%p", (void *)self];
        serialQueue = dispatch_queue_create([queuelabel UTF8String], DISPATCH_QUEUE_SERIAL);
        NSString *networkLabel = [queuelabel stringByAppendingString:@".network"];
        networkQueue = dispatch_queue_create([networkLabel UTF8String], DISPATCH_QUEUE_SERIAL);
    });
}

+ (dispatch_queue_t)serialQueue {
    return serialQueue;
}

+ (dispatch_queue_t)networkQueue {
    return networkQueue;
}

- (instancetype)initLight:(NSString *)appid withServerURL:(NSString *)reportURL withConfig:(DEConfig *)config {
    if (self = [self init]) {
        NSString * baseUrl = [self checkServerURL:reportURL];
        _appid = appid;
        _isEnabled = YES;
        _reportURL = reportURL;
        _config = [config copy];
        _config.configureURL = reportURL;
        
        self.trackTimer = [NSMutableDictionary dictionary];
        _timeFormatter = [[NSDateFormatter alloc] init];
        _timeFormatter.dateFormat = kDefaultTimeFormat;
        _timeFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        _timeFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        _timeFormatter.timeZone = config.defaultTimeZone;
        self.file = [[DEFile alloc] initWithAppid:appid];
        
        NSString *keyPattern = @"^[a-zA-Z][a-zA-Z\\d_]{0,49}$";
        self.regexKey = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", keyPattern];
        
        self.dataQueue = [DESqliteDataQueue sharedInstanceWithAppid:appid];
        if (self.dataQueue == nil) {
            DELogError(@"SqliteException: init SqliteDataQueue failed");
        }
        
        _network = [[DENetwork alloc] init];
        _network.debugMode = config.debugMode;
        _network.appid = appid;
        _network.sessionDidReceiveAuthenticationChallenge = config.securityPolicy.sessionDidReceiveAuthenticationChallenge;
        if (config.debugMode == DataEyeDebugOnly || config.debugMode == DataEyeDebug) {
            _network.serverDebugURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/data_debug", baseUrl]];
        }
        _network.securityPolicy = config.securityPolicy;
    }
    return self;
}

- (instancetype)initWithAppkey:(NSString *)appid withServerURL:(NSString *)reportURL withConfig:(DEConfig *)config {
    if (self = [self init:appid]) {
//        NSString * baseUrl = [self checkServerURL:reportURL];
//        self.reportURL = reportURL;
        self.appid = appid;
        
        [self login:[self getDeviceId]];
        
        if (!config) {
            config = DEConfig.defaultTDConfig;
        }
        
        _config = [config copy];
        _config.appid = appid;
        [self updateReportUrl:reportURL newReportUrl:[self.file unarchiveUpUrl]];
        
        self.file = [[DEFile alloc] initWithAppid:appid];
        [self retrievePersistedData];
        self.appStatus = [self.file unarchiveAppStatus];
        DELogInfo(@"initWithAppkey, appStatus = %lu", self.appStatus);
        //次序不能调整
        [_config updateConfig:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if(error == nil && result != nil){
                NSNumber * appStatusNum = [result valueForKey:@"status"];
                if(appStatusNum){
                    self.appStatus = [appStatusNum integerValue];
                }
                
                NSString * newUrl = [result valueForKey:@"up-url"];
                [self updateReportUrl:reportURL newReportUrl:newUrl];
            }
        }];
        
        self.trackTimer = [NSMutableDictionary dictionary];
        _timeFormatter = [[NSDateFormatter alloc] init];
        _timeFormatter.dateFormat = kDefaultTimeFormat;
        _timeFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        _timeFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        _timeFormatter.timeZone = config.defaultTimeZone;

        _applicationWillResignActive = NO;
        _ignoredViewControllers = [[NSMutableSet alloc] init];
        _ignoredViewTypeList = [[NSMutableSet alloc] init];
        
        self.taskId = UIBackgroundTaskInvalid;
        
        NSString *keyPattern = @"^[a-zA-Z][a-zA-Z\\d_]{0,49}$";
        self.regexKey = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", keyPattern];
        NSString *keyAutoTrackPattern = @"^([a-zA-Z][a-zA-Z\\d_]{0,49}|\\#(resume_from_background|app_crashed_reason|screen_name|referrer|title|url|element_id|element_type|element_content|element_position))$";
        self.regexAutoTrackKey = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", keyAutoTrackPattern];
        
        self.dataQueue = [DESqliteDataQueue sharedInstanceWithAppid:appid];
        if (self.dataQueue == nil) {
            DELogError(@"SqliteException: init SqliteDataQueue failed");
        }
        
        [self setNetRadioListeners];
        
        self.autoTrackManager = [DEAutoTrackManager sharedManager];
        
        _network = [[DENetwork alloc] init];
        _network.debugMode = config.debugMode;
        _network.appid = appid;
        _network.sessionDidReceiveAuthenticationChallenge = config.securityPolicy.sessionDidReceiveAuthenticationChallenge;
        if (config.debugMode == DataEyeDebugOnly || config.debugMode == DataEyeDebug) {
            NSString * baseUrl = [self checkServerURL:self.reportURL];
            _network.serverDebugURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/data_debug",baseUrl]];
        }
        _network.serverURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@",self.reportURL]];
        _network.securityPolicy = config.securityPolicy;
        
        [self sceneSupportSetting];
        
        if(calibratedTime == nil){
            [DataEyeSDK calibrateTimeWithNtps:@[DE_NTP_SERVER_1, DE_NTP_SERVER_1, DE_NTP_SERVER_3, DE_NTP_SERVER_CN]];
        }
        
#ifdef __IPHONE_13_0
        if (@available(iOS 13.0, *)) {
            if (!_isEnableSceneSupport) {
                [self launchedIntoBackground:config.launchOptions];
            } else if (config.launchOptions && [config.launchOptions objectForKey:UIApplicationLaunchOptionsLocationKey]) {
                _relaunchInBackGround = YES;
            } else {
                _relaunchInBackGround = NO;
            }
        }
#else
        [self launchedIntoBackground:config.launchOptions];
#endif
        
        [self startFlushTimer];
        [self setApplicationListeners];
        
        instances[appid] = self;
        
        DELogInfo(@"DataEye Analytics SDK %@ instance initialized successfully with mode: %@, APP ID: %@, server url: %@, device ID: %@", [DEDeviceInfo libVersion], [self modeEnumToString:config.debugMode], appid, reportURL, [self getDeviceId]);
    }
    return self;
}

-(void)updateReportUrl:(NSString *)defaultReportUrl newReportUrl:(NSString *)newUrl {
    
    NSString * reportUrl = defaultReportUrl;
    if(DE_NSSTRING_NOT_NULL(newUrl)){
        reportUrl = newUrl;
    }
    
    NSString * baseUrl = [self checkServerURL:reportUrl];
    self.reportURL = reportUrl;
    
    if(self.config){
        self.config.baseUrl = baseUrl;
        self.config.configureURL = reportUrl;
    }
    
    if(self.network){
        if (self.config.debugMode == DataEyeDebugOnly || self.config.debugMode == DataEyeDebug) {
            _network.serverDebugURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/data_debug",baseUrl]];
        }
        _network.serverURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@",reportUrl]];
    }
    
    DELogInfo(@"updateReportUrl, final reportURL = %@", self.reportURL);
}

- (void)launchedIntoBackground:(NSDictionary *)launchOptions {
    td_dispatch_main_sync_safe(^{
        if (launchOptions && [launchOptions objectForKey:UIApplicationLaunchOptionsLocationKey]) {
            UIApplicationState applicationState = [UIApplication sharedApplication].applicationState;
            if (applicationState == UIApplicationStateBackground) {
                self->_relaunchInBackGround = YES;
            }
        }
    });
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<DataEyeSDK: %p - appid: %@ serverUrl: %@>", (void *)self, self.appid, self.reportURL];
}

+ (UIApplication *)sharedUIApplication {
    if ([[UIApplication class] respondsToSelector:@selector(sharedApplication)]) {
        return [[UIApplication class] performSelector:@selector(sharedApplication)];
    }
    return nil;
}

#pragma mark - EnableTracking
- (void)enableTracking:(BOOL)enabled {
    self.isEnabled = enabled;
    
    dispatch_async(serialQueue, ^{
        [self.file archiveIsEnabled:self.isEnabled];
    });
}

- (BOOL)hasDisabled {
    
    if(self.appStatus < 0){
        return YES;
    }
    
    return !_isEnabled || _isOptOut;
}

- (void)optOutTracking {
    DELogDebug(@"%@ optOutTracking...", self);
    [self doOptOutTracking];
}

- (void)doOptOutTracking {
    self.isOptOut = YES;
    
    @synchronized (self.trackTimer) {
        [self.trackTimer removeAllObjects];
    }
    
    @synchronized (self.superProperty) {
        self.superProperty = [NSDictionary new];
    }
    
    @synchronized (self.identifyId) {
        self.identifyId = [DEDeviceInfo sharedManager].uniqueId;
    }
    
    @synchronized (self.accountId) {
        self.accountId = nil;
    }
    
    dispatch_async(serialQueue, ^{
        @synchronized (instances) {
            [self.dataQueue deleteAll:self.appid];
        }
        
        [self.file archiveAccountID:nil];
        [self.file archiveIdentifyId:nil];
        [self.file archiveSuperProperties:nil];
        [self.file archiveOptOut:YES];
    });
}

- (void)optOutTrackingAndDeleteUser {
    DELogDebug(@"%@ optOutTrackingAndDeleteUser...", self);
    DEEventModel *eventData = [[DEEventModel alloc] initWithEventName:nil eventType:DE_EVENT_TYPE_USER_DEL];
    eventData.persist = NO;
    [self tdInternalTrack:eventData];
    [self doOptOutTracking];
}

- (void)optInTracking {
    DELogDebug(@"%@ optInTracking...", self);
    self.isOptOut = NO;
    [self.file archiveOptOut:NO];
}

#pragma mark - LightInstance
- (DataEyeSDK *)createLightInstance {
    DataEyeSDK *lightInstance = [[LightDataEyeSDK alloc] initWithAPPID:self.appid withServerURL:self.reportURL withConfig:self.config];
    lightInstance.identifyId = [DEDeviceInfo sharedManager].uniqueId;
    lightInstance.relaunchInBackGround = self.relaunchInBackGround;
    lightInstance.isEnableSceneSupport = self.isEnableSceneSupport;
    return lightInstance;
}

#pragma mark - Persistence
- (void)retrievePersistedData {
    self.accountId = [self.file unarchiveAccountID];
    self.superProperty = [self.file unarchiveSuperProperties];
    self.identifyId = [self.file unarchiveIdentifyID];
    self.isEnabled = [self.file unarchiveEnabled];
    self.isOptOut  = [self.file unarchiveOptOut];
    self.config.uploadSize = [self.file unarchiveUploadSize];
    self.config.uploadInterval = [self.file unarchiveUploadInterval];
    if (self.identifyId.length == 0) {
        self.identifyId = [DEDeviceInfo sharedManager].uniqueId;
    }
    // 兼容老版本
    if (self.accountId.length == 0) {
        self.accountId = [self.file unarchiveAccountID];
        [self.file archiveAccountID:self.accountId];
        [self.file deleteOldLoginId];
    }
}

- (NSInteger)saveEventsData:(NSDictionary *)data {
    NSMutableDictionary *event = [[NSMutableDictionary alloc] initWithDictionary:data];
    NSInteger count;
    @synchronized (instances) {
        count = [self.dataQueue addObject:event withAppid:self.appid];
    }
    return count;
}

- (void)deleteAll {
    dispatch_async(serialQueue, ^{
        @synchronized (instances) {
            [self.dataQueue deleteAll:self.appid];
        }
    });
}

#pragma mark - UIApplication Events
- (void)setApplicationListeners {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillEnterForeground:)
                               name:UIApplicationWillEnterForegroundNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActive:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillResignActive:)
                               name:UIApplicationWillResignActiveNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidEnterBackground:)
                               name:UIApplicationDidEnterBackgroundNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillTerminate:)
                               name:UIApplicationWillTerminateNotification
                             object:nil];
    
}

- (void)setNetRadioListeners {
    if ((_reachability = SCNetworkReachabilityCreateWithName(NULL,"thinkingdata.cn")) != NULL) {
        SCNetworkReachabilityFlags flags;
        BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(_reachability, &flags);
        if (didRetrieveFlags) {
            isWifi = (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsIsWWAN);
            isWwan = (flags & kSCNetworkReachabilityFlagsIsWWAN);
        }
        SCNetworkReachabilityContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        if (SCNetworkReachabilitySetCallback(_reachability, DataEyeReachabilityCallback, &context)) {
            if (!SCNetworkReachabilitySetDispatchQueue(_reachability, serialQueue)) {
                SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
            }
        }
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    DELogDebug(@"%@ application will enter foreground", self);
    
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
        _relaunchInBackGround = NO;
        _appRelaunched = YES;
        dispatch_async(serialQueue, ^{
            if (self.taskId != UIBackgroundTaskInvalid) {
                [[DataEyeSDK sharedUIApplication] endBackgroundTask:self.taskId];
                self.taskId = UIBackgroundTaskInvalid;
            }
        });
    }
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    DELogDebug(@"%@ application did enter background", self);
    _relaunchInBackGround = NO;
    _applicationWillResignActive = NO;
    
    __block UIBackgroundTaskIdentifier backgroundTask = [[DataEyeSDK sharedUIApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[DataEyeSDK sharedUIApplication] endBackgroundTask:backgroundTask];
        self.taskId = UIBackgroundTaskInvalid;
    }];
    self.taskId = backgroundTask;
    dispatch_group_t bgGroup = dispatch_group_create();

    dispatch_group_enter(bgGroup);
    dispatch_async(serialQueue, ^{
        NSNumber *currentTimeStamp = @([[NSDate date] timeIntervalSince1970]);
        @synchronized (self.trackTimer) {
            NSArray *keys = [self.trackTimer allKeys];
            for (NSString *key in keys) {
                if ([key isEqualToString:DE_APP_END_EVENT]) {
                    continue;
                }
                NSMutableDictionary *eventTimer = [[NSMutableDictionary alloc] initWithDictionary:self.trackTimer[key]];
                if (eventTimer) {
                    NSNumber *eventBegin = [eventTimer valueForKey:DE_EVENT_START];
                    NSNumber *eventDuration = [eventTimer valueForKey:DE_EVENT_DURATION];
                    double usedTime;
                    if (eventDuration) {
                        usedTime = [currentTimeStamp doubleValue] - [eventBegin doubleValue] + [eventDuration doubleValue];
                    } else {
                        usedTime = [currentTimeStamp doubleValue] - [eventBegin doubleValue];
                    }
                    [eventTimer setObject:[NSNumber numberWithDouble:usedTime] forKey:DE_EVENT_DURATION];
                    self.trackTimer[key] = eventTimer;
                }
            }
        }
        dispatch_group_leave(bgGroup);
    });
    
    if (_config.autoTrackEventType & DataEyeEventTypeAppEnd) {
        NSString *screenName = NSStringFromClass([[DEAutoTrackManager topPresentedViewController] class]);
        screenName = (screenName == nil) ? @"" : screenName;
        [self autotrack:DE_APP_END_EVENT properties:@{DE_EVENT_PROPERTY_SCREEN_NAME: screenName} withTime:nil];
    }
    
    dispatch_group_enter(bgGroup);
    [self syncWithCompletion:^{
        dispatch_group_leave(bgGroup);
    }];
    
    dispatch_group_notify(bgGroup, dispatch_get_main_queue(), ^{
        if (self.taskId != UIBackgroundTaskInvalid) {
            [[DataEyeSDK sharedUIApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
        }
    });
    
    dispatch_sync([DataEyeSDK serialQueue], ^{});
    dispatch_sync([DataEyeSDK networkQueue], ^{});
}

- (void)applicationWillTerminate:(UIApplication *)application {
    dispatch_sync([DataEyeSDK serialQueue], ^{});
    dispatch_sync([DataEyeSDK networkQueue], ^{});
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    DELogDebug(@"%@ application will resign active", self);
    _applicationWillResignActive = YES;
    [self stopFlushTimer];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    DELogDebug(@"%@ application did become active", self);
    [self startFlushTimer];
    
    if (_applicationWillResignActive) {
        _applicationWillResignActive = NO;
        return;
    }
    _applicationWillResignActive = NO;
    
    dispatch_async(serialQueue, ^{
        NSNumber *currentTime = @([[NSDate date] timeIntervalSince1970]);
        @synchronized (self.trackTimer) {
            NSArray *keys = [self.trackTimer allKeys];
            for (NSString *key in keys) {
                NSMutableDictionary *eventTimer = [[NSMutableDictionary alloc] initWithDictionary:self.trackTimer[key]];
                if (eventTimer) {
                    [eventTimer setValue:currentTime forKey:DE_EVENT_START];
                    self.trackTimer[key] = eventTimer;
                }
            }
        }
    });
    
    if (_appRelaunched) {
        if (_config.autoTrackEventType & DataEyeEventTypeAppStart) {
            [self autotrack:DE_APP_START_EVENT properties:@{DE_RESUME_FROM_BACKGROUND:@(_appRelaunched)} withTime:nil];
        }
        if (_config.autoTrackEventType & DataEyeEventTypeAppEnd) {
            [self timeEvent:DE_APP_END_EVENT];
        }
    }
}

- (void)sceneSupportSetting {
    NSDictionary *sceneManifest = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIApplicationSceneManifest"];
    if (sceneManifest) {
        NSDictionary *sceneConfig = sceneManifest[@"UISceneConfigurations"];
        if (sceneConfig.count > 0) {
            _isEnableSceneSupport = YES;
        } else {
            _isEnableSceneSupport = NO;
        }
    } else {
        _isEnableSceneSupport = NO;
    }
}

- (void)setNetworkType:(DENetworkType)type {
    if ([self hasDisabled])
        return;
        
    [self.config setNetworkType:type];
}

- (DataEyeNetworkType)convertNetworkType:(NSString *)networkType {
    if ([@"NULL" isEqualToString:networkType]) {
        return DataEyeNetworkTypeALL;
    } else if ([@"WIFI" isEqualToString:networkType]) {
        return DataEyeNetworkTypeWIFI;
    } else if ([@"2G" isEqualToString:networkType]) {
        return DataEyeNetworkType2G;
    } else if ([@"3G" isEqualToString:networkType]) {
        return DataEyeNetworkType3G;
    } else if ([@"4G" isEqualToString:networkType]) {
        return DataEyeNetworkType4G;
    }else if([@"5G"isEqualToString:networkType])
    {
        return DataEyeNetworkType5G;
    }
    return DataEyeNetworkTypeNONE;
}

static void DataEyeReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    DataEyeSDK *dataeye = (__bridge DataEyeSDK *)info;
    if (dataeye && [dataeye isKindOfClass:[DataEyeSDK class]]) {
        [dataeye reachabilityChanged:flags];
    }
}

- (void)reachabilityChanged:(SCNetworkReachabilityFlags)flags {
    isWifi = (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsIsWWAN);
    isWwan = (flags & kSCNetworkReachabilityFlagsIsWWAN);
}

+ (NSString *)currentRadio {
    NSString *networkType = @"NULL";
    @try {
        static CTTelephonyNetworkInfo *info = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            info = [[CTTelephonyNetworkInfo alloc] init];
        });
        NSString *currentRadio = nil;
#ifdef __IPHONE_12_0
        if (@available(iOS 12.0, *)) {
            NSDictionary *serviceCurrentRadio = [info serviceCurrentRadioAccessTechnology];
            if ([serviceCurrentRadio isKindOfClass:[NSDictionary class]] && serviceCurrentRadio.allValues.count>0) {
                currentRadio = serviceCurrentRadio.allValues[0];
            }
        }
#endif
        if (currentRadio == nil && [info.currentRadioAccessTechnology isKindOfClass:[NSString class]]) {
            currentRadio = info.currentRadioAccessTechnology;
        }
        
        if ([currentRadio isEqualToString:CTRadioAccessTechnologyLTE]) {
            networkType = @"4G";
        } else if ([currentRadio isEqualToString:CTRadioAccessTechnologyeHRPD] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyCDMA1x] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyHSUPA] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyHSDPA] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyWCDMA]) {
            networkType = @"3G";
        } else if ([currentRadio isEqualToString:CTRadioAccessTechnologyEdge] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyGPRS]) {
            networkType = @"2G";
        }
#ifdef __IPHONE_14_1
        else if (@available(iOS 14.1, *)) {
            if ([currentRadio isKindOfClass:[NSString class]]) {
                if([currentRadio isEqualToString:CTRadioAccessTechnologyNRNSA] ||
                   [currentRadio isEqualToString:CTRadioAccessTechnologyNR]) {
                    networkType = @"5G";
                }
            }
        }
#endif
    } @catch (NSException *exception) {
        DELogError(@"%@: %@", self, exception);
    }
    
    return networkType;
}

+ (NSString *)getNetWorkStates {
    if (isWifi) {
        return @"WIFI";
    } else if (isWwan) {
        return [self currentRadio];
    } else {
        return @"NULL";
    }
}

#pragma mark - Public

- (void)track:(NSString *)event {
    if ([self hasDisabled]){
        DELogInfo(@"track, sdk is disabled, return");
        return;
    }
    [self track:event properties:nil];
}

- (void)track:(NSString *)event properties:(NSDictionary *)propertiesDict {
    if ([self hasDisabled]){
        DELogInfo(@"track, sdk is disabled, return");
        return;
    }
    propertiesDict = [self processParameters:propertiesDict withType:DE_EVENT_TYPE_TRACK withEventName:event withAutoTrack:NO withH5:NO];
    DEEventModel *eventData = [[DEEventModel alloc] initWithEventName:event];
    eventData.properties = [propertiesDict copy];
    eventData.timeValueType = DETimeValueTypeNone;
    [self tdInternalTrack:eventData];
}

// deprecated  使用 track:properties:time:timeZone: 方法传入
- (void)track:(NSString *)event properties:(NSDictionary *)propertiesDict time:(NSDate *)time {
    if ([self hasDisabled]){
        DELogInfo(@"track, sdk is disabled, return");
        return;
    }
    propertiesDict = [self processParameters:propertiesDict withType:DE_EVENT_TYPE_TRACK withEventName:event withAutoTrack:NO withH5:NO];
    DEEventModel *eventData = [[DEEventModel alloc] initWithEventName:event];
    eventData.properties = [propertiesDict copy];
    eventData.timeString = [_timeFormatter stringFromDate:time];
    eventData.timeValueType = DETimeValueTypeTimeOnly;
    [self tdInternalTrack:eventData];
}

- (void)track:(NSString *)event properties:(nullable NSDictionary *)properties time:(NSDate *)time timeZone:(NSTimeZone *)timeZone {
    if ([self hasDisabled]){
        DELogInfo(@"track, sdk is disabled, return");
        return;
    }
    if (timeZone == nil) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self track:event properties:properties time:time];
#pragma clang diagnostic pop
        return;
    }
    properties = [self processParameters:properties withType:DE_EVENT_TYPE_TRACK withEventName:event withAutoTrack:NO withH5:NO];
    DEEventModel *eventData = [[DEEventModel alloc] initWithEventName:event];
    eventData.properties = [properties copy];
    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    timeFormatter.dateFormat = kDefaultTimeFormat;
    timeFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    timeFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    timeFormatter.timeZone = timeZone;
    eventData.timeString = [timeFormatter stringFromDate:time];
    eventData.zoneOffset = [self getTimezoneOffset:time timeZone:timeZone];
    eventData.timeValueType = DETimeValueTypeAll;
    [self tdInternalTrack:eventData];
}

- (void)trackWithEventModel:(DEEventModel *)eventModel {
    NSDictionary *dic = eventModel.properties;
    eventModel.properties = [self processParameters:dic
                                           withType:eventModel.eventType
                                      withEventName:eventModel.eventName
                                      withAutoTrack:NO
                                             withH5:NO];
    [self tdInternalTrack:eventModel];
}

#pragma mark - Private

- (NSString *)checkServerURL:(NSString *)urlString {
    urlString = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = [url scheme];
    NSString *host = [url host];
    NSNumber *port = [url port];
    
    if (scheme && scheme.length>0 && host && host.length>0) {
        urlString = [NSString stringWithFormat:@"%@://%@", scheme, host];
        if (port && [port stringValue]) {
            urlString = [urlString stringByAppendingFormat:@":%@", [port stringValue]];
        }
    }
    return urlString;
}

- (void)h5track:(NSString *)eventName
        extraID:(NSString *)extraID
     properties:(NSDictionary *)propertieDict
           type:(NSString *)type
           time:(NSString *)time {
    
    if ([self hasDisabled])
        return;
    propertieDict = [self processParameters:propertieDict withType:type withEventName:eventName withAutoTrack:NO withH5:YES];
    DEEventModel *eventData;
    
    if (extraID.length > 0) {
        if ([type isEqualToString:DE_EVENT_TYPE_TRACK]) {
            eventData = [[DEEventModel alloc] initWithEventName:eventName eventType:DE_EVENT_TYPE_TRACK_FIRST];
        } else {
            eventData = [[DEEventModel alloc] initWithEventName:eventName eventType:type];
        }
        eventData.extraID = extraID;
    } else {
        eventData = [[DEEventModel alloc] initWithEventName:eventName];
    }
    eventData.properties = [propertieDict copy];

    if ([propertieDict objectForKey:@"#zone_offset"]) {
        eventData.zoneOffset = [[propertieDict objectForKey:@"#zone_offset"] doubleValue];
        eventData.timeValueType = DETimeValueTypeAll;
    } else {
        eventData.timeValueType = DETimeValueTypeTimeOnly;
    }
    eventData.timeString = time;
    [self tdInternalTrack:eventData];
}

- (void)autotrack:(NSString *)event properties:(NSDictionary *)propertieDict withTime:(NSDate *)time {
    if ([self hasDisabled]){
        DELogInfo(@"autotrack, sdk is disabled, return");
        return;
    }
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    [properties addEntriesFromDictionary:propertieDict];
    NSDictionary *superProperty = [NSDictionary dictionary];
    superProperty = [self processParameters:superProperty withType:DE_EVENT_TYPE_TRACK withEventName:event withAutoTrack:YES withH5:NO];
    [properties addEntriesFromDictionary:superProperty];
    DEEventModel *eventData = [[DEEventModel alloc] initWithEventName:event];
    eventData.properties = [properties copy];
    eventData.timeString = [_timeFormatter stringFromDate:time];
    eventData.timeValueType = DETimeValueTypeNone;
    [self tdInternalTrack:eventData];
}

- (double)getTimezoneOffset:(NSDate *)date timeZone:(NSTimeZone *)timeZone {
    NSTimeZone *tz = timeZone ? timeZone : [NSTimeZone localTimeZone];
    NSInteger sourceGMTOffset = [tz secondsFromGMTForDate:date];
    return (double)sourceGMTOffset/3600;
}

- (void)track:(NSString *)event withProperties:(NSDictionary *)properties withType:(NSString *)type {
    [self track:event withProperties:properties withType:type withTime:nil];
}

- (void)track:(NSString *)event withProperties:(NSDictionary *)properties withType:(NSString *)type withTime:(NSDate *)time {
    if ([self hasDisabled]){
        DELogInfo(@"track, sdk is disabled, return");
        return;
    }
    
    properties = [self processParameters:properties withType:type withEventName:event withAutoTrack:NO withH5:NO];
    DEEventModel *eventData = [[DEEventModel alloc] initWithEventName:event eventType:type];
    eventData.properties = [properties copy];
    if (time) {
        eventData.timeString = [_timeFormatter stringFromDate:time];
        eventData.timeValueType = DETimeValueTypeTimeOnly;
    } else {
        eventData.timeValueType = DETimeValueTypeNone;
    }
    [self tdInternalTrack:eventData];
}

+ (BOOL)isTrackEvent:(NSString *)eventType {
    return [DE_EVENT_TYPE_TRACK isEqualToString:eventType]
    || [DE_EVENT_TYPE_TRACK_FIRST isEqualToString:eventType]
    || [DE_EVENT_TYPE_TRACK_UPDATE isEqualToString:eventType]
    || [DE_EVENT_TYPE_TRACK_OVERWRITE isEqualToString:eventType]
    ;
}

#pragma mark - User

- (void)user_add:(NSString *)propertyName andPropertyValue:(NSNumber *)propertyValue {
    [self user_add:propertyName andPropertyValue:propertyValue withTime:nil];
}

- (void)user_add:(NSString *)propertyName andPropertyValue:(NSNumber *)propertyValue withTime:(NSDate *)time {
    if (propertyName && propertyValue) {
        [self track:nil withProperties:@{propertyName:propertyValue} withType:DE_EVENT_TYPE_USER_ADD withTime:time];
    }
}

- (void)user_add:(NSDictionary *)properties {
    [self user_add:properties withTime:nil];
}

- (void)user_add:(NSDictionary *)properties withTime:(NSDate *)time {
    if ([self hasDisabled])
        return;
    [self track:nil withProperties:properties withType:DE_EVENT_TYPE_USER_ADD withTime:time];
}

- (void)user_setOnce:(NSDictionary *)properties {
    [self user_setOnce:properties withTime:nil];
}

- (void)user_setOnce:(NSDictionary *)properties withTime:(NSDate *)time {
    [self track:nil withProperties:properties withType:DE_EVENT_TYPE_USER_SETONCE withTime:time];
}

- (void)user_set:(NSDictionary *)properties {
    [self user_set:properties withTime:nil];
}

- (void)user_set:(NSDictionary *)properties withTime:(NSDate *)time {
    [self track:nil withProperties:properties withType:DE_EVENT_TYPE_USER_SET withTime:time];
}

- (void)user_unset:(NSString *)propertyName {
    [self user_unset:propertyName withTime:nil];
}

- (void)user_unset:(NSString *)propertyName withTime:(NSDate *)time {
    if ([propertyName isKindOfClass:[NSString class]] && propertyName.length > 0) {
        NSDictionary *properties = @{propertyName: @0};
        [self track:nil withProperties:properties withType:DE_EVENT_TYPE_USER_UNSET withTime:time];
    }
}

- (void)user_delete {
    [self user_delete:nil];
}

- (void)user_delete:(NSDate *)time {
    [self track:nil withProperties:nil withType:DE_EVENT_TYPE_USER_DEL withTime:time];
}

- (void)user_append:(NSDictionary<NSString *, NSArray *> *)properties {
    [self user_append:properties withTime:nil];
}

- (void)user_append:(NSDictionary<NSString *, NSArray *> *)properties withTime:(NSDate *)time {
    [self track:nil withProperties:properties withType:DE_EVENT_TYPE_USER_APPEND withTime:time];
}

+ (void)setCustomerLibInfoWithLibName:(NSString *)libName libVersion:(NSString *)libVersion {
    if (libName.length > 0) {
        [DEDeviceInfo sharedManager].libName = libName;
    }
    if (libVersion.length > 0) {
        [DEDeviceInfo sharedManager].libVersion = libVersion;
    }
    [[DEDeviceInfo sharedManager] updateAutomaticData];
}

- (NSString *)getDistinctId {
    return [self.identifyId copy];
}

+ (NSString *)getSDKVersion {
    return DEPublicConfig.version;
}

- (NSString *)getDeviceId {
    return [DEDeviceInfo sharedManager].deviceId;
}

- (void)registerDynamicSuperProperties:(NSDictionary<NSString *, id> *(^)(void)) dynamicSuperProperties {
    if ([self hasDisabled])
        return;
    self.dynamicSuperProperties = dynamicSuperProperties;
}

- (void)setSuperProperties:(NSDictionary *)properties {
    if ([self hasDisabled])
        return;
    
    if (properties == nil) {
        return;
    }
    properties = [properties copy];
    
    if ([DELogging sharedInstance].loggingLevel != DELoggingLevelNone && ![self checkEventProperties:properties withEventType:nil haveAutoTrackEvents:NO]) {
        DELogError(@"%@ propertieDict error.", properties);
        return;
    }
    
    @synchronized (self.superProperty) {
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperty];
        [tmp addEntriesFromDictionary:[properties copy]];
        self.superProperty = [NSDictionary dictionaryWithDictionary:tmp];
    }
    
    dispatch_async(serialQueue, ^{
        [self.file archiveSuperProperties:self.superProperty];
    });
}

- (void)unsetSuperProperty:(NSString *)propertyKey {
    if ([self hasDisabled])
        return;
    
    if (![propertyKey isKindOfClass:[NSString class]] || propertyKey.length == 0)
        return;
    
    @synchronized (self.superProperty) {
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperty];
        tmp[propertyKey] = nil;
        self.superProperty = [NSDictionary dictionaryWithDictionary:tmp];
    }
    dispatch_async(serialQueue, ^{
        [self.file archiveSuperProperties:self.superProperty];
    });
}

- (void)clearSuperProperties {
    if ([self hasDisabled])
        return;
    
    @synchronized (self.superProperty) {
        self.superProperty = @{};
    }
    
    dispatch_async(serialQueue, ^{
        [self.file archiveSuperProperties:self.superProperty];
    });
}

- (NSDictionary *)currentSuperProperties {
    return [self.superProperty copy];
}

- (DEPresetProperties *)getPresetProperties {
    NSString *bundleId = [DEDeviceInfo bundleId];
    NSString *networkType = [self.class getNetWorkStates];
    double offset = [self getTimezoneOffset:[NSDate date] timeZone:_config.defaultTimeZone];
    
    NSMutableDictionary * autoDic = [NSMutableDictionary dictionary];
    [autoDic addEntriesFromDictionary:[DEDeviceInfo sharedManager].staticAutomaticData];
    [autoDic addEntriesFromDictionary:[DEDeviceInfo sharedManager].dynamicAutomaticData];
    
    NSMutableDictionary *presetDic = [NSMutableDictionary new];
    [presetDic setObject:bundleId?:@"" forKey:@"#bundle_id"];
    [presetDic setObject:autoDic[@"#carrier"]?:@"" forKey:@"#carrier"];
    [presetDic setObject:autoDic[@"#device_id"]?:@"" forKey:@"#device_id"];
    [presetDic setObject:autoDic[@"#device_model"]?:@"" forKey:@"#device_model"];
    [presetDic setObject:autoDic[@"#manufacturer"]?:@"" forKey:@"#manufacturer"];
    [presetDic setObject:networkType?:@"" forKey:@"#network_type"];
    [presetDic setObject:autoDic[@"#os"]?:@"" forKey:@"#os"];
    [presetDic setObject:autoDic[@"#os_version"]?:@"" forKey:@"#os_version"];
    [presetDic setObject:autoDic[@"#screen_height"]?:@(0) forKey:@"#screen_height"];
    [presetDic setObject:autoDic[@"#screen_width"]?:@(0) forKey:@"#screen_width"];
    [presetDic setObject:autoDic[@"#system_language"]?:@"" forKey:@"#system_language"];
    [presetDic setObject:@(offset)?:@(0) forKey:@"#zone_offset"];
    
    static DEPresetProperties *presetProperties = nil;
    if (presetProperties == nil) {
        presetProperties = [[DEPresetProperties alloc] initWithDictionary:presetDic];
    }
    else {
        [presetProperties updateValuesWithDictionary:presetDic];
    }
    return presetProperties;
}

- (void)identify:(NSString *)distinctId {
    if ([self hasDisabled])
        return;
        
    if (![distinctId isKindOfClass:[NSString class]] || distinctId.length == 0) {
        DELogError(@"identify cannot null");
        return;
    }
    
    @synchronized (self.identifyId) {
       self.identifyId = distinctId;
    }
    dispatch_async(serialQueue, ^{
        [self.file archiveIdentifyId:distinctId];
    });
}

- (void)login:(NSString *)accountId {
    if ([self hasDisabled])
        return;
        
    if (![accountId isKindOfClass:[NSString class]] || accountId.length == 0) {
        DELogError(@"accountId invald", accountId);
        return;
    }
    
    @synchronized (self.accountId) {
        self.accountId = accountId;
    }
        
    dispatch_async(serialQueue, ^{
        [self.file archiveAccountID:accountId];
    });
}

- (void)logout {
    if ([self hasDisabled])
        return;
    
    @synchronized (self.accountId) {
        self.accountId = nil;
    }
    dispatch_async(serialQueue, ^{
        [self.file archiveAccountID:nil];
    });
}

- (void)timeEvent:(NSString *)event {
    if ([self hasDisabled])
        return;
        
    if (![event isKindOfClass:[NSString class]] || event.length == 0 || ![self isValidName:event isAutoTrack:NO]) {
        NSString *errMsg = [NSString stringWithFormat:@"timeEvent parameter[%@] is not valid", event];
        DELogError(errMsg);
        return;
    }
    
    NSNumber *eventBegin = @([[NSDate date] timeIntervalSince1970]);
    @synchronized (self.trackTimer) {
        self.trackTimer[event] = @{DE_EVENT_START:eventBegin, DE_EVENT_DURATION:[NSNumber numberWithDouble:0]};
    };
}

- (BOOL)isValidName:(NSString *)name isAutoTrack:(BOOL)isAutoTrack {
    @try {
        if (!isAutoTrack) {
            return [self.regexKey evaluateWithObject:name];
        } else {
            return [self.regexAutoTrackKey evaluateWithObject:name];
        }
    } @catch (NSException *exception) {
        DELogError(@"%@: %@", self, exception);
        return YES;
    }
}

- (BOOL)checkEventProperties:(NSDictionary *)properties withEventType:(NSString *)eventType haveAutoTrackEvents:(BOOL)haveAutoTrackEvents {
    if (![properties isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    __block BOOL failed = NO;
    [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) {
            NSString *errMsg = [NSString stringWithFormat:@"Property name is not valid. The property KEY must be NSString. got: %@ %@", [key class], key];
            DELogError(errMsg);
            failed = YES;
        }
        
        if (![self isValidName:key isAutoTrack:haveAutoTrackEvents]) {
            NSString *errMsg = [NSString stringWithFormat:@"Property name[%@] is not valid. The property KEY must be string that starts with English letter, and contains letter, number, and '_'. The max length of the property KEY is 50.", key];
            DELogError(errMsg);
            failed = YES;
        }
        
        if (![obj isKindOfClass:[NSString class]] &&
            ![obj isKindOfClass:[NSNumber class]] &&
            ![obj isKindOfClass:[NSDate class]] &&
            ![obj isKindOfClass:[NSArray class]]) {
            NSString *errMsg = [NSString stringWithFormat:@"Property value must be type NSString, NSNumber, NSDate or NSArray. got: %@ %@. ", [obj class], obj];
            DELogError(errMsg);
            failed = YES;
        }
        
        if (eventType.length > 0 && [eventType isEqualToString:DE_EVENT_TYPE_USER_ADD]) {
            if (![obj isKindOfClass:[NSNumber class]]) {
                NSString *errMsg = [NSString stringWithFormat:@"user_add value must be NSNumber. got: %@ %@. ", [obj class], obj];
                DELogError(errMsg);
                failed = YES;
            }
        }

        if (eventType.length > 0 && [eventType isEqualToString:DE_EVENT_TYPE_USER_APPEND]) {
            if (![obj isKindOfClass:[NSArray class]]) {
                NSString *errMsg = [NSString stringWithFormat:@"user_append value must be NSArray. got: %@ %@. ", [obj class], obj];
                DELogError(errMsg);
                failed = YES;
            }
        }
        
        if ([obj isKindOfClass:[NSNumber class]]) {
            if ([obj doubleValue] > 9999999999999.999 || [obj doubleValue] < -9999999999999.999) {
                NSString *errMsg = [NSString stringWithFormat:@"The number value [%@] is invalid.", obj];
                DELogError(errMsg);
                failed = YES;
            }
        }
    }];
    if (failed) {
        return NO;
    }
    
    return YES;
}

- (void)clickFromH5:(NSString *)data {
    NSData *jsonData = [data dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *eventDict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                              options:NSJSONReadingMutableContainers
                                                                error:&err];
    NSString *appid = [eventDict[@"#app_id"] isKindOfClass:[NSString class]] ? eventDict[@"#app_id"] : self.appid;
    id dataArr = eventDict[@"data"];
    if (!err && [dataArr isKindOfClass:[NSArray class]]) {
        NSDictionary *dataInfo = [dataArr objectAtIndex:0];
        if (dataInfo != nil) {
            NSString *type = [dataInfo objectForKey:@"#type"];
            NSString *event_name = [dataInfo objectForKey:@"#event_name"];
            NSString *time = [dataInfo objectForKey:@"#time"];
            NSDictionary *properties = [dataInfo objectForKey:@"properties"];
            
            NSString *extraID;
            
            if ([type isEqualToString:DE_EVENT_TYPE_TRACK]) {
                extraID = [dataInfo objectForKey:@"#first_check_id"];
            } else {
                extraID = [dataInfo objectForKey:@"#event_id"];
            }
            
            NSMutableDictionary *dic = [properties mutableCopy];
            [dic removeObjectForKey:@"#account_id"];
            [dic removeObjectForKey:@"#distinct_id"];
            [dic removeObjectForKey:@"#device_id"];
            [dic removeObjectForKey:@"#lib"];
            [dic removeObjectForKey:@"#lib_version"];
            [dic removeObjectForKey:@"#screen_height"];
            [dic removeObjectForKey:@"#screen_width"];
            
            DataEyeSDK *instance = [DataEyeSDK sharedInstanceWithAppid:appid];
            if (instance) {
                dispatch_async(serialQueue, ^{
                    [instance h5track:event_name
                              extraID:extraID
                           properties:dic
                                 type:type
                                 time:time];
                });
            } else {
                dispatch_async(serialQueue, ^{
                    [self h5track:event_name
                          extraID:extraID
                       properties:dic
                             type:type
                             time:time];
                });
            }
        }
    }
}

- (void)tdInternalTrack:(DEEventModel *)eventData
{
    if ([self hasDisabled]){
        DELogInfo(@"tdInternalTrack, sdk is disabled, return");
        return;
    }
    
    if (_relaunchInBackGround && !_config.trackRelaunchedInBackgroundEvents) {
        return;
    }
    
    NSMutableDictionary *dataDic = [NSMutableDictionary dictionary];
    
    [self addPresetProperties:dataDic eventData:eventData];
    
    NSString *timeString;
    NSDate *nowDate = [NSDate date];
    NSTimeInterval systemUptime = [[NSProcessInfo processInfo] systemUptime];
    double offset = 0;
    if (eventData.timeValueType == DETimeValueTypeNone) {
        timeString = [_timeFormatter stringFromDate:[NSDate date]];
        offset = [self getTimezoneOffset:[NSDate date] timeZone:_config.defaultTimeZone];
    } else {
        timeString = eventData.timeString;
        offset = eventData.zoneOffset;
    }
    if (eventData.timeValueType != DETimeValueTypeTimeOnly) {
        dataDic[@"#zone_offset"] = @(offset);
    }
    dataDic[@"#time"] = timeString;
    
    NSTimeInterval timeStamp = [nowDate timeIntervalSince1970];
    NSInteger timeStampInteger = (NSInteger)timeStamp * 1000; // 将时间戳转换为整数
    dataDic[@"#timestamp"] = [NSNumber numberWithInteger:timeStampInteger];
    
    // 用户自定义属性
    NSMutableDictionary *propertiesDict = [NSMutableDictionary dictionaryWithDictionary:eventData.properties];
    
    if (propertiesDict) {
        
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_RESUME_FROM_BACKGROUND];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_CRASH_REASON];
        
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_TITLE];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_URL_PROPERTY];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_REFERRER_URL];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_SCREEN_NAME];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_ELEMENT_ID];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_ELEMENT_TYPE];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_ELEMENT_CONTENT];
        [self movePresetProperties:dataDic customProperties:propertiesDict propertyName:DE_EVENT_PROPERTY_ELEMENT_POSITION];
        
        // 移除#号，并且将key全部小写
        NSMutableDictionary * newPropertiesDict = [NSMutableDictionary dictionary];
        for(NSString * proKey in propertiesDict){
            id value = propertiesDict[proKey];
            NSString * newKey = [proKey stringByReplacingOccurrencesOfString:@"#" withString:@""];
            [newPropertiesDict setValue:value forKey:[newKey lowercaseString]];
        }
        
        dataDic[@"properties"] = [NSDictionary dictionaryWithDictionary:newPropertiesDict];
    }
    
    if ([self.config.disableEvents containsObject:eventData.eventName]) {
        DELogDebug(@"disabled data:%@", dataDic);
        return;
    }
    
    if (eventData.persist) {
        dispatch_async(serialQueue, ^{
            NSDictionary *finalDic = dataDic;
            if (eventData.timeValueType == DETimeValueTypeNone && calibratedTime && !calibratedTime.stopCalibrate) {
                finalDic = [self calibratedTime:dataDic withDate:nowDate withSystemDate:systemUptime withEventData:eventData];
            }
            NSInteger count = 0;
            if (self.config.debugMode == DataEyeDebugOnly || self.config.debugMode == DataEyeDebug) {
                DELogDebug(@"queueing debug data:%@", finalDic);
                [self flushDebugEvent:finalDic];
                @synchronized (instances) {
                    count = [self.dataQueue sqliteCountForAppid:self.appid];
                }
            } else {
                DELogDebug(@"queueing data:%@", finalDic);
//                NSError *parseError;
//                NSData  *jsonData = [NSJSONSerialization dataWithJSONObject:finalDic options:NSJSONWritingPrettyPrinted error:&parseError];
//                NSString * str = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
//                DELogDebug(@"queueing data:%@", str);
                count = [self saveEventsData:finalDic];
            }
            if (count >= [self.config.uploadSize integerValue]) {
                [self flush];
            }
        });
    } else {
        DELogDebug(@"queueing data flush immediately:%@", dataDic);
        dispatch_async(serialQueue, ^{
            [self flushImmediately:dataDic];
        });
    }
}

-(void) addPresetProperties:(NSMutableDictionary *)dataDic eventData:(DEEventModel *)eventData {
    @try {
        // event_name
        if (eventData.eventName.length > 0) {
            dataDic[@"#event_name"] = eventData.eventName;
        }
        
        // type
        if ([eventData.eventType isEqualToString:DE_EVENT_TYPE_TRACK_FIRST]) {
            /** 首次事件的eventType也是track, 但是会有#first_check_id,
             所以初始化的时候首次事件的eventType是 track_first, 用来判断是否需要extraID */
            dataDic[@"#type"] = DE_EVENT_TYPE_TRACK;
        } else {
            dataDic[@"#type"] = eventData.eventType;
        }
        
        // uuid
        dataDic[@"#uuid"] = [[NSUUID UUID] UUIDString];
        
        // distinct_id
        if (self.identifyId.length > 0) {
            dataDic[@"#distinct_id"] = self.identifyId;
        }
        
        // account_id
        if (self.accountId.length > 0) {
            dataDic[@"#account_id"] = self.accountId;
        }
            
        //增加duration
        NSDictionary *eventTimer;
        [self addDuration:dataDic eventName:eventData.eventName];
            
        dataDic[@"#app_version"] = [DEDeviceInfo sharedManager].appVersion;
        dataDic[@"#network_type"] = [[self class] getNetWorkStates];
        
        if (_relaunchInBackGround) {
            dataDic[@"#relaunched_in_background"] = @YES;
        }
        
        [dataDic addEntriesFromDictionary:[DEDeviceInfo sharedManager].dynamicAutomaticData];
        
        if (eventData.extraID.length > 0) {
            if ([eventData.eventType isEqualToString:DE_EVENT_TYPE_TRACK_FIRST]) {
                dataDic[@"#first_check_id"] = eventData.extraID;
            } else if ([eventData.eventType isEqualToString:DE_EVENT_TYPE_TRACK_UPDATE]
                       || [eventData.eventType isEqualToString:DE_EVENT_TYPE_TRACK_OVERWRITE]) {
                dataDic[@"#event_id"] = eventData.extraID;
            }
        }
    } @catch (NSException *exception) {
        
    } @finally {
        
    }
}

-(void) movePresetProperties:(NSMutableDictionary *)dataDic customProperties:(NSMutableDictionary *)customProperties propertyName:(NSString *) propertyName{
    
    @try {
        if (dataDic == nil){
            return;
        }
        
        if (customProperties == nil){
            return;
        }
        
        id value = [customProperties objectForKey:propertyName];
        if (value == nil){
            return;
        }
        
        [customProperties removeObjectForKey:propertyName];
        [dataDic setValue:value forKey:propertyName];
    } @catch (NSException *exception) {
        
    } @finally {
        
    }
}

-(void) addDuration:(NSMutableDictionary *)dataDic eventName:(NSString *) eventName{
    //增加duration
    NSDictionary *eventTimer;
    @synchronized (self.trackTimer) {
        eventTimer = self.trackTimer[eventName];
        if (eventTimer) {
            [self.trackTimer removeObjectForKey:eventName];
        }
    }

    if (eventTimer) {
        NSNumber *eventBegin = [eventTimer valueForKey:DE_EVENT_START];
        NSNumber *eventDuration = [eventTimer valueForKey:DE_EVENT_DURATION];
        
        double usedTime;
        NSNumber *currentTimeStamp = @([[NSDate date] timeIntervalSince1970]);
        if (eventDuration) {
            usedTime = [currentTimeStamp doubleValue] - [eventBegin doubleValue] + [eventDuration doubleValue];
        } else {
            usedTime = [currentTimeStamp doubleValue] - [eventBegin doubleValue];
        }
        
        if (usedTime > 0) {
            dataDic[@"#duration"] = @([[NSString stringWithFormat:@"%.3f", usedTime] floatValue]);
        }
    }
}

- (NSDictionary *)calibratedTime:(NSDictionary *)dataDic withDate:(NSDate *)date withSystemDate:(NSTimeInterval)systemUptime withEventData:(DEEventModel *)eventData {
    NSMutableDictionary *calibratedData = [NSMutableDictionary dictionaryWithDictionary:dataDic];
    NSTimeInterval outTime = systemUptime - calibratedTime.systemUptime;
    NSDate *serverDate = [NSDate dateWithTimeIntervalSince1970:(calibratedTime.serverTime + outTime)];

    if (calibratedTime.stopCalibrate) {
        return dataDic;
    }
    NSString *timeString = [_timeFormatter stringFromDate:serverDate];
    NSTimeInterval timeStamp = [serverDate timeIntervalSince1970];
    NSInteger timeStampInteger = (NSInteger)timeStamp * 1000; // 将时间戳转换为整数
    double offset = [self getTimezoneOffset:serverDate timeZone:_config.defaultTimeZone];
    
    calibratedData[@"#time"] = timeString;
    calibratedData[@"#timestamp"] = [NSNumber numberWithInteger:timeStampInteger];

    if ([eventData.eventType isEqualToString:DE_EVENT_TYPE_TRACK]
        && eventData.timeValueType != DETimeValueTypeTimeOnly) {
        calibratedData[@"#zone_offset"] = @(offset);
    }
    return calibratedData;
}

- (void)flushImmediately:(NSDictionary *)dataDic {
    [self dispatchOnNetworkQueue:^{
        [self.network flushEvents:@[dataDic]];
    }];
}

- (NSDictionary<NSString *,id> *)processParameters:(NSDictionary<NSString *,id> *)propertiesDict withType:(NSString *)eventType withEventName:(NSString *)eventName withAutoTrack:(BOOL)autotrack withH5:(BOOL)isH5 {
    
    BOOL isTrackEvent = [DataEyeSDK isTrackEvent:eventType];
    
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    if (isTrackEvent) {
        [properties addEntriesFromDictionary:self.superProperty];
        NSDictionary *dynamicSuperPropertiesDict = self.dynamicSuperProperties?[self.dynamicSuperProperties() copy]:nil;
        if (dynamicSuperPropertiesDict && [dynamicSuperPropertiesDict isKindOfClass:[NSDictionary class]]) {
            [properties addEntriesFromDictionary:dynamicSuperPropertiesDict];
        }
    }
    if (propertiesDict) {
        if ([propertiesDict isKindOfClass:[NSDictionary class]]) {
            [properties addEntriesFromDictionary:propertiesDict];
        } else {
            DELogDebug(@"The property must be NSDictionary. got: %@ %@", [propertiesDict class], propertiesDict);
        }
    }
    
    if (isTrackEvent && !isH5) {
        if (![eventName isKindOfClass:[NSString class]] || eventName.length == 0) {
            NSString *errMsg = [NSString stringWithFormat:@"Event name is invalid. Event name must be NSString. got: %@ %@", [eventName class], eventName];
            DELogError(errMsg);
        }
        
        if (![self isValidName:eventName isAutoTrack:NO]) {
            NSString *errMsg = [NSString stringWithFormat:@"Event name[ %@ ] is invalid. Event name must be string that starts with English letter, and contains letter, number, and '_'. The max length of the event name is 50.", eventName];
            DELogError(@"%@", errMsg);
        }
    }
    
    if (properties && !isH5 && [DELogging sharedInstance].loggingLevel != DELoggingLevelNone && ![self checkEventProperties:properties withEventType:eventType haveAutoTrackEvents:autotrack]) {
        NSString *errMsg = [NSString stringWithFormat:@"%@ The data contains invalid key or value.", properties];
        DELogError(errMsg);
    }
    
    if (properties) {
        NSMutableDictionary<NSString *, id> *propertiesDic = [NSMutableDictionary dictionaryWithDictionary:properties];
        for (NSString *key in [properties keyEnumerator]) {
            if ([properties[key] isKindOfClass:[NSDate class]]) {
                NSString *dateStr = [_timeFormatter stringFromDate:(NSDate *)properties[key]];
                propertiesDic[key] = dateStr;
            } else if ([properties[key] isKindOfClass:[NSArray class]]) {
                NSMutableArray *arrayItem = [properties[key] mutableCopy];
                for (int i = 0; i < arrayItem.count ; i++) {
                    if ([arrayItem[i] isKindOfClass:[NSDate class]]) {
                        NSString *dateStr = [_timeFormatter stringFromDate:(NSDate *)arrayItem[i]];
                        arrayItem[i] = dateStr;
                    }
                }
                propertiesDic[key] = arrayItem;
            }
        }
        
        return [propertiesDic copy];
    }
    
    return nil;
}

- (void)flush {
    [self syncWithCompletion:nil];
}

- (void)flushDebugEvent:(NSDictionary *)data {
    [self dispatchOnNetworkQueue:^{
        [self _syncDebug:data];
    }];
}

- (void)syncWithCompletion:(void (^)(void))handler {
    [self dispatchOnNetworkQueue:^{
        [self _sync];
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), handler);
        }
    }];
}

- (NSString*)modeEnumToString:(DataEyeDebugMode)enumVal {
    NSArray *modeEnumArray = [[NSArray alloc] initWithObjects:kModeEnumArray];
    return [modeEnumArray objectAtIndex:enumVal];
}

- (void)_syncDebug:(NSDictionary *)record {
    if (self.config.debugMode == DataEyeDebug || self.config.debugMode == DataEyeDebugOnly) {
        int debugResult = [self.network flushDebugEvents:record withAppid:self.appid];
        if (debugResult == -1) {
            // 降级处理
            if (self.config.debugMode == DataEyeDebug) {
                dispatch_async(serialQueue, ^{
                    [self saveEventsData:record];
                });
                
                self.config.debugMode = DataEyeDebugOff;
                self.network.debugMode = DataEyeDebugOff;
            } else if (self.config.debugMode == DataEyeDebugOnly) {
                DELogDebug(@"The data will be discarded due to this device is not allowed to debug:%@", record);
            }
        }
        else if (debugResult == -2) {
            DELogDebug(@"Exception occurred when sending message to Server:%@", record);
            if (self.config.debugMode == DataEyeDebug) {
                // 网络异常
                dispatch_async(serialQueue, ^{
                    [self saveEventsData:record];
                });
            }
        }
    } else {
        //防止并发事件未降级
        NSInteger count = [self saveEventsData:record];
        if (count >= [self.config.uploadSize integerValue]) {
            [self flush];
        }
    }
}

- (void)_sync {
    NSString *networkType = [[self class] getNetWorkStates];
    if (!([self convertNetworkType:networkType] & self.config.networkTypePolicy)) {
        return;
    }

    dispatch_async(serialQueue, ^{
        NSArray *recordArray;
        
        @synchronized (instances) {
            recordArray = [self.dataQueue getFirstRecords:kBatchSize withAppid:self.appid];
        }
        
        BOOL flushSucc = YES;
        while (recordArray.count > 0 && flushSucc) {
            NSUInteger sendSize = recordArray.count;
            flushSucc = [self.network flushEvents:recordArray];
            if (flushSucc) {
                @synchronized (instances) {
                    BOOL ret = [self.dataQueue removeFirstRecords:sendSize withAppid:self.appid];
                    if (!ret) {
                        break;
                    }
                    recordArray = [self.dataQueue getFirstRecords:kBatchSize withAppid:self.appid];
                }
            } else {
                break;
            }
        }
    });
}

- (void)dispatchOnNetworkQueue:(void (^)(void))dispatchBlock {
    dispatch_async(serialQueue, ^{
        dispatch_async(networkQueue, dispatchBlock);
    });
}

#pragma mark - Flush control
- (void)startFlushTimer {
    [self stopFlushTimer];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.config.uploadInterval > 0) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:[self.config.uploadInterval integerValue]
                                                          target:self
                                                        selector:@selector(flush)
                                                        userInfo:nil
                                                         repeats:YES];
        }
    });
}

- (void)stopFlushTimer {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.timer) {
            [self.timer invalidate];
            self.timer = nil;
        }
    });
}

#pragma mark - Autotracking
- (void)enableAutoTrack:(DataEyeAutoTrackEventType)eventType {
    if ([self hasDisabled]){
        DELogInfo(@"enableAutoTrack, sdk is disabled, return");
        return;
    }
    
    _config.autoTrackEventType = eventType;
    if ([DEDeviceInfo sharedManager].isFirstOpen && (_config.autoTrackEventType & DataEyeEventTypeAppInstall)) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [self autotrack:DE_APP_INSTALL_EVENT properties:nil withTime:nil];
            [self flush];
        });
    }
    
    if (_config.autoTrackEventType & DataEyeEventTypeAppEnd) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [self timeEvent:DE_APP_END_EVENT];
        });
    }

    if (_config.autoTrackEventType & DataEyeEventTypeAppStart) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSString *eventName = _relaunchInBackGround?DE_APP_START_BACKGROUND_EVENT:DE_APP_START_EVENT;
#ifdef __IPHONE_13_0
            if (@available(iOS 13.0, *)) {
                if (_isEnableSceneSupport) {
                    eventName = DE_APP_START_EVENT;
                }
            }
#endif
            [self autotrack:eventName properties:@{DE_RESUME_FROM_BACKGROUND:@(_appRelaunched)} withTime:nil];
            [self flush];
        });
    }
    
    [_autoTrackManager trackWithAppid:self.appid withOption:eventType];
    
    if (_config.autoTrackEventType & DataEyeEventTypeAppViewCrash) {
        [self trackCrash];
    }
}

- (void)ignoreViewType:(Class)aClass {
    if ([self hasDisabled])
        return;
        
    dispatch_async(serialQueue, ^{
        [self->_ignoredViewTypeList addObject:aClass];
    });
}

- (BOOL)isViewTypeIgnored:(Class)aClass {
    return [_ignoredViewTypeList containsObject:aClass];
}

- (BOOL)isViewControllerIgnored:(UIViewController *)viewController {
    if (viewController == nil) {
        return false;
    }
    NSString *screenName = NSStringFromClass([viewController class]);
    if (_ignoredViewControllers != nil && _ignoredViewControllers.count > 0) {
        if ([_ignoredViewControllers containsObject:screenName]) {
            return true;
        }
    }
    return false;
}

- (BOOL)isAutoTrackEventTypeIgnored:(DataEyeAutoTrackEventType)eventType {
    return !(_config.autoTrackEventType & eventType);
}

- (void)ignoreAutoTrackViewControllers:(NSArray *)controllers {
    if ([self hasDisabled])
        return;
        
    if (controllers == nil || controllers.count == 0) {
        return;
    }
    
    dispatch_async(serialQueue, ^{
        [self->_ignoredViewControllers addObjectsFromArray:controllers];
    });
}

#pragma mark - H5 tracking
- (BOOL)showUpWebView:(id)webView WithRequest:(NSURLRequest *)request {
    if (webView == nil || request == nil || ![request isKindOfClass:NSURLRequest.class]) {
        DELogInfo(@"showUpWebView request error");
        return NO;
    }
    
    NSString *urlStr = request.URL.absoluteString;
    if (!urlStr) {
        return NO;
    }
    
    if ([urlStr rangeOfString:DE_JS_TRACK_SCHEME].length == 0) {
        return NO;
    }
    
    NSString *query = [[request URL] query];
    NSArray *queryItem = [query componentsSeparatedByString:@"="];
    
    if (queryItem.count != 2)
        return YES;
    
    NSString *queryValue = [queryItem lastObject];
    if ([urlStr rangeOfString:DE_JS_TRACK_SCHEME].length > 0) {
        if ([self hasDisabled])
            return YES;
        
        NSString *eventData = [queryValue stringByRemovingPercentEncoding];
        if (eventData.length > 0)
            [self clickFromH5:eventData];
    }
    return YES;
}

- (void)wkWebViewGetUserAgent:(void (^)(NSString *))completion {
    self.wkWebView = [[WKWebView alloc] initWithFrame:CGRectZero];
    [self.wkWebView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id __nullable userAgent, NSError * __nullable error) {
        completion(userAgent);
    }];
}

- (void)addWebViewUserAgent {
    if ([self hasDisabled])
        return;
        
    void (^setUserAgent)(NSString *userAgent) = ^void (NSString *userAgent) {
        if ([userAgent rangeOfString:@"td-sdk-ios"].location == NSNotFound) {
            userAgent = [userAgent stringByAppendingString:@" /td-sdk-ios"];
            
            NSDictionary *userAgentDic = [[NSDictionary alloc] initWithObjectsAndKeys:userAgent, @"UserAgent", nil];
            [[NSUserDefaults standardUserDefaults] registerDefaults:userAgentDic];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    };
    
    dispatch_block_t getUABlock = ^() {
        [self wkWebViewGetUserAgent:^(NSString *userAgent) {
            setUserAgent(userAgent);
        }];
    };
    
    td_dispatch_main_sync_safe(getUABlock);
}

#pragma mark - Logging
+ (void)setLogLevel:(DELoggingLevel)level {
    [DELogging sharedInstance].loggingLevel = level;
}

#pragma mark - Crash tracking
-(void)trackCrash {
    [[DataEyeExceptionHandler sharedHandler] addDataEyeInstance:self];
}

#pragma mark - Calibrate time

+ (void)calibrateTime:(NSTimeInterval)timestamp {
    calibratedTime = [DECalibratedTime sharedInstance];
    [[DECalibratedTime sharedInstance] recalibrationWithTimeInterval:timestamp/1000.];
}

+ (void)calibrateTimeWithNtp:(NSString *)ntpServer {
    if ([ntpServer isKindOfClass:[NSString class]] && ntpServer.length > 0) {
        calibratedTime = [DECalibratedTimeWithNTP sharedInstance];
        [[DECalibratedTimeWithNTP sharedInstance] recalibrationWithNtps:@[ntpServer]];
    }
}

+ (void)calibrateTimeWithNtps:(NSArray *)ntpServers {
    NSMutableArray *serverHostArr = [NSMutableArray array];
    for (NSString *host in ntpServers) {
        if ([host isKindOfClass:[NSString class]] && host.length > 0) {
            [serverHostArr addObject:host];
        }
    }
    
    
    if(serverHostArr.count <= 0){
        return;
    }
    
    calibratedTime = [DECalibratedTimeWithNTP sharedInstance];
    [[DECalibratedTimeWithNTP sharedInstance] recalibrationWithNtps:serverHostArr];
}

// for UNITY
- (NSString *)getTimeString:(NSDate *)date {
    return [_timeFormatter stringFromDate:date];
}

@end

@implementation UIView (DataEye)

- (NSString *)dataEyeViewID {
    return objc_getAssociatedObject(self, &DE_AUTOTRACK_VIEW_ID);
}

- (void)setDataEyeViewID:(NSString *)dataEyeViewID {
    objc_setAssociatedObject(self, &DE_AUTOTRACK_VIEW_ID, dataEyeViewID, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (BOOL)dataEyeIgnoreView {
    return [objc_getAssociatedObject(self, &DE_AUTOTRACK_VIEW_IGNORE) boolValue];
}

- (void)setDataEyeIgnoreView:(BOOL)dataEyeIgnoreView {
    objc_setAssociatedObject(self, &DE_AUTOTRACK_VIEW_IGNORE, [NSNumber numberWithBool:dataEyeIgnoreView], OBJC_ASSOCIATION_ASSIGN);
}

- (NSDictionary *)dataEyeIgnoreViewWithAppid {
    return objc_getAssociatedObject(self, &DE_AUTOTRACK_VIEW_IGNORE_APPID);
}

- (void)setDataEyeIgnoreViewWithAppid:(NSDictionary *)dataEyeViewProperties {
    objc_setAssociatedObject(self, &DE_AUTOTRACK_VIEW_IGNORE_APPID, dataEyeViewProperties, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)dataEyeViewIDWithAppid {
    return objc_getAssociatedObject(self, &DE_AUTOTRACK_VIEW_ID_APPID);
}

- (void)setDataEyeViewIDWithAppid:(NSDictionary *)dataEyeViewProperties {
    objc_setAssociatedObject(self, &DE_AUTOTRACK_VIEW_ID_APPID, dataEyeViewProperties, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)dataEyeViewProperties {
    return objc_getAssociatedObject(self, &DE_AUTOTRACK_VIEW_PROPERTIES);
}

- (void)setDataEyeViewProperties:(NSDictionary *)dataEyeViewProperties {
    objc_setAssociatedObject(self, &DE_AUTOTRACK_VIEW_PROPERTIES, dataEyeViewProperties, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)dataEyeViewPropertiesWithAppid {
    return objc_getAssociatedObject(self, &DE_AUTOTRACK_VIEW_PROPERTIES_APPID);
}

- (void)setDataEyeViewPropertiesWithAppid:(NSDictionary *)dataEyeViewProperties {
    objc_setAssociatedObject(self, &DE_AUTOTRACK_VIEW_PROPERTIES_APPID, dataEyeViewProperties, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)dataEyeDelegate {
    return objc_getAssociatedObject(self, &DE_AUTOTRACK_VIEW_DELEGATE);
}

- (void)setDataEyeDelegate:(id)dataEyeDelegate {
    objc_setAssociatedObject(self, &DE_AUTOTRACK_VIEW_DELEGATE, dataEyeDelegate, OBJC_ASSOCIATION_ASSIGN);
}

@end
