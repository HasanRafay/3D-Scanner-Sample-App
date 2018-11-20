/*
 This file is part of the Structure SDK.
 Copyright © 2016 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "ViewController.h"
#import "ViewController+CaptureSession.h"
#import "ViewController+SLAM.h"
#import "ViewController+OpenGL.h"

@implementation ViewController (Sensor)

- (void)setupCaptureSession
{
    // Clear / reset the capture session if it already exists
    if (!_captureSession)
    {
        _captureSession = nil;
    }
    
    // Create an STCaptureSession instance
    _captureSession = [STCaptureSession newCaptureSession];
    
    NSDictionary* sensorConfig = @{
                                   kSTCaptureSessionOptionColorResolutionKey: @(STCaptureSessionColorResolution640x480),
                                   kSTCaptureSessionOptionDepthSensorVGAEnabledIfAvailableKey: @(YES),
                                   kSTCaptureSessionOptionColorMaxFPSKey: @(30.0f),
                                   kSTCaptureSessionOptionDepthSensorEnabledKey: @(YES),
                                   kSTCaptureSessionOptionUseAppleCoreMotionKey: @(YES),
                                   kSTCaptureSessionOptionSimulateRealtimePlaybackKey: @(YES),
                                   };
    
    _captureSession.occWriter.useH264ForColor = YES;

    // Set the lens detector on, and default lens state as "non-WVL" mode
    _captureSession.lens = STLensNormal;
    _captureSession.lensDetection = STLensDetectorOn;
    
    // Set ourself as the delegate to receive sensor data.
    _captureSession.delegate = self;
[_captureSession startMonitoringWithOptions:sensorConfig];
}

- (BOOL)isStructureConnected
{
    return _captureSession.sensorMode >= STCaptureSessionSensorModeNotConnected;
}

#pragma mark -  STCaptureSession delegate methods

- (void)captureSession:(STCaptureSession*)captureSession colorCameraDidEnterMode:(STCaptureSessionColorCameraMode)mode
{
    switch (mode)
    {
        case STCaptureSessionColorCameraModeReady:
        case STCaptureSessionColorCameraModePermissionDenied:
            break;
        // Fall through intentional
        case STCaptureSessionColorCameraModeUnknown:
        default:
            @throw [NSException exceptionWithName:@"RoomCapture"
                                           reason:@"Unknown STCaptureSessionColorCameraMode!"
                                         userInfo:nil];
            break;
    }
    [self updateAppStatusMessage];
}

- (void)captureSession:(STCaptureSession*)captureSession sensorDidEnterMode:(STCaptureSessionSensorMode)mode
{
    switch (mode)
    {
        case STCaptureSessionSensorModeReady:
        case STCaptureSessionSensorModeWakingUp:
        case STCaptureSessionSensorModeStandby:
        case STCaptureSessionSensorModeNotConnected:
        case STCaptureSessionSensorModeBatteryDepleted:
            break;
        // Fall through intentional
        case STCaptureSessionSensorModeUnknown:
        default:
            @throw [NSException exceptionWithName:@"RoomCapture"
                                           reason:@"Unknown STCaptureSessionSensorMode!"
                                         userInfo:nil];
            break;
    }
    [self updateAppStatusMessage];
}

- (void)captureSession:(STCaptureSession*)captureSession sensorChargerStateChanged:(STCaptureSessionSensorChargerState)chargerState
{
    switch (chargerState)
    {
        case STCaptureSessionSensorChargerStateConnected:
            break;
        case STCaptureSessionSensorChargerStateDisconnected:
            // Do nothing, we only need to handle low-power notifications based on the sensor mode.
            break;
        case STCaptureSessionSensorChargerStateUnknown:
        default:
            @throw [NSException exceptionWithName:@"RoomCapture"
                                           reason:@"Unknown STCaptureSessionSensorChargerState!"
                                         userInfo:nil];
            break;
    }
    [self updateAppStatusMessage];
}

- (void)captureSession:(STCaptureSession*)captureSession didStartAVCaptureSession:(AVCaptureSession*)avCaptureSession
{
    [self enterPoseInitializationState];
}

- (void)captureSession:(STCaptureSession*)captureSession didStopAVCaptureSession:(AVCaptureSession*)avCaptureSession
{
}

- (void)captureSession:(STCaptureSession*)captureSession didOutputSample:(NSDictionary*)sample type:(STCaptureSessionSampleType)type
{
    switch (type)
    {
        case STCaptureSessionSampleTypeSensorDepthFrame:
        {
            STDepthFrame* depthFrame = [sample objectForKey:kSTCaptureSessionSampleEntryDepthFrame];
            if (_slamState.initialized)
            {
                [self processDepthFrame:depthFrame colorFrame:nil];
                // Scene rendering is triggered by new frames to avoid rendering the same view several times.
                [self renderSceneWithDepthFrame:depthFrame colorFrame:nil];
            }
            break;
        }
        case STCaptureSessionSampleTypeIOSColorFrame:
        {
            // Skipping until a pair is returned.
            break;
        }
        case STCaptureSessionSampleTypeSynchronizedFrames:
        {
            STDepthFrame* depthFrame = [sample objectForKey:kSTCaptureSessionSampleEntryDepthFrame];
            STColorFrame* colorFrame = [sample objectForKey:kSTCaptureSessionSampleEntryIOSColorFrame];
            if (_slamState.initialized)
            {
                [self processDepthFrame:depthFrame colorFrame:colorFrame];
                // Scene rendering is triggered by new frames to avoid rendering the same view several times.
                [self renderSceneWithDepthFrame:depthFrame colorFrame:colorFrame];
            }
            break;
        }
        case STCaptureSessionSampleTypeDeviceMotionData:
        {
            CMDeviceMotion* deviceMotion = [sample objectForKey:kSTCaptureSessionSampleEntryDeviceMotionData];
            [self processDeviceMotion:deviceMotion withError:nil];
            break;
        }
        case STCaptureSessionSampleTypeUnknown:
            @throw [NSException exceptionWithName:@"RoomCapture"
                                           reason:@"Unknown STCaptureSessionSampleType!"
                                         userInfo:nil];
            break;
        default:
            NSLog(@"Skipping Capture Session sample type: %ld", static_cast<long>(type));
            break;
    }
}

- (void)captureSession:(STCaptureSession*)captureSession onLensDetectorOutput:(STDetectedLensStatus)detectedLensStatus
{
    switch (detectedLensStatus)
    {
        case STDetectedLensNormal:
            // Detected a WVL is not attached to the bracket.
            NSLog(@"Detected that the WVL is off!");
            break;
        case STDetectedLensWideVisionLens:
            // Detected a WVL is attached to the bracket.
            NSLog(@"Detected that the WVL is on!");
            break;
        case STDetectedLensPerformingInitialDetection:
            // Triggers immediately when detector is turned on. Can put a message here
            // showing the user that the detector is working and they need to pan the
            // camera for best results
            NSLog(@"Performing initial detection!");
            break;
        case STDetectedLensUnsure:
            break;
        default:
            @throw [NSException exceptionWithName:@"RoomCapture"
                                           reason:@"Unknown STDetectedLensStatus!"
                                         userInfo:nil];
            break;
    }
}

@end
