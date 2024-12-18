//
//  DEMarco.h
//  DateEyeSDK
//
//  Created by xuge on 2024/9/19.
//  Copyright © 2024 thinkingdata. All rights reserved.
//

#ifndef DEMarco_h
#define DEMarco_h

// nsstring is not nil and length > 0
#define DE_NSSTRING_NOT_NULL(str)\
([(str) isKindOfClass:[NSString class]] && ![(str) isEqualToString:@""])

#endif /* DEMarco_h */
