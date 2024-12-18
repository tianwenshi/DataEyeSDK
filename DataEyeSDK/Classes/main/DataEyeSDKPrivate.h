#import "DataEyeSDK.h"

#import <Foundation/Foundation.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>

#import "DELogging.h"
#import "DataEyeExceptionHandler.h"
#import "DEDeviceInfo.h"
#import "DEConfig.h"
#import "DESqliteDataQueue.h"
#import "DEEventModel.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * const DE_APP_START_EVENT                  = @"app_start";
static NSString * const DE_APP_START_BACKGROUND_EVENT       = @"app_bg_start";
static NSString * const DE_APP_END_EVENT                    = @"app_end";
static NSString * const DE_APP_VIEW_EVENT                   = @"app_view";
static NSString * const DE_APP_CLICK_EVENT                  = @"app_click";
static NSString * const DE_APP_CRASH_EVENT                  = @"app_crash";
static NSString * const DE_APP_INSTALL_EVENT                = @"app_install";

static NSString * const DE_CRASH_REASON                     = @"#app_crashed_reason";
static NSString * const DE_RESUME_FROM_BACKGROUND           = @"#resume_from_background";

static kEDEventTypeName const DE_EVENT_TYPE_TRACK           = @"track";

static kEDEventTypeName const DE_EVENT_TYPE_USER_DEL        = @"user_del";
static kEDEventTypeName const DE_EVENT_TYPE_USER_ADD        = @"user_add";
static kEDEventTypeName const DE_EVENT_TYPE_USER_SET        = @"user_set";
static kEDEventTypeName const DE_EVENT_TYPE_USER_SETONCE    = @"user_setOnce";
static kEDEventTypeName const DE_EVENT_TYPE_USER_UNSET      = @"user_unset";
static kEDEventTypeName const DE_EVENT_TYPE_USER_APPEND     = @"user_append";

static NSString * const DE_EVENT_START                      = @"eventStart";
static NSString * const DE_EVENT_DURATION                   = @"eventDuration";

static NSString * const DE_NTP_SERVER_1                   = @"pool.ntp.org";
static NSString * const DE_NTP_SERVER_2                   = @"time.google.com";
static NSString * const DE_NTP_SERVER_3                   = @"time.cloudflare.com";
static NSString * const DE_NTP_SERVER_CN                   = @"ntp.ntsc.ac.cn";

static char DE_AUTOTRACK_VIEW_ID;
static char DE_AUTOTRACK_VIEW_ID_APPID;
static char DE_AUTOTRACK_VIEW_IGNORE;
static char DE_AUTOTRACK_VIEW_IGNORE_APPID;
static char DE_AUTOTRACK_VIEW_PROPERTIES;
static char DE_AUTOTRACK_VIEW_PROPERTIES_APPID;
static char DE_AUTOTRACK_VIEW_DELEGATE;

#ifndef td_dispatch_main_sync_safe
#define td_dispatch_main_sync_safe(block)\
if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(dispatch_get_main_queue())) {\
block();\
} else {\
dispatch_sync(dispatch_get_main_queue(), block);\
}
#endif

#define kDefaultTimeFormat  @"yyyy-MM-dd HH:mm:ss.SSS"

static NSUInteger const kBatchSize = 50;
static NSUInteger const DE_PROPERTY_CRASH_LENGTH_LIMIT = 8191*2;
static NSString * const DE_JS_TRACK_SCHEME = @"thinkinganalytics://trackEvent";

#define kModeEnumArray @"NORMAL", @"DebugOnly", @"Debug", nil

@interface DataEyeSDK ()

@property (atomic, copy) NSString *appid;
@property (atomic, copy) NSString *reportURL;
@property (atomic, copy, nullable) NSString *accountId;
@property (atomic, copy) NSString *identifyId;
@property (atomic, strong) NSDictionary *superProperty;
@property (atomic, strong) NSMutableSet *ignoredViewTypeList;
@property (atomic, strong) NSMutableSet *ignoredViewControllers;
@property (nonatomic, assign) BOOL relaunchInBackGround;
@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, assign) BOOL isOptOut;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, strong) NSPredicate *regexKey;
@property (nonatomic, strong) NSPredicate *regexAutoTrackKey;
@property (nonatomic, strong) NSMutableDictionary *trackTimer;
@property (nonatomic, assign) UIBackgroundTaskIdentifier taskId;
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, strong) CTTelephonyNetworkInfo *telephonyInfo;
@property (nonatomic, copy) NSDictionary<NSString *, id> *(^dynamicSuperProperties)(void);

@property (atomic, strong) DESqliteDataQueue *dataQueue;
@property (nonatomic, copy) DEConfig *config;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@property (nonatomic, assign) BOOL applicationWillResignActive;
@property (nonatomic, assign) BOOL appRelaunched;
@property (nonatomic, assign) BOOL isEnableSceneSupport;
@property (nonatomic, strong) WKWebView *wkWebView;

- (instancetype)initLight:(NSString *)appid withServerURL:(NSString *)serverURL withConfig:(DEConfig *)config;
- (void)autotrack:(NSString *)event properties:(NSDictionary *_Nullable)propertieDict withTime:(NSDate *_Nullable)date;
- (BOOL)isViewControllerIgnored:(UIViewController *)viewController;
- (BOOL)isAutoTrackEventTypeIgnored:(DataEyeAutoTrackEventType)eventType;
- (BOOL)isViewTypeIgnored:(Class)aClass;
- (void)retrievePersistedData;
+ (dispatch_queue_t)serialQueue;
+ (dispatch_queue_t)networkQueue;
+ (UIApplication *)sharedUIApplication;
- (NSInteger)saveEventsData:(NSDictionary *)data;
- (void)flushImmediately:(NSDictionary *)dataDic;
- (BOOL)hasDisabled;
- (BOOL)isValidName:(NSString *)name isAutoTrack:(BOOL)isAutoTrack;
+ (BOOL)isTrackEvent:(NSString *)eventType;
- (BOOL)checkEventProperties:(NSDictionary *)properties withEventType:(NSString *_Nullable)eventType haveAutoTrackEvents:(BOOL)haveAutoTrackEvents;
- (void)startFlushTimer;
- (double)getTimezoneOffset:(NSDate *)date timeZone:(NSTimeZone *)timeZone;

@end

@interface DEEventModel ()

@property (nonatomic, copy) NSString *timeString;
@property (nonatomic, assign) double zoneOffset;
@property (nonatomic, assign) TimeValueType timeValueType;
@property (nonatomic, copy) NSString *extraID;
@property (nonatomic, assign) BOOL persist;

- (instancetype)initWithEventName:(NSString * _Nullable)eventName;

- (instancetype _Nonnull )initWithEventName:(NSString * _Nullable)eventName eventType:(kEDEventTypeName _Nonnull )eventType;

@end

@interface LightDataEyeSDK : DataEyeSDK

- (instancetype)initWithAPPID:(NSString *)appID withServerURL:(NSString *)serverURL withConfig:(DEConfig *)config;

@end

NS_ASSUME_NONNULL_END
