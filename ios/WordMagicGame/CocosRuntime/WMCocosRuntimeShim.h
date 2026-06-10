#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WMScriptMessageHandler)(NSString *json);

/// Hosts the embedded Cocos Creator runtime in a dedicated UIWindow.
/// The engine renders into `UIApplication.delegate.window.rootViewController.view`,
/// so this shim owns a second window shown only while a battle is on screen.
/// On the simulator the Cocos prebuilt libraries are unavailable (x86_64 only),
/// so every method is a no-op and `isLinked` returns NO.
@interface WMCocosRuntimeShim : NSObject

@property (class, readonly) BOOL isLinked;

+ (instancetype)shared;

/// Boots the engine on first call (irreversible for the process lifetime),
/// then shows the Cocos window. Returns NO if the runtime is unavailable
/// or engine initialization failed.
- (BOOL)presentCocosWindow;

/// Pauses the engine and hides the Cocos window, returning key-window status
/// to the host app window.
- (void)dismissCocosWindow;

- (void)sendToScript:(NSString *)json;
- (void)setScriptHandler:(nullable WMScriptMessageHandler)handler;

/// Spike diagnostics: logs whether the engine loop ticks and what the JS
/// world looks like. Safe to call any time after presentCocosWindow.
- (void)debugProbe;

@end

NS_ASSUME_NONNULL_END
