#import "DEFirstEventModel.h"
#import "DataEyeSDKPrivate.h"

@implementation DEFirstEventModel

- (instancetype)initWithEventName:(NSString *)eventName {
    return [self initWithEventName:eventName eventType:DE_EVENT_TYPE_TRACK_FIRST];
}

- (instancetype)initWithEventName:(NSString *)eventName firstCheckID:(NSString *)firstCheckID {
    if (self = [self initWithEventName:eventName eventType:DE_EVENT_TYPE_TRACK_FIRST]) {
        self.extraID = firstCheckID;
    }
    return self;
}

@end
