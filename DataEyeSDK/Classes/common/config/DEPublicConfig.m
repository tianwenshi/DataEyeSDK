//
//  TDPublicConfig.m
//  DataEyeSDK
//
//  Created by LiHuanan on 2020/9/8.
//  Copyright © 2020 dataeye. All rights reserved.
//

#import "DEPublicConfig.h"
static DEPublicConfig* config;

@implementation DEPublicConfig
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [DEPublicConfig new];
    });
}
- (instancetype)init
{
    self = [super init];
    if(self)
    {
        self.controllers = @[
        @"UICompatibilityInputViewController",
        @"UIKeyboardCandidateGridCollectionViewController",
        @"UIInputWindowController",
        @"UIApplicationRotationFollowingController",
        @"UIApplicationRotationFollowingControllerNoTouches",
        @"UISystemKeyboardDockController",
        @"UINavigationController",
        @"SFBrowserRemoteViewController",
        @"SFSafariViewController",
        @"UIAlertController",
        @"UIImagePickerController",
        @"PUPhotoPickerHostViewController",
        @"UIViewController",
        @"UITableViewController",
        @"UITabBarController",
        @"_UIRemoteInputViewController",
        @"UIEditingOverlayViewController",
        @"_UIAlertControllerTextFieldViewController",
        @"UIActivityGroupViewController",
        @"_UISFAirDropInstructionsViewController",
        @"_UIActivityGroupListViewController",
        @"_UIShareExtensionRemoteViewController",
        @"SLRemoteComposeViewController",
        @"SLComposeViewController",
        ];
    }
    return self;
}
+ (NSArray*)controllers
{
    return config.controllers;
}
+ (NSString*)version
{
    return @"2.8.0";
}
@end
