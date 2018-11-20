/*
  This file is part of the Structure SDK.
  Copyright © 2016 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#define HAS_LIBCXX
#import <Structure/Structure.h>
#import <Structure/STCaptureSession.h>

@interface ViewController : UIViewController <STCaptureSessionDelegate>

+ (instancetype) viewController;

@end
