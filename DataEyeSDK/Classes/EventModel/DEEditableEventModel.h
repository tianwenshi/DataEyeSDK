#import "DEEventModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DEEditableEventModel : DEEventModel

- (instancetype)initWithEventName:(NSString *)eventName eventID:(NSString *)eventID;

@end

@interface DEUpdateEventModel : DEEditableEventModel

@end

@interface DEOverwriteEventModel : DEEditableEventModel

@end

NS_ASSUME_NONNULL_END
