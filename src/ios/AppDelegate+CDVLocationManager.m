/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "AppDelegate+CDVLocationManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

/**
 * YES when AppDelegate itself did not implement application:didFinishLaunchingWithOptions:
 * (cordova-ios 8: the Swift AppDelegate inherits it from CDVAppDelegate) and our method was
 * added to the class instead of exchanged with an existing one.
 */
static BOOL addedToSubclass = NO;

@implementation AppDelegate (CDVLocationManager)


+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        Class class = [self class];

        SEL originalSelector = @selector(application:didFinishLaunchingWithOptions:);
        SEL swizzledSelector = @selector(xxx_application:didFinishLaunchingWithOptions:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        
        if (didAddMethod) {
            // AppDelegate did not implement the selector itself, it inherited it from
            // CDVAppDelegate (cordova-ios 8). Do not bind xxx_ to the inherited IMP as
            // it is now: other plugins (e.g. cordova-plugin-firebasex-core) swizzle the
            // same selector on CDVAppDelegate from their own +load, and a captured IMP
            // would bypass whichever of them loads later. xxx_ forwards to the
            // superclass's current implementation instead (see below).
            addedToSubclass = YES;
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
        
    });
}

- (BOOL) xxx_application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    BOOL launchedWithoutOptions = launchOptions == nil;
    
    if (!launchedWithoutOptions) {
        [self requestMoreBackgroundExecutionTime];
    }
    
    if (addedToSubclass) {
        // Dispatch to the superclass's implementation as it is at call time, so
        // swizzles applied to CDVAppDelegate by other plugins stay in the chain.
        SEL originalSelector = @selector(application:didFinishLaunchingWithOptions:);
        Class superclass = class_getSuperclass([AppDelegate class]);
        if (![superclass instancesRespondToSelector:originalSelector]) {
            return YES;
        }
        struct objc_super superInfo = { self, superclass };
        BOOL (*sendSuper)(struct objc_super *, SEL, UIApplication *, NSDictionary *) = (void *)objc_msgSendSuper;
        return sendSuper(&superInfo, originalSelector, application, launchOptions);
    }
    
    return [self xxx_application:application didFinishLaunchingWithOptions:launchOptions];
    
}

- (UIBackgroundTaskIdentifier) backgroundTaskIdentifier {
    NSNumber *asNumber = objc_getAssociatedObject(self, @selector(backgroundTaskIdentifier));
    UIBackgroundTaskIdentifier  taskId = [asNumber unsignedIntValue];
    return taskId;
}

- (void)setBackgroundTaskIdentifier:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier {
    NSNumber *asNumber = [NSNumber numberWithUnsignedInt:backgroundTaskIdentifier];
    objc_setAssociatedObject(self, @selector(backgroundTaskIdentifier), asNumber, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void) requestMoreBackgroundExecutionTime {

    UIApplication *application = [UIApplication sharedApplication];

    // A task from an earlier launch-time call that is still running is ended first.
    [self endBackgroundExecutionTime];

    __weak typeof(self) weakSelf = self;
    self.backgroundTaskIdentifier = [application beginBackgroundTaskWithName:@"CDVLocationManager launch" expirationHandler:^{
        // The task has to be ended here, not just forgotten: a task that is still running
        // after its expiration handler returned gets the app terminated ("has active
        // assertions beyond permitted time"). That hit every launch with launch options,
        // such as a launch by a background push or by a location event, about 30 seconds in.
        [weakSelf endBackgroundExecutionTime];
    }];
}

- (void) endBackgroundExecutionTime {
    UIBackgroundTaskIdentifier taskId = self.backgroundTaskIdentifier;
    if (taskId != UIBackgroundTaskInvalid) {
        self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask:taskId];
    }
}


@end
