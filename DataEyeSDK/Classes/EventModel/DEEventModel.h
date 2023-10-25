#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSInteger, TimeValueType) {
    DETimeValueTypeNone      = 0,
    DETimeValueTypeTimeOnly  = 1 << 0,
    DETimeValueTypeAll       = 1 << 1,
};

typedef NSString *kEDEventTypeName;

/**
 当eventType为 DE_EVENT_TYPE_TRACK_FIRST 时,
 track事件会添加extraID为: #first_check_id
 */
FOUNDATION_EXTERN kEDEventTypeName const DE_EVENT_TYPE_TRACK_FIRST;

/**
 当eventType为 DE_EVENT_TYPE_TRACK_UPDATE 或 DE_EVENT_TYPE_TRACK_OVERWRITE 时,
 track事件会添加extraID为: #event_id
 */
FOUNDATION_EXTERN kEDEventTypeName const DE_EVENT_TYPE_TRACK_UPDATE;
FOUNDATION_EXTERN kEDEventTypeName const DE_EVENT_TYPE_TRACK_OVERWRITE;

@interface DEEventModel : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, copy, readonly) NSString *eventName;
@property (nonatomic, copy, readonly) kEDEventTypeName eventType; // Default is DE_EVENT_TYPE_TRACK

@property (nonatomic, strong) NSDictionary *properties;

- (void)configTime:(NSDate *)time timeZone:(NSTimeZone * _Nullable)timeZone;

@end

NS_ASSUME_NONNULL_END
