//
//  TDPublicConfig.h
//  DataEyeSDK
//
//  Created by LiHuanan on 2020/9/8.
//  Copyright © 2020 dataeye. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DEPublicConfig : NSObject
/**
 自动采集默认需要过滤的控制器列表
 */
@property(copy,nonatomic) NSArray* controllers;
/**
 SDK版本号配置
 */
@property(copy,nonatomic) NSString* version;
+ (NSArray*)controllers;
+ (NSString*)version;

@end

NS_ASSUME_NONNULL_END
