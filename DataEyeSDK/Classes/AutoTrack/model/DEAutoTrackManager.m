#import "DEAutoTrackManager.h"

#import "DESwizzler.h"
#import "UIViewController+AutoTrack.h"
#import "NSObject+DESwizzle.h"
#import "DEJSONUtil.h"
#import "UIApplication+AutoTrack.h"
#import "DataEyeSDKPrivate.h"
#import "DEPublicConfig.h"

#ifndef DE_LOCK
#define DE_LOCK(lock) dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
#endif

#ifndef DE_UNLOCK
#define DE_UNLOCK(lock) dispatch_semaphore_signal(lock);
#endif

NSString * const DE_EVENT_PROPERTY_TITLE = @"#title";
NSString * const DE_EVENT_PROPERTY_URL_PROPERTY = @"#url";
NSString * const DE_EVENT_PROPERTY_REFERRER_URL = @"#referrer";
NSString * const DE_EVENT_PROPERTY_SCREEN_NAME = @"#screen_name";
NSString * const DE_EVENT_PROPERTY_ELEMENT_ID = @"#element_id";
NSString * const DE_EVENT_PROPERTY_ELEMENT_TYPE = @"#element_type";
NSString * const DE_EVENT_PROPERTY_ELEMENT_CONTENT = @"#element_content";
NSString * const DE_EVENT_PROPERTY_ELEMENT_POSITION = @"#element_position";

@interface DEAutoTrackManager ()

@property (atomic, strong) NSMutableDictionary<NSString *, id> *autoTrackOptions;
@property (nonatomic, strong, nonnull) dispatch_semaphore_t trackOptionLock;
@property (atomic, copy) NSString *referrerViewControllerUrl;

@end


@implementation DEAutoTrackManager

#pragma mark - Public

+ (instancetype)sharedManager {
    static dispatch_once_t once;
    static DEAutoTrackManager *instance = nil;
    dispatch_once(&once, ^{
        instance = [[[DEAutoTrackManager class] alloc] init];
        instance.autoTrackOptions = [NSMutableDictionary new];
        instance.trackOptionLock = dispatch_semaphore_create(1);
    });
    return instance;
}

- (void)trackEventView:(UIView *)view {
    [self trackEventView:view withIndexPath:nil];
}

- (void)trackEventView:(UIView *)view withIndexPath:(NSIndexPath *)indexPath {
    if (view.dataEyeIgnoreView) {
        return;
    }
    
    NSMutableDictionary *properties = [[NSMutableDictionary alloc] init];
    properties[DE_EVENT_PROPERTY_ELEMENT_ID] = view.dataEyeViewID;
    properties[DE_EVENT_PROPERTY_ELEMENT_TYPE] = NSStringFromClass([view class]);
    UIViewController *viewController = [self viewControllerForView:view];
    if (viewController != nil) {
        NSString *screenName = NSStringFromClass([viewController class]);
        properties[DE_EVENT_PROPERTY_SCREEN_NAME] = screenName;
        
        NSString *controllerTitle = [self titleFromViewController:viewController];
        if (controllerTitle) {
            properties[DE_EVENT_PROPERTY_TITLE] = controllerTitle;
        }
    }
    
    NSDictionary *propDict = view.dataEyeViewProperties;
    if ([propDict isKindOfClass:[NSDictionary class]]) {
        [properties addEntriesFromDictionary:propDict];
    }
    
    UIView *contentView;
    NSDictionary *propertyWithAppid;
    if (indexPath) {
        if ([view isKindOfClass:[UITableView class]]) {
            UITableView *tableView = (UITableView *)view;
            contentView = [tableView cellForRowAtIndexPath:indexPath];
            if (!contentView) {
                [tableView layoutIfNeeded];
                contentView = [tableView cellForRowAtIndexPath:indexPath];
            }
            properties[DE_EVENT_PROPERTY_ELEMENT_POSITION] = [NSString stringWithFormat: @"%ld:%ld", (unsigned long)indexPath.section, (unsigned long)indexPath.row];
            
            if ([tableView.dataEyeDelegate conformsToProtocol:@protocol(DEUIViewAutoTrackDelegate)]) {
                if ([tableView.dataEyeDelegate respondsToSelector:@selector(dataEye_tableView:autoTrackPropertiesAtIndexPath:)]) {
                    NSDictionary *dic = [view.dataEyeDelegate dataEye_tableView:tableView autoTrackPropertiesAtIndexPath:indexPath];
                    if ([dic isKindOfClass:[NSDictionary class]]) {
                        [properties addEntriesFromDictionary:dic];
                    }
                }
                
                if ([tableView.dataEyeDelegate respondsToSelector:@selector(dataEyeWithAppid_tableView:autoTrackPropertiesAtIndexPath:)]) {
                    propertyWithAppid = [view.dataEyeDelegate dataEyeWithAppid_tableView:tableView autoTrackPropertiesAtIndexPath:indexPath];
                }
            }
        } else if ([view isKindOfClass:[UICollectionView class]]) {
            UICollectionView *collectionView = (UICollectionView *)view;
            contentView = [collectionView cellForItemAtIndexPath:indexPath];
            if (!contentView) {
                [collectionView layoutIfNeeded];
                contentView = [collectionView cellForItemAtIndexPath:indexPath];
            }
            properties[DE_EVENT_PROPERTY_ELEMENT_POSITION] = [NSString stringWithFormat: @"%ld:%ld", (unsigned long)indexPath.section, (unsigned long)indexPath.row];
            
            if ([collectionView.dataEyeDelegate conformsToProtocol:@protocol(DEUIViewAutoTrackDelegate)]) {
                if ([collectionView.dataEyeDelegate respondsToSelector:@selector(dataEye_collectionView:autoTrackPropertiesAtIndexPath:)]) {
                    NSDictionary *dic = [view.dataEyeDelegate dataEye_collectionView:collectionView autoTrackPropertiesAtIndexPath:indexPath];
                    if ([dic isKindOfClass:[NSDictionary class]]) {
                        [properties addEntriesFromDictionary:dic];
                    }
                }
                if ([collectionView.dataEyeDelegate respondsToSelector:@selector(dataEyeWithAppid_collectionView:autoTrackPropertiesAtIndexPath:)]) {
                    propertyWithAppid = [view.dataEyeDelegate dataEyeWithAppid_collectionView:collectionView autoTrackPropertiesAtIndexPath:indexPath];
                }
            }
        }
    } else {
        contentView = view;
        properties[DE_EVENT_PROPERTY_ELEMENT_POSITION] = [DEAutoTrackManager getPosition:contentView];
    }
    
    NSString *content = [DEAutoTrackManager getText:contentView];
    if (content.length > 0)
        properties[DE_EVENT_PROPERTY_ELEMENT_CONTENT] = content;
    
    NSDate *trackDate = [NSDate date];
    for (NSString *appid in self.autoTrackOptions) {
        DataEyeAutoTrackEventType type = (DataEyeAutoTrackEventType)[self.autoTrackOptions[appid] integerValue];
        
        if (type & DataEyeEventTypeAppClick) {
            DataEyeSDK *instance = [DataEyeSDK sharedInstanceWithAppid:appid];
            NSMutableDictionary *trackProperties = [properties mutableCopy];
            if ([instance isViewTypeIgnored:[view class]]) {
                continue;
            }
            NSDictionary *ignoreViews = view.dataEyeIgnoreViewWithAppid;
            if (ignoreViews != nil && [[ignoreViews objectForKey:appid] isKindOfClass:[NSNumber class]]) {
                BOOL ignore = [[ignoreViews objectForKey:appid] boolValue];
                if (ignore)
                    continue;
            }
            
            if ([instance isViewControllerIgnored:viewController]) {
                continue;
            }
            
            NSDictionary *viewIDs = view.dataEyeViewIDWithAppid;
            if (viewIDs != nil && [viewIDs objectForKey:appid]) {
                trackProperties[DE_EVENT_PROPERTY_ELEMENT_ID] = [viewIDs objectForKey:appid];
            }
            
            NSDictionary *viewProperties = view.dataEyeViewPropertiesWithAppid;
            if (viewProperties != nil && [viewProperties objectForKey:appid]) {
                NSDictionary *properties = [viewProperties objectForKey:appid];
                if ([properties isKindOfClass:[NSDictionary class]]) {
                    [trackProperties addEntriesFromDictionary:properties];
                }
            }
            
            if (propertyWithAppid) {
                NSDictionary *autoTrackproperties = [propertyWithAppid objectForKey:appid];
                if ([autoTrackproperties isKindOfClass:[NSDictionary class]]) {
                    [trackProperties addEntriesFromDictionary:autoTrackproperties];
                }
            }
            
            [instance autotrack:DE_APP_CLICK_EVENT properties:trackProperties withTime:trackDate];
        }
    }
}

- (void)trackWithAppid:(NSString *)appid withOption:(DataEyeAutoTrackEventType)type {
    DE_LOCK(self.trackOptionLock);
    self.autoTrackOptions[appid] = @(type);
    DE_UNLOCK(self.trackOptionLock);
    
    if (type & DataEyeEventTypeAppClick || type & DataEyeEventTypeAppViewScreen) {
        [self swizzleVC];
    }
}

- (void)viewControlWillAppear:(UIViewController *)controller {
    [self trackViewController:controller];
}

+ (UIViewController *)topPresentedViewController {
    UIWindow *keyWindow = [self findWindow];
    if (keyWindow != nil && !keyWindow.isKeyWindow) {
        [keyWindow makeKeyWindow];
    }
    
    UIViewController *topController = keyWindow.rootViewController;
    if ([topController isKindOfClass:[UINavigationController class]]) {
        topController = [(UINavigationController *)topController topViewController];
    }
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

#pragma mark - Private

- (BOOL)isAutoTrackEventType:(DataEyeAutoTrackEventType)eventType {
    BOOL isIgnored = YES;
    for (NSString *appid in self.autoTrackOptions) {
        DataEyeAutoTrackEventType type = (DataEyeAutoTrackEventType)[self.autoTrackOptions[appid] integerValue];
        isIgnored = !(type & eventType);
        if (isIgnored == NO)
            break;
    }
    return !isIgnored;
}

- (UIViewController *)viewControllerForView:(UIView *)view {
    UIResponder *responder = view.nextResponder;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            if ([responder isKindOfClass:[UINavigationController class]]) {
                responder = [(UINavigationController *)responder topViewController];
                continue;
            } else if ([responder isKindOfClass:UITabBarController.class]) {
                responder = [(UITabBarController *)responder selectedViewController];
                continue;
            }
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (void)trackViewController:(UIViewController *)controller {
    if (![self shouldTrackViewContrller:[controller class]]) {
        return;
    }
    
    NSMutableDictionary *properties = [[NSMutableDictionary alloc] init];
    [properties setValue:NSStringFromClass([controller class]) forKey:DE_EVENT_PROPERTY_SCREEN_NAME];
    
    NSString *controllerTitle = [self titleFromViewController:controller];
    if (controllerTitle) {
        [properties setValue:controllerTitle forKey:DE_EVENT_PROPERTY_TITLE];
    }
    
    NSDictionary *autoTrackerAppidDic;
    if ([controller conformsToProtocol:@protocol(DEAutoTracker)]) {
        UIViewController<DEAutoTracker> *autoTrackerController = (UIViewController<DEAutoTracker> *)controller;
        NSDictionary *autoTrackerDic;
        if ([controller respondsToSelector:@selector(getTrackPropertiesWithAppid)])
            autoTrackerAppidDic = [autoTrackerController getTrackPropertiesWithAppid];
        if ([controller respondsToSelector:@selector(getTrackProperties)])
            autoTrackerDic = [autoTrackerController getTrackProperties];
        
        if ([autoTrackerDic isKindOfClass:[NSDictionary class]]) {
            [properties addEntriesFromDictionary:autoTrackerDic];
        }
    }
    
    NSDictionary *screenAutoTrackerAppidDic;
    if ([controller conformsToProtocol:@protocol(DEScreenAutoTracker)]) {
        UIViewController<DEScreenAutoTracker> *screenAutoTrackerController = (UIViewController<DEScreenAutoTracker> *)controller;
        if ([screenAutoTrackerController respondsToSelector:@selector(getScreenUrlWithAppid)])
            screenAutoTrackerAppidDic = [screenAutoTrackerController getScreenUrlWithAppid];
        if ([screenAutoTrackerController respondsToSelector:@selector(getScreenUrl)]) {
            NSString *currentUrl = [screenAutoTrackerController getScreenUrl];
            [properties setValue:currentUrl forKey:DE_EVENT_PROPERTY_URL_PROPERTY];
            [properties setValue:_referrerViewControllerUrl forKey:DE_EVENT_PROPERTY_REFERRER_URL];
            _referrerViewControllerUrl = currentUrl;
        }
    }
    
    NSDate *trackDate = [NSDate date];
    for (NSString *appid in self.autoTrackOptions) {
        DataEyeAutoTrackEventType type = [self.autoTrackOptions[appid] integerValue];
        if (type & DataEyeEventTypeAppViewScreen) {
            DataEyeSDK *instance = [DataEyeSDK sharedInstanceWithAppid:appid];
            NSMutableDictionary *trackProperties = [properties mutableCopy];
            
            if ([instance isViewControllerIgnored:controller]
                || [instance isViewTypeIgnored:[controller class]]) {
                continue;
            }
            
            if (autoTrackerAppidDic && [autoTrackerAppidDic objectForKey:appid]) {
                NSDictionary *dic = [autoTrackerAppidDic objectForKey:appid];
                if ([dic isKindOfClass:[NSDictionary class]]) {
                    [trackProperties addEntriesFromDictionary:dic];
                }
            }
            
            if (screenAutoTrackerAppidDic && [screenAutoTrackerAppidDic objectForKey:appid]) {
                NSString *screenUrl = [screenAutoTrackerAppidDic objectForKey:appid];
                [trackProperties setValue:screenUrl forKey:DE_EVENT_PROPERTY_URL_PROPERTY];
            }
            
            [instance autotrack:DE_APP_VIEW_EVENT properties:trackProperties withTime:trackDate];
        }
    }
}

- (BOOL)shouldTrackViewContrller:(Class)aClass {
    return ![DEPublicConfig.controllers containsObject:NSStringFromClass(aClass)];
}

- (DataEyeAutoTrackEventType)autoTrackOptionForAppid:(NSString *)appid {
    return (DataEyeAutoTrackEventType)[[self.autoTrackOptions objectForKey:appid] integerValue];
}

- (void)swizzleSelected:(UIView *)view delegate:(id)delegate {
    if ([view isKindOfClass:[UITableView class]]
        && [delegate conformsToProtocol:@protocol(UITableViewDelegate)]) {
        void (^block)(id, SEL, id, id) = ^(id target, SEL command, UITableView *tableView, NSIndexPath *indexPath) {
            [self trackEventView:tableView withIndexPath:indexPath];
        };
        
        [DESwizzler swizzleSelector:@selector(tableView:didSelectRowAtIndexPath:)
                            onClass:[delegate class]
                          withBlock:block
                              named:@"td_table_select"];
    }
    
    if ([view isKindOfClass:[UICollectionView class]]
        && [delegate conformsToProtocol:@protocol(UICollectionViewDelegate)]) {
        
        void (^block)(id, SEL, id, id) = ^(id target, SEL command, UICollectionView *collectionView, NSIndexPath *indexPath) {
            [self trackEventView:collectionView withIndexPath:indexPath];
        };
        [DESwizzler swizzleSelector:@selector(collectionView:didSelectItemAtIndexPath:)
                            onClass:[delegate class]
                          withBlock:block
                              named:@"td_collection_select"];
    }
}

- (void)swizzleVC {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void (^tableViewBlock)(UITableView *tableView,
                               SEL cmd,
                               id<UITableViewDelegate> delegate) =
        ^(UITableView *tableView, SEL cmd, id<UITableViewDelegate> delegate) {
            if (!delegate) {
                return;
            }
            
            [self swizzleSelected:tableView delegate:delegate];
        };
        
        [DESwizzler swizzleSelector:@selector(setDelegate:)
                            onClass:[UITableView class]
                          withBlock:tableViewBlock
                              named:@"td_table_delegate"];
        
        void (^collectionViewBlock)(UICollectionView *, SEL, id<UICollectionViewDelegate>) = ^(UICollectionView *collectionView, SEL cmd, id<UICollectionViewDelegate> delegate) {
            if (nil == delegate) {
                return;
            }
            
            [self swizzleSelected:collectionView delegate:delegate];
        };
        [DESwizzler swizzleSelector:@selector(setDelegate:)
                            onClass:[UICollectionView class]
                          withBlock:collectionViewBlock
                              named:@"td_collection_delegate"];
        
        
        
        
        [UIViewController td_swizzleMethod:@selector(viewWillAppear:)
                                withMethod:@selector(de_autotrack_viewWillAppear:)
                                     error:NULL];
        
        [UIApplication td_swizzleMethod:@selector(sendAction:to:from:forEvent:)
                             withMethod:@selector(de_sendAction:to:from:forEvent:)
                                  error:NULL];
    });
}

+ (NSString *)getPosition:(UIView *)view {
    NSString *position = nil;
    if ([view isKindOfClass:[UIView class]] && view.dataEyeIgnoreView) {
        return nil;
    }
    
    if ([view isKindOfClass:[UITabBar class]]) {
        UITabBar *tabbar = (UITabBar *)view;
        position = [NSString stringWithFormat: @"%ld", (long)[tabbar.items indexOfObject:tabbar.selectedItem]];
    } else if ([view isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *segment = (UISegmentedControl *)view;
        position = [NSString stringWithFormat:@"%ld", (long)segment.selectedSegmentIndex];
    } else if ([view isKindOfClass:[UIProgressView class]]) {
        UIProgressView *progress = (UIProgressView *)view;
        position = [NSString stringWithFormat:@"%f", progress.progress];
    } else if ([view isKindOfClass:[UIPageControl class]]) {
        UIPageControl *pageControl = (UIPageControl *)view;
        position = [NSString stringWithFormat:@"%ld", (long)pageControl.currentPage];
    }
    
    return position;
}

+ (NSString *)getText:(NSObject *)obj {
    NSString *text = nil;
    if ([obj isKindOfClass:[UIView class]] && [(UIView *)obj dataEyeIgnoreView]) {
        return nil;
    }
    
    if ([obj isKindOfClass:[UIButton class]]) {
        text = ((UIButton *)obj).currentTitle;
    } else if ([obj isKindOfClass:[UITextView class]] ||
               [obj isKindOfClass:[UITextField class]]) {
        //ignore
    } else if ([obj isKindOfClass:[UILabel class]]) {
        text = ((UILabel *)obj).text;
    } else if ([obj isKindOfClass:[UIPickerView class]]) {
        UIPickerView *picker = (UIPickerView *)obj;
        NSInteger sections = picker.numberOfComponents;
        NSMutableArray *titles = [NSMutableArray array];
        
        for(NSInteger i = 0; i < sections; i++) {
            NSInteger row = [picker selectedRowInComponent:i];
            NSString *title;
            if ([picker.delegate
                 respondsToSelector:@selector(pickerView:titleForRow:forComponent:)]) {
                title = [picker.delegate pickerView:picker titleForRow:row forComponent:i];
            } else if ([picker.delegate
                        respondsToSelector:@selector(pickerView:attributedTitleForRow:forComponent:)]) {
                title = [picker.delegate
                         pickerView:picker
                         attributedTitleForRow:row forComponent:i].string;
            }
            [titles addObject:title ?: @""];
        }
        if (titles.count > 0) {
            text = [titles componentsJoinedByString:@","];
        }
    } else if ([obj isKindOfClass:[UIDatePicker class]]) {
        UIDatePicker *picker = (UIDatePicker *)obj;
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = kDefaultTimeFormat;
        text = [formatter stringFromDate:picker.date];
    } else if ([obj isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *segment = (UISegmentedControl *)obj;
        text =  [NSString stringWithFormat:@"%@", [segment titleForSegmentAtIndex:segment.selectedSegmentIndex]];
    } else if ([obj isKindOfClass:[UISwitch class]]) {
        UISwitch *switchItem = (UISwitch *)obj;
        text = switchItem.on ? @"on" : @"off";
    } else if ([obj isKindOfClass:[UISlider class]]) {
        UISlider *slider = (UISlider *)obj;
        text = [NSString stringWithFormat:@"%f", [slider value]];
    } else if ([obj isKindOfClass:[UIStepper class]]) {
        UIStepper *step = (UIStepper *)obj;
        text = [NSString stringWithFormat:@"%f", [step value]];
    } else {
        if ([obj isKindOfClass:[UIView class]]) {
            for(UIView *subView in [(UIView *)obj subviews]) {
                text = [DEAutoTrackManager getText:subView];
                if ([text isKindOfClass:[NSString class]] && text.length > 0) {
                    break;
                }
            }
        }
    }
    return text;
}

- (NSString *)titleFromViewController:(UIViewController *)viewController {
    if (!viewController) {
        return nil;
    }
    
    UIView *titleView = viewController.navigationItem.titleView;
    NSString *elementContent = nil;
    if (titleView) {
        elementContent = [DEAutoTrackManager getText:titleView];
    }
    
    return elementContent.length > 0 ? elementContent : viewController.navigationItem.title;
}

+ (UIWindow *)findWindow {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (window == nil || window.windowLevel != UIWindowLevelNormal) {
        for (window in [UIApplication sharedApplication].windows) {
            if (window.windowLevel == UIWindowLevelNormal) {
                break;
            }
        }
    }
    
#ifdef __IPHONE_13_0
    if (@available(iOS 13.0, tvOS 13, *)) {
        NSSet *scenes = [[UIApplication sharedApplication] valueForKey:@"connectedScenes"];
        for (id scene in scenes) {
            if (window) {
                break;
            }
            
            id activationState = [scene valueForKeyPath:@"activationState"];
            BOOL isActive = activationState != nil && [activationState integerValue] == 0;
            if (isActive) {
                Class WindowScene = NSClassFromString(@"UIWindowScene");
                if ([scene isKindOfClass:WindowScene]) {
                    NSArray<UIWindow *> *windows = [scene valueForKeyPath:@"windows"];
                    for (UIWindow *w in windows) {
                        if (w.isKeyWindow) {
                            window = w;
                            break;
                        }
                    }
                }
            }
        }
    }
#endif
    return window;
}

@end
