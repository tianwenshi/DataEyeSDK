#import "DEEventModel.h"
NS_ASSUME_NONNULL_BEGIN

@interface DEFirstEventModel : DEEventModel

- (instancetype)initWithEventName:(NSString * _Nullable)eventName;

- (instancetype)initWithEventName:(NSString * _Nullable)eventName firstCheckID:(NSString *)firstCheckID;

@end

NS_ASSUME_NONNULL_END
