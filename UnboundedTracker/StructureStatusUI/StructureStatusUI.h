/*
  This file is part of the Structure SDK.
  Copyright © 2016 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#import <Structure/Structure.h>
#import <Structure/STCaptureSession.h>

@interface StructureStatusUI : NSObject

- (BOOL)queryCameraAuthorizationStatusWithCompletionHandler:(void (^)(BOOL granted))handler;

- (id)initInViewController:(UIViewController*)parentView;
- (void)setCaptureSession:(STCaptureSession*)captureSession;
- (void)startBatteryTimer;
- (void)stopBatteryTimer;
- (void)updateAppStatus;

@end
