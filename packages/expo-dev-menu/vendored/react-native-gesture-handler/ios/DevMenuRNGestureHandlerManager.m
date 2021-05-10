#import "DevMenuRNGestureHandlerManager.h"

#import <React/RCTLog.h>
#import <React/RCTViewManager.h>
#import <React/RCTComponent.h>
#import <React/RCTRootView.h>
#import <React/RCTTouchHandler.h>
#import <React/RCTRootContentView.h>

#import "DevMenuRNGestureHandlerState.h"
#import "DevMenuRNGestureHandler.h"
#import "DevMenuRNGestureHandlerRegistry.h"
#import "DevMenuRNRootViewGestureRecognizer.h"

#import "Handlers/DevMenuRNPanHandler.h"
#import "Handlers/DevMenuRNTapHandler.h"
#import "Handlers/DevMenuRNFlingHandler.h"
#import "Handlers/DevMenuRNLongPressHandler.h"
#import "Handlers/DevMenuRNNativeViewHandler.h"
#import "Handlers/DevMenuRNPinchHandler.h"
#import "Handlers/DevMenuRNRotationHandler.h"
#import "Handlers/DevMenuRNForceTouchHandler.h"

// We use the method below instead of RCTLog because we log out messages after the bridge gets
// turned down in some cases. Which normally with RCTLog would cause a crash in DEBUG mode
#define RCTLifecycleLog(...) RCTDefaultLogFunction(RCTLogLevelInfo, RCTLogSourceNative, @(__FILE__), @(__LINE__), [NSString stringWithFormat:__VA_ARGS__])

@interface DevMenuRNGestureHandlerManager () <DevMenuRNGestureHandlerEventEmitter, DevMenuRNRootViewGestureRecognizerDelegate>

@end

@implementation DevMenuRNGestureHandlerManager
{
    DevMenuRNGestureHandlerRegistry *_registry;
    RCTUIManager *_uiManager;
    NSMutableSet<UIView*> *_rootViews;
    RCTEventDispatcher *_eventDispatcher;
}

- (instancetype)initWithUIManager:(RCTUIManager *)uiManager
                  eventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
    if ((self = [super init])) {
        _uiManager = uiManager;
        _eventDispatcher = eventDispatcher;
        _registry = [DevMenuRNGestureHandlerRegistry new];
        _rootViews = [NSMutableSet new];
    }
    return self;
}

- (void)createGestureHandler:(NSString *)handlerName
                         tag:(NSNumber *)handlerTag
                      config:(NSDictionary *)config
{
    static NSDictionary *map;
    static dispatch_once_t mapToken;
    dispatch_once(&mapToken, ^{
        map = @{
                @"PanGestureHandler" : [DevMenuRNPanGestureHandler class],
                @"TapGestureHandler" : [DevMenuRNTapGestureHandler class],
                @"FlingGestureHandler" : [DevMenuRNFlingGestureHandler class],
                @"LongPressGestureHandler": [DevMenuRNLongPressGestureHandler class],
                @"NativeViewGestureHandler": [DevMenuRNNativeViewGestureHandler class],
                @"PinchGestureHandler": [DevMenuRNPinchGestureHandler class],
                @"RotationGestureHandler": [DevMenuRNRotationGestureHandler class],
                @"ForceTouchGestureHandler": [DevMenuRNForceTouchHandler class],
                };
    });
    
    Class nodeClass = map[handlerName];
    if (!nodeClass) {
        RCTLogError(@"Gesture handler type %@ is not supported", handlerName);
        return;
    }
    
    DevMenuRNGestureHandler *gestureHandler = [[nodeClass alloc] initWithTag:handlerTag];
    [gestureHandler configure:config];
    [_registry registerGestureHandler:gestureHandler];
    
    __weak id<DevMenuRNGestureHandlerEventEmitter> emitter = self;
    gestureHandler.emitter = emitter;
}


- (void)attachGestureHandler:(nonnull NSNumber *)handlerTag
               toViewWithTag:(nonnull NSNumber *)viewTag
{
    UIView *view = [_uiManager viewForReactTag:viewTag];

    [_registry attachHandlerWithTag:handlerTag toView:view];

    // register root view if not already there
    [self registerRootViewIfNeeded:view];
}

- (void)updateGestureHandler:(NSNumber *)handlerTag config:(NSDictionary *)config
{
    DevMenuRNGestureHandler *handler = [_registry handlerWithTag:handlerTag];
    [handler configure:config];
}

- (void)dropGestureHandler:(NSNumber *)handlerTag
{
    [_registry dropHandlerWithTag:handlerTag];
}

- (void)handleSetJSResponder:(NSNumber *)viewTag blockNativeResponder:(NSNumber *)blockNativeResponder
{
    if ([blockNativeResponder boolValue]) {
        for (RCTRootView *rootView in _rootViews) {
            for (UIGestureRecognizer *recognizer in rootView.gestureRecognizers) {
                if ([recognizer isKindOfClass:[DevMenuRNRootViewGestureRecognizer class]]) {
                    [(DevMenuRNRootViewGestureRecognizer *)recognizer blockOtherRecognizers];
                }
            }
        }
    }
}

- (void)handleClearJSResponder
{
    // ignore...
}

#pragma mark Root Views Management

- (void)registerRootViewIfNeeded:(UIView*)childView
{
    UIView *parent = childView;
    while (parent != nil && ![parent isKindOfClass:[RCTRootView class]]) parent = parent.superview;
    
    RCTRootView *rootView = (RCTRootView *)parent;
    UIView *rootContentView = rootView.contentView;
    if (rootContentView != nil && ![_rootViews containsObject:rootContentView]) {
        RCTLifecycleLog(@"[GESTURE HANDLER] Initialize gesture handler for root view %@", rootContentView);
        [_rootViews addObject:rootContentView];
        DevMenuRNRootViewGestureRecognizer *recognizer = [DevMenuRNRootViewGestureRecognizer new];
        recognizer.delegate = self;
        rootContentView.userInteractionEnabled = YES;
        [rootContentView addGestureRecognizer:recognizer];
    }
}

- (void)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    didActivateInRootView:(UIView *)rootContentView
{
    // Cancel touches in DevMenuRN's root view in order to cancel all in-js recognizers

    // As scroll events are special-cased in DevMenuRN responder implementation and sending them would
    // trigger JS responder change, we don't cancel touches if the handler that got activated is
    // a scroll recognizer. This way root view will keep sending touchMove and touchEnd events
    // and therefore allow JS responder to properly release the responder at the end of the touch
    // stream.
    // NOTE: this is not a proper fix and solving this problem requires upstream fixes to DevMenuRN. In
    // particular if we have one PanHandler and ScrollView that can work simultaniously then when
    // the Pan handler activates it would still tigger cancel events.
    // Once the upstream fix lands the line below along with this comment can be removed
    if ([gestureRecognizer.view isKindOfClass:[UIScrollView class]]) return;

    UIView *parent = rootContentView.superview;
    if ([parent isKindOfClass:[RCTRootView class]]) {
        [((RCTRootContentView*)rootContentView).touchHandler cancel];
    }
}

- (void)dealloc
{
    if ([_rootViews count] > 0) {
        RCTLifecycleLog(@"[GESTURE HANDLER] Tearing down gesture handler registered for views %@", _rootViews);
    }
}

#pragma mark Events

- (void)sendTouchEvent:(DevMenuRNGestureHandlerEvent *)event
{
    [_eventDispatcher sendEvent:event];
}

- (void)sendStateChangeEvent:(DevMenuRNGestureHandlerStateChange *)event
{
    [_eventDispatcher sendEvent:event];
}

@end
