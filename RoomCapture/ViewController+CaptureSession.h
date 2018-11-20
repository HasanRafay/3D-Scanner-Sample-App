/*
 This file is part of the Structure SDK.
 Copyright © 2016 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#define HAS_LIBCXX

#import "ViewController.h"
#import <Structure/StructureSLAM.h>

#import "MeshViewController.h"

@interface ViewController (CaptureSession) <STCaptureSessionDelegate>

- (void)setupCaptureSession;
- (BOOL)isStructureConnected;

@end
