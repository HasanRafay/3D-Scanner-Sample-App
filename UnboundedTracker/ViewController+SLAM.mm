/*
  This file is part of the Structure SDK.
  Copyright © 2016 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+SLAM.h"
#import "ViewController+CaptureSession.h"

#import <mach/mach_time.h>

#import "MotionLogs.h"

@implementation ViewController (SLAM)

- (void)clearSLAM
{
    _slamState.initialized = false;
    _slamState.scene = nil;
    [_slamState.trackerThread reset];
    [_slamState.trackerThread stop];
    _slamState.trackerThread.tracker = nil;
}

// Setup SLAM related objects.
- (void)setupSLAM
{
    if (_slamState.initialized)
        return;
    
    // Create an EAGLContext to use with the tracker.
    _slamState.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_slamState.context)
    {
        NSLog(@"Failed to create ES context");
        return;
    }
    
    // Initialize the scene.
    _slamState.scene = [[STScene alloc] initWithContext:_slamState.context];
    
    NSDictionary* trackerOptions = @{
                                     kSTTrackerTypeKey: @(STTrackerDepthAndColorBased),
                                     kSTTrackerTrackAgainstModelKey: @FALSE, // not creating a global model
                                     kSTTrackerQualityKey: @(STTrackerQualityAccurate),
                                     kSTTrackerBackgroundProcessingEnabledKey: @YES,
                                     kSTTrackerAvoidPitchRollDriftKey: @YES,
                                     kSTTrackerAvoidHeightDriftKey: @YES,
                                     };
    
    STTracker* tracker = [[STTracker alloc] initWithScene:_slamState.scene options:trackerOptions];
    
    _slamState.trackerThread = [[TrackerThread alloc] init];
    _slamState.trackerThread.tracker = tracker;
    [_slamState.trackerThread start];
    
    // Setup the cube placement initializer.
    _slamState.cameraPoseInitializer = [[STCameraPoseInitializer alloc]
                                        initWithVolumeSizeInMeters:GLKVector3Make(1.f,1.f,1.f) // not used
                                        options:@{kSTCameraPoseInitializerStrategyKey: @(STCameraPoseInitializerStrategyGravityAlignedAtOrigin)}];
    
    // Start with cube placement mode
    [self enterWaitingForStartState];
    
    _slamState.initialized = true;
}

// This will be called after resuming from background or if the sensor was unplugged. We want
// to reset the tracker because it won't be able to recover, but to keep the same pose in the
// virtual world.
- (void)gracefullyResetTrackerWhileKeepingPreviousPose
{
    TrackerUpdate lastUpdate = _slamState.trackerThread.lastUpdate;
    
    if (lastUpdate.couldEstimatePose)
    {
        [_slamState.trackerThread reset];
        [_slamState.trackerThread setInitialTrackerPose:lastUpdate.cameraPose timestamp:nowInSeconds()];
    }
    else
    {
        NSLog(@"Warning: could not reset the pose gracefully, there was no previous estimate.");
    }
}

- (void)enterWaitingForStartState
{
    // Cannot be lost in initial placement mode.
    self.trackingLostLabel.hidden = YES;
    
    _slamState.isTracking = NO;
    
    // Restore automatic color camera parameters.
    _captureSession.properties = STCaptureSessionPropertiesSetColorCameraAutoExposureISOAndWhiteBalance();
}

- (void)enterTrackingState
{
    // Lock color camera settings to ensure smoother transitions between keyframes.
    _captureSession.lensDetection = STLensDetectorOff;
    _captureSession.properties = STCaptureSessionPropertiesLockAllColorCameraPropertiesToCurrent();

    _slamState.isTracking = YES;
}

- (bool)trackingConsideredBad
{
    return _slamState.lastSceneKitTrackerUpdateProcessed.trackerHints.trackerIsLost ||
        _slamState.lastSceneKitTrackerUpdateProcessed.poseAccuracy < STTrackerPoseAccuracyApproximate ||
        _slamState.lastSceneKitTrackerUpdateProcessed.trackingError != nil;
}

- (TrackerUpdate)getMoreRecentTrackerUpdate:(double)previousTimestamp
{
    TrackerUpdate newTrackerUpdate;
    
    // If the sensor is disconnected, we don't want the panning to slow down.
    // Never wait for more than 25 ms. We probably dropped a frame if this happens.
    int maxWaitTime = [self isStructureConnected] ? 0.025: 0.0166;
    newTrackerUpdate = [_slamState.trackerThread waitForUpdateMoreRecentThan:previousTimestamp maxWaitTimeSeconds:maxWaitTime];

    // Motion Logging
    if (![self trackingConsideredBad])
    {
        [MotionLogs logTrackerPose:newTrackerUpdate.cameraPose atTime:newTrackerUpdate.timestamp];
    }
    
    return newTrackerUpdate;
}

#pragma mark - Structure Sensor & SLAM Management

- (void)onStructureSensorStartedStreaming
{
    // We cannot initialize SLAM objects before a sensor is ready to be used, so now is a good time
    // to do it.
    if (!_slamState.initialized)
    {
        [self clearSLAM];
        
        // One-time setup of SLAM related members now that we have a sensor connected
        [self setupSLAM];
    }
    else
    {
        // Here we need to reset the tracker because the user may have moved far away, and
        // exposure might be different too.
        [self gracefullyResetTrackerWhileKeepingPreviousPose];
    }
}

@end
