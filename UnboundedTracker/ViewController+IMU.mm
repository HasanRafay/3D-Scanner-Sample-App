/*
  This file is part of the Structure SDK.
  Copyright © 2016 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+IMU.h"

@implementation ViewController (IMU)

- (void)processDeviceMotion:(CMDeviceMotion *)motion withError:(NSError *)error
{
    if (!_slamState.isTracking)
    {
        // Update our gravity vector, it will be used by the cube placement initializer.
        _lastGravity = GLKVector3Make (motion.gravity.x, motion.gravity.y, motion.gravity.z);
    }
    
    // The tracker is more robust to fast moves if we feed it with motion data.
    [_slamState.trackerThread updateWithMotion:motion];
}

@end

