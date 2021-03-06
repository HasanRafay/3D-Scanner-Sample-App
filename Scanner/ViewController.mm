/*
  This file is part of the Structure SDK.
  Copyright © 2018 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "ViewController+CaptureSession.h"
#import "ViewController+SLAM.h"
#import "ViewController+OpenGL.h"

#import <Structure/Structure.h>
#import <Structure/StructureSLAM.h>

#include <cmath>
#include <algorithm>

#pragma mark - ViewController Setup

@interface ViewController ()
{}

// These property should usually not been accessed directly.
// Unless you know what you're doing, modify _dynamicOptions and call syncUIfromDynamicOptions instead.
@property (weak, nonatomic) IBOutlet UISwitch *enableRGBDTrackerSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *enableNewMapperSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *enableHighResMappingSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *enableHighResolutionColorSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *enableImprovedTrackerSwitch;

@end

@implementation ViewController

+ (instancetype) viewController
{
    ViewController* vc = [[ViewController alloc] initWithNibName:@"ViewController" bundle:nil];
    return vc;
}

- (void)dealloc
{
    if ([EAGLContext currentContext] == _display.context)
    {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupGL];
    
    [self setupUserInterface];
    
    [self setupMeshViewController];
    
    [self setupGestures];
    
    [self setupIMU];

    [self setupCaptureSession];
    
    [self setupSLAM];
    
    // Later, we’ll set this true if we have a device-specific calibration
    _useColorCamera = true;
    
    // Make sure we get notified when the app becomes active to start/restore the sensor state if necessary.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    [self initializeDynamicOptions];
    [self syncUIfromDynamicOptions];
    [self enterCubePlacementState];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // The framebuffer will only be really ready with its final size after the view appears.
    [(EAGLView *)self.view setFramebuffer];
    
    [self setupGLViewport];

    [self updateAppStatusMessage];
    
    
    // We will connect to the sensor when we receive appDidBecomeActive.
}

- (void)appDidBecomeActive
{
    // Try to connect to the Structure Sensor and stream if necessary.
    if ([self currentStateNeedsSensor])
    {
        _captureSession.streamingEnabled = YES;
    }
    
    // Abort the current scan if we were still scanning before going into background since we
    // are not likely to recover well.
    if (_slamState.scannerState == ScannerStateScanning)
    {
        [self resetButtonPressed:self];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    [self respondToMemoryWarning];
}

- (void)initializeDynamicOptions
{
    _dynamicOptions.depthAndColorTrackerIsOn = true;
    _dynamicOptions.depthAndColorTrackerSwitchEnabled = true;

    _dynamicOptions.improvedTrackingIsOn = true;
    _dynamicOptions.improvedTrackingSwitchEnabled = true;
    
    _dynamicOptions.newMapperIsOn = true;
    _dynamicOptions.newMapperSwitchEnabled = true;
    
    _dynamicOptions.highResColoring = true;
    _dynamicOptions.highResColoringSwitchEnabled = true;

    _dynamicOptions.highResMapping = true;
    _dynamicOptions.highResMappingSwitchEnabled = true;
}

- (void)syncUIfromDynamicOptions
{
    // This method ensures the UI reflects the dynamic settings.
    
    self.enableRGBDTrackerSwitch.on = _dynamicOptions.depthAndColorTrackerIsOn;
    self.enableRGBDTrackerSwitch.enabled = _dynamicOptions.depthAndColorTrackerSwitchEnabled;

    self.enableImprovedTrackerSwitch.on = _dynamicOptions.improvedTrackingIsOn;
    self.enableImprovedTrackerSwitch.enabled = _dynamicOptions.improvedTrackingSwitchEnabled;
    
    self.enableHighResMappingSwitch.on = _dynamicOptions.highResMapping;
    self.enableHighResMappingSwitch.enabled = _dynamicOptions.highResMappingSwitchEnabled;
    
    self.enableNewMapperSwitch.on = _dynamicOptions.newMapperIsOn;
    self.enableNewMapperSwitch.enabled = _dynamicOptions.newMapperSwitchEnabled;
    
    self.enableHighResolutionColorSwitch.on = _dynamicOptions.highResColoring;
    self.enableHighResolutionColorSwitch.enabled = _dynamicOptions.highResColoringSwitchEnabled;
}

- (void)setupUserInterface
{
    // Make sure the status bar is hidden.
    [self prefersStatusBarHidden];
    
    // Fully transparent message label, initially.
    self.appStatusMessageLabel.alpha = 0;
    
    // Make sure the label is on top of everything else.
    self.appStatusMessageLabel.layer.zPosition = 100;
}

// Make sure the status bar is disabled (iOS 7+)
- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)setupGestures
{
    // Register pinch gesture for volume scale adjustment.
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGesture:)];
    [pinchGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchGesture];
}

- (void)setupMeshViewController
{
    _meshViewController = [MeshViewController viewController];
    _meshViewController.delegate = self;
    _meshViewNavigationController = [[UINavigationController alloc] initWithRootViewController:_meshViewController];
}

- (void)presentMeshViewer:(STMesh *)mesh
{
    [_meshViewController setupGL:_display.context];
    
    _meshViewController.colorEnabled = _useColorCamera;
    _meshViewController.mesh = mesh;
    [_meshViewController setCameraProjectionMatrix:_display.depthCameraGLProjectionMatrix];
    
    // Sample a few points to estimate the volume center
    int totalNumVertices = 0;
    for( int i=0; i<mesh.numberOfMeshes; ++i )
        totalNumVertices += [mesh numberOfMeshVertices:i];
    
    // The sample step if we need roughly 1000 sample points
    int sampleStep = std::max (1.f, totalNumVertices/1000.f);
    int sampleCount = 0;
    GLKVector3 volumeCenter = GLKVector3Make(0,0,0);
    
    for( int i=0; i<mesh.numberOfMeshes; ++i )
    {
        int numVertices = [mesh numberOfMeshVertices:i];
        const GLKVector3* vertex = [mesh meshVertices:i];
        
        for( int j=0; j<numVertices; j+=sampleStep )
        {
            volumeCenter = GLKVector3Add(volumeCenter, vertex[j]);
            sampleCount++;
        }
    }
    
    if( sampleCount>0 )
        volumeCenter = GLKVector3DivideScalar(volumeCenter, sampleCount);
    
    else
        volumeCenter = GLKVector3MultiplyScalar(_slamState.volumeSizeInMeters, 0.5);
    
    [_meshViewController resetMeshCenter:volumeCenter];

    [self presentViewController:_meshViewNavigationController animated:YES completion:^{}];
}

- (void)enterCubePlacementState
{
    // Switch to the Scan button.
    self.scanButton.hidden = NO;
    self.doneButton.hidden = YES;
    self.resetButton.hidden = YES;
    
    // We'll enable the button only after we get some initial pose.
    self.scanButton.enabled = NO;
    
    // Cannot be lost in cube placement mode.
    _trackingLostLabel.hidden = YES;
    
    //[self setColorCameraParametersForInit];
    
    _captureSession.properties = STCaptureSessionPropertiesSetColorCameraAutoExposureISOAndWhiteBalance();
    
    _slamState.scannerState = ScannerStateCubePlacement;
 
    // Restore dynamic options UI state, as we may be coming back from scanning state, where they were all disabled.
    [self syncUIfromDynamicOptions];
    
    [self updateIdleTimer];
}

- (void)enterScanningState
{
    // This can happen if the UI did not get updated quickly enough.
    if (!_slamState.cameraPoseInitializer.lastOutput.hasValidPose)
    {
        NSLog(@"Warning: not accepting to enter into scanning state since the initial pose is not valid.");
        return;
    }
    
    // Switch to the Done button.
    self.scanButton.hidden = YES;
    self.doneButton.hidden = NO;
    self.resetButton.hidden = NO;

    // Prepare the mapper for the new scan.
    [self setupMapper];
    
    _slamState.tracker.initialCameraPose = _slamState.initialDepthCameraPose;
    
    // We will lock exposure during scanning to ensure better coloring.
    _captureSession.properties = STCaptureSessionPropertiesLockAllColorCameraPropertiesToCurrent();

    _slamState.scannerState = ScannerStateScanning;
    
    // Temporarily disable options while we're scanning.
    self.enableRGBDTrackerSwitch.enabled = NO;
    self.enableHighResolutionColorSwitch.enabled = NO;
    self.enableNewMapperSwitch.enabled = NO;
    self.enableHighResMappingSwitch.enabled = NO;
    self.enableImprovedTrackerSwitch.enabled = NO;
}

- (void)enterViewingState
{
    // Cannot be lost in view mode.
    [self hideTrackingErrorMessage];
    
    _appStatus.statusMessageDisabled = true;
    [self updateAppStatusMessage];
    
    // Hide the Scan/Done/Reset button.
    self.scanButton.hidden = YES;
    self.doneButton.hidden = YES;
    self.resetButton.hidden = YES;
    
    [_sensorController stopStreaming];

    //if (_useColorCamera)
    //    [self stopColorCamera];
    
    [_slamState.mapper finalizeTriangleMesh];
    
    STMesh *mesh = [_slamState.scene lockAndGetSceneMesh];
    [self presentMeshViewer:mesh];
    
    [_slamState.scene unlockSceneMesh];
    
    _slamState.scannerState = ScannerStateViewing;
    
    [self updateIdleTimer];
}

#pragma mark -  Structure Sensor Management

-(BOOL)currentStateNeedsSensor
{
    switch (_slamState.scannerState)
    {
        // Initialization and scanning need the sensor.
        case ScannerStateCubePlacement:
        case ScannerStateScanning:
            return TRUE;
            
        // Other states don't need the sensor.
        default:
            return FALSE;
    }
}

#pragma mark - IMU

- (void)setupIMU
{
    _lastGravity = GLKVector3Make (0,0,0);
    
    // 60 FPS is responsive enough for motion events.
    const float fps = 60.0;
    _motionManager = [[CMMotionManager alloc] init];
    _motionManager.accelerometerUpdateInterval = 1.0/fps;
    _motionManager.gyroUpdateInterval = 1.0/fps;
    
    // Limiting the concurrent ops to 1 is a simple way to force serial execution
    _imuQueue = [[NSOperationQueue alloc] init];
    [_imuQueue setMaxConcurrentOperationCount:1];
    
    __weak ViewController *weakSelf = self;
    CMDeviceMotionHandler dmHandler = ^(CMDeviceMotion *motion, NSError *error)
    {
        // Could be nil if the self is released before the callback happens.
        if (weakSelf) {
            [weakSelf processDeviceMotion:motion withError:error];
        }
    };
    
    [_motionManager startDeviceMotionUpdatesToQueue:_imuQueue withHandler:dmHandler];
}

- (void)processDeviceMotion:(CMDeviceMotion *)motion withError:(NSError *)error
{
    if (_slamState.scannerState == ScannerStateCubePlacement)
    {
        // Update our gravity vector, it will be used by the cube placement initializer.
        _lastGravity = GLKVector3Make (motion.gravity.x, motion.gravity.y, motion.gravity.z);
    }
    
    if (_slamState.scannerState == ScannerStateCubePlacement || _slamState.scannerState == ScannerStateScanning)
    {
        // The tracker is more robust to fast moves if we feed it with motion data.
        [_slamState.tracker updateCameraPoseWithMotion:motion];
    }
}

#pragma mark - UI Callbacks

- (IBAction)enableRGBDTrackerSwitchChanged:(UISwitch*)sender
{
    _dynamicOptions.depthAndColorTrackerIsOn = self.enableRGBDTrackerSwitch.on;

    [self onSLAMOptionsChanged]; // will call UI sync
}

- (IBAction)enableHighResolutionColorSwitchChanged:(UISwitch*)sender
{
    _dynamicOptions.highResColoring = self.enableHighResolutionColorSwitch.on;
    [self setupCaptureSession];
    _captureSession.streamingEnabled = YES;
    [self onSLAMOptionsChanged]; // will call UI sync
}

- (IBAction)enableImprovedTrackerSwitch:(UISwitch*)sender {
    _dynamicOptions.improvedTrackingIsOn = self.enableImprovedTrackerSwitch.on;

    [self onSLAMOptionsChanged];
}

- (IBAction)enableNewMapperSwitchChanged:(UISwitch*)sender
{
    _dynamicOptions.newMapperIsOn = self.enableNewMapperSwitch.on;
    [self onSLAMOptionsChanged]; // will call UI sync
}

- (IBAction)enableHighResMappingSwitchChanged:(UISwitch*)sender
{
    _dynamicOptions.highResMapping = self.enableHighResMappingSwitch.on;
    [self onSLAMOptionsChanged]; // will call UI sync
}

- (void)onSLAMOptionsChanged
{
    [self syncUIfromDynamicOptions];
    
    // A full reset to force a creation of a new tracker.
    [self resetSLAM];
    [self clearSLAM];
    [self setupSLAM];
    
    // Restore the volume size cleared by the full reset.
    [self adjustVolumeSize:_slamState.volumeSizeInMeters];
}

- (void)adjustVolumeSize:(GLKVector3)volumeSize
{
    // Make sure the volume size remains between 10 centimeters and 3 meters.
    volumeSize.x = keepInRange (volumeSize.x, 0.1, 3.f);
    volumeSize.y = keepInRange (volumeSize.y, 0.1, 3.f);
    volumeSize.z = keepInRange (volumeSize.z, 0.1, 3.f);
    
    _slamState.volumeSizeInMeters = volumeSize;
    
    _slamState.cameraPoseInitializer.volumeSizeInMeters = volumeSize;
    [_display.cubeRenderer adjustCubeSize:_slamState.volumeSizeInMeters];
}

- (IBAction)scanButtonPressed:(id)sender
{
    bool success = [_captureSession.occWriter startWriting:@"[AppDocuments]/Scanner" appendDateAndExtension:YES];
    if (!success)
    {
        NSLog(@"Could not properly start OCC writer.");
    }

    [self enterScanningState];
}

- (IBAction)resetButtonPressed:(id)sender
{
    [self resetSLAM];
}

- (IBAction)doneButtonPressed:(id)sender
{
    [self enterViewingState];
}

- (IBAction)optionsButtonPressed:(id)sender
{
    [self.enableNewTrackerView setHidden:![self.enableNewTrackerView isHidden]];
}

// Manages whether we can let the application sleep.
-(void)updateIdleTimer
{
    if ([self isStructureConnectedAndCharged] && [self currentStateNeedsSensor])
    {
        // Do not let the application sleep if we are currently using the sensor data.
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    }
    else
    {
        // Let the application sleep if we are only viewing the mesh or if no sensors are connected.
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    }
}

- (void)showTrackingMessage:(NSString*)message
{
    self.trackingLostLabel.text = message;
    self.trackingLostLabel.hidden = NO;
}

- (void)hideTrackingErrorMessage
{
    self.trackingLostLabel.hidden = YES;
}

- (void)showAppStatusMessage:(NSString *)msg
{
    _appStatus.needsDisplayOfStatusMessage = true;
    [self.view.layer removeAllAnimations];
    
    [self.appStatusMessageLabel setText:msg];
    [self.appStatusMessageLabel setHidden:NO];
    
    // Progressively show the message label.
    self.enableNewTrackerView.userInteractionEnabled = false;
    self.optionsButton.userInteractionEnabled = false;

    [UIView animateWithDuration:0.5f animations:^{
        self.appStatusMessageLabel.alpha = 1.0f;
    }completion:nil];
}

- (void)hideAppStatusMessage
{
    [self.view.layer removeAllAnimations];
    
    self.enableNewTrackerView.userInteractionEnabled = true;
    self.optionsButton.userInteractionEnabled = true;

    __weak ViewController *weakSelf = self;
    [UIView animateWithDuration:0.5f
                     animations:^{
                         weakSelf.appStatusMessageLabel.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         // If nobody called showAppStatusMessage before the end of the animation, do not hide it.
                         if (!self->_appStatus.needsDisplayOfStatusMessage)
                         {
                             // Could be nil if the self is released before the callback happens.
                             if (weakSelf) {
                                 [weakSelf.appStatusMessageLabel setHidden:YES];
                             }
                         }
     }];
}

-(void)updateAppStatusMessage
{
    STCaptureSessionUserInstruction userInstructions = _captureSession.userInstructions;
    
    bool needToConnectSensor = userInstructions & STCaptureSessionUserInstructionNeedToConnectSensor;
    bool needToChargeSensor = userInstructions & STCaptureSessionUserInstructionNeedToChargeSensor;
    bool needToAuthorizeColorCamera = userInstructions & STCaptureSessionUserInstructionNeedToAuthorizeColorCamera;
    
    // If you don't want to display the overlay message when an approximate calibration
    // is available use `_captureSession.calibrationType >= STCalibrationTypeApproximate`
    bool needToRunCalibrator = userInstructions & STCaptureSessionUserInstructionNeedToRunCalibrator;
    
    if (needToConnectSensor)
    {
        [self showAppStatusMessage:_appStatus.pleaseConnectSensorMessage];
        return;
    }
    
    if (needToChargeSensor)
    {
        [self showAppStatusMessage:_appStatus.pleaseChargeSensorMessage];
        return;
    }
    
    if (needToRunCalibrator)
    {
        bool hasApproximateCalibration = _captureSession.calibrationType >= STCalibrationTypeApproximate;
        self.scanButton.enabled = hasApproximateCalibration;
        CGRect screenBounds = [[UIScreen mainScreen] bounds];

        int offset = 128;
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        {
            offset = 50;
        }

        _calibrationOverlay = [CalibrationOverlay calibrationOverlaySubviewOf:self.view
                                                                     atCenter:CGPointMake(screenBounds.size.width / 2,
                                                                                          screenBounds.size.height - offset)
                                                    hasApproximateCalibration:hasApproximateCalibration];
    }
    else
    {
        if (_calibrationOverlay) { _calibrationOverlay.hidden = YES; }
    }
    
    // Color camera permission issues.
    if (needToAuthorizeColorCamera)
    {
        [self showAppStatusMessage:_appStatus.needColorCameraAccessMessage];
        return;
    }
    
    // If we reach this point, no status to show.
    [self hideAppStatusMessage];
}

- (void)pinchGesture:(UIPinchGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
    {
        if (_slamState.scannerState == ScannerStateCubePlacement)
        {
            _volumeScale.initialPinchScale = _volumeScale.currentScale / [gestureRecognizer scale];
        }
    }
    else if ([gestureRecognizer state] == UIGestureRecognizerStateChanged)
    {
        if(_slamState.scannerState == ScannerStateCubePlacement)
        {
            // In some special conditions the gesture recognizer can send a zero initial scale.
            if (!isnan (_volumeScale.initialPinchScale))
            {
                _volumeScale.currentScale = [gestureRecognizer scale] * _volumeScale.initialPinchScale;
                
                // Don't let our scale multiplier become absurd
                _volumeScale.currentScale = keepInRange(_volumeScale.currentScale, 0.01, 1000.f);
                
                GLKVector3 newVolumeSize = GLKVector3MultiplyScalar(_options.initVolumeSizeInMeters, _volumeScale.currentScale);
                
                [self adjustVolumeSize:newVolumeSize];
            }
        }
    }
}

#pragma mark - MeshViewController delegates

- (void)meshViewWillDismiss
{
    // If we are running colorize work, we should cancel it.
    if (_naiveColorizeTask)
    {
        [_naiveColorizeTask cancel];
        _naiveColorizeTask = nil;
    }
    if (_enhancedColorizeTask)
    {
        [_enhancedColorizeTask cancel];
        _enhancedColorizeTask = nil;
    }
    
    [_meshViewController hideMeshViewerMessage];
}

- (void)meshViewDidDismiss
{
    _appStatus.statusMessageDisabled = false;
    [self updateAppStatusMessage];
    
    // Reset the tracker, mapper, etc.
    [self resetSLAM];
    [self enterCubePlacementState];
}

- (void)backgroundTask:(STBackgroundTask *)sender didUpdateProgress:(double)progress
{
    if (sender == _naiveColorizeTask)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_meshViewController showMeshViewerMessage:[NSString stringWithFormat:@"Processing: % 3d%%", int(progress*20)]];
        });
    }
    else if (sender == _enhancedColorizeTask)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_meshViewController showMeshViewerMessage:[NSString stringWithFormat:@"Processing: % 3d%%", int(progress*80)+20]];
        });
    }
}

- (BOOL)meshViewDidRequestColorizing:(STMesh*)mesh previewCompletionHandler:(void (^)())previewCompletionHandler enhancedCompletionHandler:(void (^)())enhancedCompletionHandler
{
    if (_naiveColorizeTask) // already one running?
    {
        NSLog(@"Already one colorizing task running!");
        return FALSE;
    }

    _naiveColorizeTask = [STColorizer
                     newColorizeTaskWithMesh:mesh
                     scene:_slamState.scene
                     keyframes:[_slamState.keyFrameManager getKeyFrames]
                     completionHandler: ^(NSError *error)
                     {
                         if (error != nil) {
                             NSLog(@"Error during colorizing: %@", [error localizedDescription]);
                         }
                         else
                         {
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 previewCompletionHandler();
                                 self->_meshViewController.mesh = mesh;
                                 [self performEnhancedColorize:(STMesh*)mesh enhancedCompletionHandler:enhancedCompletionHandler];
                             });
                             self->_naiveColorizeTask = nil;
                         }
                     }
                     options:@{kSTColorizerTypeKey: @(STColorizerPerVertex),
                               kSTColorizerPrioritizeFirstFrameColorKey: @(_options.prioritizeFirstFrameColor)}
                     error:nil];
    
    if (_naiveColorizeTask)
    {
        // Release the tracking and mapping resources. It will not be possible to resume a scan after this point
        [_slamState.mapper reset];
        [_slamState.tracker reset];
    
        _naiveColorizeTask.delegate = self;
        [_naiveColorizeTask start];
        return TRUE;
    }
    
    return FALSE;
}

- (void)performEnhancedColorize:(STMesh*)mesh enhancedCompletionHandler:(void (^)())enhancedCompletionHandler
{
    _enhancedColorizeTask =[STColorizer
       newColorizeTaskWithMesh:mesh
       scene:_slamState.scene
       keyframes:[_slamState.keyFrameManager getKeyFrames]
       completionHandler: ^(NSError *error)
       {
           if (error != nil) {
               NSLog(@"Error during colorizing: %@", [error localizedDescription]);
           }
           else
           {
               dispatch_async(dispatch_get_main_queue(), ^{
                   enhancedCompletionHandler();
                   self->_meshViewController.mesh = mesh;
               });
               self->_enhancedColorizeTask = nil;
           }
       }
       options:@{kSTColorizerTypeKey: @(STColorizerTextureMapForObject),
                 kSTColorizerPrioritizeFirstFrameColorKey: @(_options.prioritizeFirstFrameColor),
                 kSTColorizerQualityKey: @(_options.colorizerQuality),
                 kSTColorizerTargetNumberOfFacesKey: @(_options.colorizerTargetNumFaces)} // 20k faces is enough for most objects.
       error:nil];
    
    if (_enhancedColorizeTask)
    {
        // We don't need the keyframes anymore now that the final colorizing task was started.
        // Clearing it now gives a chance to early release the keyframe memory when the colorizer
        // stops needing them.
        [_slamState.keyFrameManager clear];
        
        _enhancedColorizeTask.delegate = self;
        [_enhancedColorizeTask start];
    }
}


- (void) respondToMemoryWarning
{
    switch( _slamState.scannerState )
    {
        case ScannerStateViewing:
        {
            // If we are running a colorizing task, abort it
            if( _enhancedColorizeTask != nil && !_slamState.showingMemoryWarning )
            {
                _slamState.showingMemoryWarning = true;
                
                // stop the task
                [_enhancedColorizeTask cancel];
                _enhancedColorizeTask = nil;
                
                // hide progress bar
                [_meshViewController hideMeshViewerMessage];
                
                UIAlertController *alertCtrl= [UIAlertController alertControllerWithTitle:@"Memory Low"
                                                                                  message:@"Colorizing was canceled."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action)
                                           {
                                               self->_slamState.showingMemoryWarning = false;
                                           }];
                
                [alertCtrl addAction:okAction];
                
                // show the alert in the meshViewController
                [_meshViewController presentViewController:alertCtrl animated:YES completion:nil];
            }
            
            break;
        }
        case ScannerStateScanning:
        {
            if( !_slamState.showingMemoryWarning )
            {
                _slamState.showingMemoryWarning = true;
                
                UIAlertController *alertCtrl= [UIAlertController alertControllerWithTitle:@"Memory Low"
                                                                                  message:@"Scanning will be stopped to avoid loss."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action)
                                           {
                                               self->_slamState.showingMemoryWarning = false;
                                               [self enterViewingState];
                                           }];
                
                
                [alertCtrl addAction:okAction];
                
                // show the alert
                [self presentViewController:alertCtrl animated:YES completion:nil];
            }
            
            break;
        }
        default:
        {
            // not much we can do here
        }
    }
}
@end
