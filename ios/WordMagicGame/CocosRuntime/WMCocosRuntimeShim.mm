#import "WMCocosRuntimeShim.h"
#include <TargetConditionals.h>

#if TARGET_OS_SIMULATOR

// Cocos Creator 3.8 ships simulator prebuilts for x86_64 only; the host app
// targets arm64 simulators, so the runtime is compiled out entirely here.
@implementation WMCocosRuntimeShim

+ (instancetype)shared {
    static WMCocosRuntimeShim *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [WMCocosRuntimeShim new]; });
    return shared;
}

+ (BOOL)isLinked { return NO; }
- (BOOL)presentCocosWindow { return NO; }
- (void)dismissCocosWindow {}
- (void)sendToScript:(NSString *)json {}
- (void)setScriptHandler:(WMScriptMessageHandler)handler {}

@end

#else

#import <QuartzCore/CAMetalLayer.h>

#include "WMCocosEnginePrelude.h"

#include "platform/BasePlatform.h"
#import "platform/ios/AppDelegateBridge.h"
#import "platform/ios/View.h"
#import "platform/apple/JsbBridgeWrapper.h"

static NSString *const kWMToScriptEvent = @"wmBattleToScript";
static NSString *const kWMToNativeEvent = @"wmBattleToNative";

#pragma mark - WMCocosViewController

// Minimal replacement for the generated ViewController.mm: same rendering
// surface handling, but forwards size changes to a bridge instance we own
// instead of reaching back into a Cocos AppDelegate.
@interface WMCocosViewController : UIViewController
@property (nonatomic, strong) AppDelegateBridge *appDelegateBridge;
@end

@implementation WMCocosViewController

- (BOOL)shouldAutorotate { return YES; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self.appDelegateBridge viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    float pixelRatio = [self.appDelegateBridge getPixelRatio];
    CAMetalLayer *layer = (CAMetalLayer *)self.view.layer;
    layer.drawableSize = CGSizeMake(static_cast<int>(size.width * pixelRatio),
                                    static_cast<int>(size.height * pixelRatio));
}

@end

#pragma mark - WMCocosRuntimeShim

@implementation WMCocosRuntimeShim {
    UIWindow *_cocosWindow;
    WMCocosViewController *_viewController;
    AppDelegateBridge *_appDelegateBridge;
    WMScriptMessageHandler _handler;
    BOOL _booted;
}

+ (instancetype)shared {
    static WMCocosRuntimeShim *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [WMCocosRuntimeShim new]; });
    return shared;
}

+ (BOOL)isLinked { return YES; }

- (BOOL)presentCocosWindow {
    if (_booted) {
        _cocosWindow.hidden = NO;
        [_cocosWindow makeKeyAndVisible];
        [_appDelegateBridge applicationDidBecomeActive:UIApplication.sharedApplication];
        return YES;
    }
    return [self boot];
}

- (BOOL)boot {
    cc::BasePlatform *platform = cc::BasePlatform::getPlatform();
    if (platform->init() != 0) {
        NSLog(@"[CocosRuntime] platform init failed");
        return NO;
    }

    CGRect bounds = UIScreen.mainScreen.bounds;
    _cocosWindow = [[UIWindow alloc] initWithFrame:bounds];

    _viewController = [WMCocosViewController new];
    View *view = [[View alloc] initWithFrame:bounds];
    view.contentScaleFactor = UIScreen.mainScreen.scale;
    view.multipleTouchEnabled = YES;
    _viewController.view = view;
    _cocosWindow.rootViewController = _viewController;

    // SystemWindow.mm resolves the render surface through
    // UIApplication.delegate.window.rootViewController.view, so the host
    // AppDelegate must report the Cocos window as its `window`.
    id<UIApplicationDelegate> appDelegate = UIApplication.sharedApplication.delegate;
    if ([appDelegate respondsToSelector:@selector(setWindow:)]) {
        [(NSObject *)appDelegate setValue:_cocosWindow forKey:@"window"];
    } else {
        NSLog(@"[CocosRuntime] host AppDelegate has no window property; cannot boot");
        _cocosWindow = nil;
        _viewController = nil;
        return NO;
    }

    [_cocosWindow makeKeyAndVisible];

    _appDelegateBridge = [[AppDelegateBridge alloc] init];
    _viewController.appDelegateBridge = _appDelegateBridge;
    [_appDelegateBridge application:UIApplication.sharedApplication didFinishLaunchingWithOptions:@{}];

    __weak WMCocosRuntimeShim *weakSelf = self;
    [[JsbBridgeWrapper sharedInstance] addScriptEventListener:kWMToNativeEvent
                                                     listener:^(NSString *arg) {
        WMCocosRuntimeShim *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        WMScriptMessageHandler handler = strongSelf->_handler;
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{ handler(arg); });
        }
    }];

    _booted = YES;
    return YES;
}

- (void)dismissCocosWindow {
    if (!_booted) { return; }
    [_appDelegateBridge applicationWillResignActive:UIApplication.sharedApplication];
    _cocosWindow.hidden = YES;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window != _cocosWindow && !window.isHidden) {
            [window makeKeyWindow];
            break;
        }
    }
}

- (void)sendToScript:(NSString *)json {
    if (!_booted) { return; }
    [[JsbBridgeWrapper sharedInstance] dispatchEventToScript:kWMToScriptEvent arg:json];
}

- (void)setScriptHandler:(WMScriptMessageHandler)handler {
    _handler = [handler copy];
}

@end

#endif
