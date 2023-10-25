#import "DEEditableEventModel.h"
#import "DataEyeSDKPrivate.h"

@interface DEEditableEventModel ()

@property (nonatomic, copy) NSString *eventName;
@property (nonatomic, copy) kEDEventTypeName eventType;

@end

@implementation DEEditableEventModel
@synthesize eventName = _eventName;
@synthesize eventType = _eventType;

- (instancetype)initWithEventName:(NSString *)eventName eventID:(NSString *)eventID {
    NSAssert(nil, @"Init with subClass: DEUpdateEventModel or DEOverwriteEventModel!");
    return nil;
}

@end

@implementation DEUpdateEventModel

- (instancetype)initWithEventName:(NSString *)eventName
                          eventID:(NSString *)eventID {
    if (self = [self initWithEventName:eventName eventType:DE_EVENT_TYPE_TRACK_UPDATE]) {
        self.extraID = eventID;
    }
    return self;
}

@end

@implementation DEOverwriteEventModel

- (instancetype)initWithEventName:(NSString *)eventName
                          eventID:(NSString *)eventID {
    if (self = [self initWithEventName:eventName eventType:DE_EVENT_TYPE_TRACK_OVERWRITE]) {
        self.extraID = eventID;
    }
    return self;
}

@end
