/*
 This file is part of the Structure SDK.
 Copyright © 2016 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#define HAS_LIBCXX
#import <Structure/Structure.h>
#import <Structure/STCaptureSession.h>

#import "CalibrationOverlay.h"
#import "MeshViewController.h"

#include <vector>

struct Options
{
    // The initial scanning volume size will be 6.0 x 4.0 x 6.0 meters
    GLKVector3 initialVolumeSizeInMeters = GLKVector3Make (6.f, 4.f, 6.f);
    
    // Resolution for the initialVolumeSizeInMeters. Will get scaled if we change the volume size.
    const float initialVolumeResolutionInMeters = 0.05; // coarse, but gives good performance
    
    // The minimal vertical volume size is fixed, since the ceiling is not likely to be very low.
    float minVerticalVolumeSize = 3.f;
        
    // The maximum of keyframes for keyFrameManager. More won't fit in a single OpenGL texture.
    int maxNumKeyframes = 48;
    
    // Take a new keyframe in the rotation difference is higher than 20 degrees.
    float maxKeyFrameRotation = 20.0f * (M_PI / 180.f);
    
    // Take a new keyframe if the translation difference is higher than 30 cm.
    float maxKeyFrameTranslation = 0.3;
    
    // Threshold to consider that the rotation motion was small enough for a frame to be accepted
    // as a keyframe. This avoids capturing keyframes with strong motion blur / rolling shutter.
    float maxKeyframeRotationSpeedInDegreesPerSecond = 1.f;
    
    // Threshold to pop a warning to the user if he's exploring too far away since this demo is optimized
    // for a rotation around oneself.
    float maxDistanceFromInitialPositionInMeters = 1.f;
    
    // Fixed focus position of the color camera.
    float colorCameraLensPosition = 0.75f; // 0.75 gives pretty good focus for a room scale.
    
    // Whether we should use depth aligned to the color viewpoint when Structure Sensor was calibrated.
    // This setting may get overwritten to false if no color camera can be used.
    bool useHardwareRegisteredDepth = false;
    
    // Whether to enable an expensive per-frame depth accuracy refinement.
    // Note: this option requires useHardwareRegisteredDepth to be set to false.
    const bool applyExpensiveCorrectionToDepth = true;
};

enum RoomCaptureState
{
    // Defining the volume to scan
    RoomCaptureStatePoseInitialization = 0,
    
    // Scanning
    RoomCaptureStateScanning,
    
    // Finalizing the mesh
    RoomCaptureStateFinalizing,
    
    // Visualizing the mesh
    RoomCaptureStateViewing,
    
    RoomCaptureStateNumStates
};

// SLAM-related members.
struct SlamData
{
    RoomCaptureState roomCaptureState = RoomCaptureStatePoseInitialization;
    bool initialized = false;
    
    NSTimeInterval prevFrameTimeStamp = -1.0;
    
    STScene *scene = NULL;
    STTracker *tracker = NULL;
    STMapper *mapper = NULL;
    STCameraPoseInitializer *cameraPoseInitializer = NULL;
    STKeyFrameManager *keyFrameManager = NULL;
    
    GLKVector3 volumeSizeInMeters = GLKVector3Make (NAN, NAN, NAN);
};

struct AppStatus
{
    NSString* const pleaseConnectSensorMessage = @"Please connect Structure Sensor.";
    NSString* const pleaseChargeSensorMessage = @"Please charge Structure Sensor.";
    
    NSString* const needColorCameraAccessMessage = @"This app requires camera access to capture rooms.\nAllow access by going to Settings → Privacy → Camera.";
    NSString* const needCalibratedColorCameraMessage = @"This app requires an iOS device with a supported bracket.";
    
    NSString* const finalizingMeshMessage = @"Finalizing model...";

    enum BackgroundProcessingStatus
    {
        BackgroundProcessingStatusIdle,
        BackgroundProcessingStatusFinalizing
    };

    BackgroundProcessingStatus backgroundProcessingStatus = BackgroundProcessingStatusIdle;
    
    // Whether there is currently a message to show.
    bool needsDisplayOfStatusMessage = false;
    
    // Flag to disable entirely status message display.
    bool statusMessageDisabled = false;
};

// Display related members.
struct DisplayData
{
    ~DisplayData ()
    {
        if (lumaTexture)
        {
            CFRelease (lumaTexture);
            lumaTexture = NULL;
        }
        
        if (chromaTexture)
        {
            CFRelease(chromaTexture);
            chromaTexture = NULL;
        }
        
        if (videoTextureCache)
        {
            CFRelease(videoTextureCache);
            videoTextureCache = NULL;
        }
    }
    
    // OpenGL context.
    EAGLContext *context = nil;
    
    // Intrinsics of the current frame to use with undistortion shader.
    STIntrinsics intrinsics;

    // OpenGL Texture reference for y images.
    CVOpenGLESTextureRef lumaTexture = NULL;
    
    // OpenGL Texture reference for color images.
    CVOpenGLESTextureRef chromaTexture = NULL;
    
    // OpenGL Texture cache for the color camera.
    CVOpenGLESTextureCacheRef videoTextureCache = NULL;
    
    // Shader to render a GL texture as a simple quad. YCbCr version.
    STGLTextureShaderYCbCr *yCbCrTextureShader = nil;
    
    // Shader to render a GL texture as a simple quad. RGBA version.
    STGLTextureShaderRGBA *rgbaTextureShader = nil;
    
    // Used during initialization to show which depth pixels lies in the scanning volume boundaries.
    std::vector<uint8_t> scanningVolumeFeedbackBuffer;
    GLuint scanningVolumeFeedbackTexture = -1;
    
    // OpenGL viewport.
    GLfloat viewport[4] = {0,0,0,0};
    
    // OpenGL projection matrix for the color camera.
    GLKMatrix4 colorCameraGLProjectionMatrix = GLKMatrix4Identity;
};

@interface ViewController : UIViewController <STBackgroundTaskDelegate, MeshViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, UIPopoverControllerDelegate, UIGestureRecognizerDelegate>
{
    Options _options;
    
    // Manages the app status messages.
    AppStatus _appStatus;
    
    DisplayData _display;
    SlamData _slamState;
    
    STMesh *_colorizedMesh;
    STMesh *_holeFilledMesh;
    
    // Most recent gravity vector from IMU.
    GLKVector3 _lastCoreMotionGravity;
    
    // Structure Sensor controller.backgroundProcessingStatus
    STCaptureSession* _captureSession;
    
    // Mesh viewer controllers.
    UINavigationController *_meshViewNavigationController;
    MeshViewController *_meshViewController;
    
    // IMU handling.
    CMMotionManager *_motionManager;
    NSOperationQueue *_imuQueue;
    
    // Handles on background tasks which may be running.
    STBackgroundTask* _holeFillingTask;
    STBackgroundTask* _colorizeTask;
    
    CalibrationOverlay* _calibrationOverlay;
}

@property (nonatomic, retain) AVCaptureSession *avCaptureSession;
@property (nonatomic, retain) AVCaptureDevice *videoDevice;

@property (weak, nonatomic) IBOutlet UILabel *appStatusMessageLabel;
@property (weak, nonatomic) IBOutlet UIButton *scanButton;
@property (weak, nonatomic) IBOutlet UIButton *resetButton;
@property (weak, nonatomic) IBOutlet UIButton *doneButton;
@property (weak, nonatomic) IBOutlet UILabel *trackingMessageLabel;
@property (weak, nonatomic) IBOutlet UILabel *roomSizeLabel;
@property (weak, nonatomic) IBOutlet UISlider *roomSizeSlider;

+ (instancetype) viewController;

- (IBAction)roomSizeSliderValueChanged:(id)sender;
- (IBAction)scanButtonPressed:(id)sender;
- (IBAction)resetButtonPressed:(id)sender;
- (IBAction)doneButtonPressed:(id)sender;
- (IBAction)roomSizeSliderTouchDown:(id)sender;
- (IBAction)roomSizeSliderTouchUpInside:(id)sender;
- (IBAction)roomSizeSliderTouchUpOutside:(id)sender;

- (void)enterPoseInitializationState;
- (void)enterScanningState;
- (void)enterViewingState;
- (void)adjustVolumeSize:(GLKVector3)volumeSize;
- (void)updateAppStatusMessage;
- (BOOL)currentStateNeedsSensor;
- (void)updateIdleTimer;
- (void)showTrackingMessage:(NSString*)message;
- (void)hideTrackingErrorMessage;
- (void)processDeviceMotion:(CMDeviceMotion *)motion withError:(NSError *)error;

@end
