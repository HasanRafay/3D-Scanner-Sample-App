/*
  This file is part of the Structure SDK.
  Copyright © 2016 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+CaptureSession.h"
#import "ViewController+IMU.h"
#import "ViewController+SLAM.h"
#import "MotionLogs.h"

@implementation ViewController (Sensor)

#pragma mark - setup

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
    [_structureStatusUI setCaptureSession:_captureSession];
}

- (void)startStructureStreaming
{
    if (![self isStructureConnected])
        return;
    
    // Tell the driver to start streaming.
    _captureSession.streamingEnabled = YES;
    
    NSLog(@"[Structure] streaming started");
    
    // Notify and initialize streaming dependent objects.
    [self onStructureSensorStartedStreaming];
    
    [[self recordButton] setHidden:NO];
    [[self recordButton] setTitle:@"Record Path" forState:UIControlStateNormal];
}

- (BOOL)isStructureConnected
{
    return _captureSession.sensorMode > STCaptureSessionSensorModeNotConnected;
}

#pragma mark - STCaptureSession delegate events

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
            @throw [NSException exceptionWithName:@"UnboundedTracker"
                                           reason:@"Unknown STCaptureSessionColorCameraMode!"
                                         userInfo:nil];
            break;
    }
    [_structureStatusUI updateAppStatus];
}

- (void)captureSession:(STCaptureSession*)captureSession sensorDidEnterMode:(STCaptureSessionSensorMode)mode
{
    switch (mode)
    {
        case STCaptureSessionSensorModeReady:
            [self startStructureStreaming];
            [_structureStatusUI startBatteryTimer];
            break;
        case STCaptureSessionSensorModeWakingUp:
        case STCaptureSessionSensorModeStandby:
            break;
        // Fall through intentional
        case STCaptureSessionSensorModeNotConnected:
        case STCaptureSessionSensorModeBatteryDepleted:
            [_structureStatusUI stopBatteryTimer];
            [[self recordButton] setHidden:YES];
            [MotionLogs stopMotionLogRecording];
            break;
        // Fall through intentional
        case STCaptureSessionSensorModeUnknown:
        default:
            @throw [NSException exceptionWithName:@"UnboundedTracker"
                                           reason:@"Unknown STCaptureSessionSensorMode!"
                                         userInfo:nil];
            break;
    }
    [_structureStatusUI updateAppStatus];
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
            @throw [NSException exceptionWithName:@"UnboundedTracker"
                                           reason:@"Unknown STCaptureSessionSensorChargerState!"
                                         userInfo:nil];
            break;
    }
    [_structureStatusUI updateAppStatus];
}

- (void)captureSession:(STCaptureSession*)captureSession didStartAVCaptureSession:(AVCaptureSession*)avCaptureSession
{
    // Initialize our default video device properties once the AVCaptureSession has been started.
    _captureSession.properties = STCaptureSessionPropertiesSetColorCameraAutoExposureISOAndWhiteBalance();
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
            // Skipping unless a synchronized pair is returned
            break;
        }
        case STCaptureSessionSampleTypeIOSColorFrame:
        {
            // Skipping unless a synchronized pair is returned
            break;
        }
        case STCaptureSessionSampleTypeSynchronizedFrames:
        {
            STDepthFrame* depthFrame = [sample objectForKey:kSTCaptureSessionSampleEntryDepthFrame];
            STColorFrame* colorFrame = [sample objectForKey:kSTCaptureSessionSampleEntryIOSColorFrame];
            if (_slamState.initialized)
            {
                if (!_slamState.isTracking) // Initially, we are in the waiting state.
                {
                    // Estimate the new initial position. The cameraPoseInitializer will make sure the initial
                    // orientation is aligned with gravity.
                    [_slamState.cameraPoseInitializer updateCameraPoseWithGravity:_lastGravity depthFrame:depthFrame error:nil];
                    
                    GLKMatrix4 initialCameraPose = _slamState.cameraPoseInitializer.lastOutput.cameraPose;
                    // Set the initial camera translation to human height (1.5m). GLKMatrix4 is column-major.
                    initialCameraPose = GLKMatrix4SetColumn (initialCameraPose, 3, _slamState.initialTrackerTranslation);
                    [_slamState.trackerThread setInitialTrackerPose:initialCameraPose timestamp:nowInSeconds()];
                    
                    // Starting tracking right away.
                    [self enterTrackingState];
                }
                else
                {
                    double newTimestamp = nowInSeconds();
                    // This test is trying to avoid processing frames which arrive in batch. Sometimes scheduling becomes messy
                    // and instead of getting a frame after 33ms, we get no frames for 66ms, and then two frames at the same time.
                    // Trying to process them both will make the SceneKit thread starve, so we'll just skip one if we receive two
                    // frames in less than 5 milliseconds.
                    if (_slamState.previousFrameTimestamp < 0 || (newTimestamp - _slamState.previousFrameTimestamp) > 0.005)
                    {
                        const int timeoutSeconds = 20/1000.; // don't allow it to eat more than 20ms of the main thread.
                        
                        // We need to take a copy of the depth frame since it won't survive the callback scope.
                        // However the color frame will live long enough since the AVFoundation pool is quite big.
                        [_slamState.trackerThread updateWithDepthFrame:[depthFrame copy] colorFrame:colorFrame maxWaitTimeSeconds:timeoutSeconds];
                    }
                    _slamState.previousFrameTimestamp = newTimestamp;
                }
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
            @throw [NSException exceptionWithName:@"UnboundedTracker"
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
            @throw [NSException exceptionWithName:@"UnboundedTracker"
                                           reason:@"Unknown STDetectedLensStatus!"
                                         userInfo:nil];
            break;
    }
}

@end
