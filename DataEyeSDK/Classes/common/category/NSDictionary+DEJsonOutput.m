//
//  NSDictionary+TDJsonOutput.m
//  DataEyeSDK
//
//  Created by huangdiao on 2021/3/18.
//  Copyright © 2021 dataeye. All rights reserved.
//

#import "NSDictionary+DEJsonOutput.h"

@implementation NSDictionary (DEJsonOutput)

- (NSString *)descriptionWithLocale:(nullable id)locale {
    if ([NSJSONSerialization isValidJSONObject:self]) {
        NSString *output = nil;
        @try {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self options:NSJSONWritingPrettyPrinted error:nil];
            output = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            output = [output stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        }
        @catch (NSException *exception) {
            output = self.description;
        }
        return  output;
    } else {
        return self.description;
    }
}

@end
