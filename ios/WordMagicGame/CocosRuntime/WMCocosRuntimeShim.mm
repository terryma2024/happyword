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
- (BOOL)isBooted { return NO; }
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
#include "application/ApplicationManager.h"
#include "bindings/jswrapper/SeApi.h"

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

- (BOOL)isBooted { return _booted; }

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
    // Register the script listener before the engine boots: JsbBridgeWrapper
    // is plain ObjC with no script-engine dependency, and battle/ready may be
    // dispatched during engine startup.
    __weak WMCocosRuntimeShim *weakSelf = self;
    // JsbBridgeWrapper is compiled without ARC and its addScriptEventListener
    // takes OWNERSHIP of the listener (it calls [listener release] after
    // adding it to the array). ARC passes arguments at +0, so hand the method
    // an extra retain or the block is over-released and the array ends up
    // holding a dangling pointer (crash on first triggerEvent).
    OnScriptEventListener listener = [^(NSString *arg) {
        NSLog(@"[CocosRuntime] script -> native: %@", arg);
        WMCocosRuntimeShim *strongSelf = weakSelf;
        if (!strongSelf) { return; }
        WMScriptMessageHandler handler = strongSelf->_handler;
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{ handler(arg); });
        }
    } copy];
    CFRetain((__bridge CFTypeRef)listener);
    [[JsbBridgeWrapper sharedInstance] addScriptEventListener:kWMToNativeEvent
                                                     listener:listener];
    NSLog(@"[CocosRuntime] script listener registered");

    cc::BasePlatform *platform = cc::BasePlatform::getPlatform();
    if (platform->init() != 0) {
        NSLog(@"[CocosRuntime] platform init failed");
        return NO;
    }
    NSLog(@"[CocosRuntime] platform init ok");

    CGRect bounds = UIScreen.mainScreen.bounds;
    _cocosWindow = [[UIWindow alloc] initWithFrame:bounds];

    // Scene-based apps never display a window that is not attached to a
    // UIWindowScene.
    UIWindowScene *windowScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            windowScene = (UIWindowScene *)scene;
            if (scene.activationState == UISceneActivationStateForegroundActive) { break; }
        }
    }
    if (windowScene == nil) {
        NSLog(@"[CocosRuntime] no UIWindowScene available; cannot boot");
        _cocosWindow = nil;
        return NO;
    }
    _cocosWindow.windowScene = windowScene;

    _viewController = [WMCocosViewController new];
    View *view = [[View alloc] initWithFrame:bounds];
    view.contentScaleFactor = UIScreen.mainScreen.scale;
    view.multipleTouchEnabled = YES;
    _viewController.view = view;
    _cocosWindow.rootViewController = _viewController;

    // SystemWindow.mm resolves the render surface through
    // UIApplication.delegate.window.rootViewController.view, so the host
    // AppDelegate must report the Cocos window as its `window`. The actual
    // delegate is SwiftUI's internal class, which forwards unknown selectors
    // to the @UIApplicationDelegateAdaptor instance — message it directly
    // (KVC bypasses forwarding and throws NSUnknownKeyException).
    id<UIApplicationDelegate> appDelegate = UIApplication.sharedApplication.delegate;
    if ([appDelegate respondsToSelector:@selector(setWindow:)]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [(NSObject *)appDelegate performSelector:@selector(setWindow:) withObject:_cocosWindow];
        #pragma clang diagnostic pop
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
    NSLog(@"[CocosRuntime] engine launched");

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
    NSLog(@"[CocosRuntime] native -> script: %@", json);
    [[JsbBridgeWrapper sharedInstance] dispatchEventToScript:kWMToScriptEvent arg:json];
}

- (void)setScriptHandler:(WMScriptMessageHandler)handler {
    _handler = [handler copy];
}

- (void)debugProbe {
    if (!_booted) {
        NSLog(@"[CocosRuntime] probe: not booted");
        return;
    }
    NSLog(@"[CocosRuntime] probe: scheduling on cocos thread");
    auto engine = CC_CURRENT_ENGINE();
    if (!engine) {
        NSLog(@"[CocosRuntime] probe: no current engine");
        return;
    }
    engine->getScheduler()->performFunctionInCocosThread([]() {
        NSLog(@"[CocosRuntime] probe: cocos thread alive");
        se::ScriptEngine::getInstance()->evalString(
            "console.log('[probe] cc=' + (typeof cc) + ' director=' + "
            "(typeof cc !== 'undefined' && cc.director ? 'yes' : 'no') + ' scene=' + "
            "((typeof cc !== 'undefined' && cc.director && cc.director.getScene && cc.director.getScene()) ? cc.director.getScene().name : 'none'))");
    });
}

@end

#endif
