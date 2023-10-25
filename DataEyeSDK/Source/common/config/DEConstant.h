//
//  DEConstant.h
//  ThinkingSDK
//
//  Created by LiHuanan on 2020/9/8.
//  Copyright © 2020 thinkingdata. All rights reserved.
//

#import <Foundation/Foundation.h>
/**
Debug 模式

- DataEyeDebugOff : 默认不开启 Debug 模式
*/
typedef NS_OPTIONS(NSInteger, DataEyeDebugMode) {
    /**
     默认不开启 Debug 模式
     */
    DataEyeDebugOff      = 0,
    
    /**
     开启 DebugOnly 模式，不入库
     */
    DataEyeDebugOnly     = 1 << 0,
    
    /**
     开启 Debug 模式，并入库
     */
    DataEyeDebug         = 1 << 1,
    
    /**
     开启 Debug 模式，并入库，等同于 DataEyeDebug
     [兼容swift] swift 调用 oc 中的枚举类型，需要遵守 [枚举类型名+枚举值] 的规则。
     */
    DataEyeDebugOn = DataEyeDebug,
};

/**
 证书验证模式
*/
typedef NS_OPTIONS(NSInteger, DESSLPinningMode) {
    /**
     默认认证方式，只会在系统的信任的证书列表中对服务端返回的证书进行验证
    */
    DESSLPinningModeNone          = 0,
    
    /**
     校验证书的公钥
    */
    DESSLPinningModePublicKey     = 1 << 0,
    
    /**
     校验证书的所有内容
    */
    DESSLPinningModeCertificate   = 1 << 1
};

/**
 自定义 HTTPS 认证
*/
typedef NSURLSessionAuthChallengeDisposition (^DEURLSessionDidReceiveAuthenticationChallengeBlock)(NSURLSession *_Nullable session, NSURLAuthenticationChallenge *_Nullable challenge, NSURLCredential *_Nullable __autoreleasing *_Nullable credential);



/**
 Log 级别

 - DELoggingLevelNone : 默认不开启
 */
typedef NS_OPTIONS(NSInteger, DELoggingLevel) {
    /**
     默认不开启
     */
    DELoggingLevelNone  = 0,
    
    /**
     Error Log
     */
    DELoggingLevelError = 1 << 0,
    
    /**
     Info  Log
     */
    DELoggingLevelInfo  = 1 << 1,
    
    /**
     Debug Log
     */
    DELoggingLevelDebug = 1 << 2,
};

/**
 上报数据网络条件

 - DENetworkTypeDefault : 默认 3G、4G、WIFI
 */
typedef NS_OPTIONS(NSInteger, DENetworkType) {
    
    /**
     默认 3G、4G、WIFI
     */
    DENetworkTypeDefault  = 0,
    
    /**
     仅WIFI
     */
    DENetworkTypeOnlyWIFI = 1 << 0,
    
    /**
     2G、3G、4G、WIFI
     */
    DENetworkTypeALL      = 1 << 1,
};

/**
 自动采集事件

 - DataEyeEventTypeNone           : 默认不开启自动埋点
 */
typedef NS_OPTIONS(NSInteger, DataEyeAutoTrackEventType) {
    
    /**
     默认不开启自动埋点
     */
    DataEyeEventTypeNone          = 0,
    
    /*
     APP 启动或从后台恢复事件
     */
    DataEyeEventTypeAppStart      = 1 << 0,
    
    /**
     APP 进入后台事件
     */
    DataEyeEventTypeAppEnd        = 1 << 1,
    
    /**
     APP 控件点击事件
     */
    DataEyeEventTypeAppClick      = 1 << 2,
    
    /**
     APP 浏览页面事件
     */
    DataEyeEventTypeAppViewScreen = 1 << 3,
    
    /**
     APP 崩溃信息
     */
    DataEyeEventTypeAppViewCrash  = 1 << 4,
    
    /**
     APP 安装之后的首次打开
     */
    DataEyeEventTypeAppInstall    = 1 << 5,
    /**
     以上全部 APP 事件
     */
    DataEyeEventTypeAll    = DataEyeEventTypeAppStart | DataEyeEventTypeAppEnd | DataEyeEventTypeAppClick | DataEyeEventTypeAppInstall | DataEyeEventTypeAppViewCrash | DataEyeEventTypeAppViewScreen

};

typedef NS_OPTIONS(NSInteger, DataEyeNetworkType) {
    DataEyeNetworkTypeNONE     = 0,
    DataEyeNetworkType2G       = 1 << 0,
    DataEyeNetworkType3G       = 1 << 1,
    DataEyeNetworkType4G       = 1 << 2,
    DataEyeNetworkTypeWIFI     = 1 << 3,
    DataEyeNetworkType5G       = 1 << 4,
    DataEyeNetworkTypeALL      = 0xFF,
};

