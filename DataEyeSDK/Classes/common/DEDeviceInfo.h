#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *const VERSION;

@interface DEDeviceInfo : NSObject

+ (DEDeviceInfo *)sharedManager;

@property (nonatomic, copy) NSString *uniqueId;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *appVersion;
@property (nonatomic, strong) NSDictionary *automaticData;
@property (nonatomic, readonly) BOOL isFirstOpen;

@property (nonatomic, copy) NSString *libName;
@property (nonatomic, copy) NSString *libVersion;
- (void)updateAutomaticData;

+ (NSString *)libVersion;
- (NSDictionary *)collectAutomaticProperties;
+ (NSString*)bundleId;

@end

NS_ASSUME_NONNULL_END
