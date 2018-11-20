/*
  This file is part of the Structure SDK.
  Copyright © 2016 Occipital, Inc. All rights reserved.
  http://structure.io
*/

// StructureStatusUI contains all the UI for Structure Sensor status feedback,
// as required as part of the Structure Sensor App Submission process.
// This is:
//   - battery status
//   - calibration overlay
//   - camera allowance setting
//   - structure connected status/first time "get structure" message.
//
// A developer may copy this collection of files into each new structure app,
// and write code in the parent view controller to instantiate and send it events.
//
// The only modification users may want to do is change the default location of where
// the UI elements are placed, but that's just changing the hard-coded numbers in the frame.

#import "StructureStatusUI.h"
#import "UIView+AnimateHidden.h"

#import "CalibrationOverlay.h"
#import "LocalStoreHelper.h"

@interface StructureStatusUI ()
{
    NSTimer *_updateBatteryDisplayTimer;
    STCaptureSession* _captureSession;
    
    UIViewController *_parentViewController;
    
    // UI Feedback elements
    UIImageView *_sensorBatteryIcon;
    UILabel *_messageLabel;
    CalibrationOverlay* _calibrationOverlay;
    UIView *_getStructureView;
}
@end

#define NOTIFICATION_X 664
#define NOTIFICATION_Y 40
#define CAMERA_ACCESS_ALERT_TAG 102491

// ALWAYS_SHOW_EVERYTHING is useful for debugging StructureStatusUI without the sensor being in the state so everything is shown.
const bool ALWAYS_SHOW_EVERYTHING = NO;

@implementation StructureStatusUI

+ (void)applyUIStyle:(UIView*)view
{
    [view setBackgroundColor:[UIColor colorWithRed:0 green:0 blue:0 alpha:0.9]];
    
    view.layer.cornerRadius = 10.0f;
    
    UIColor *borderColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    [view.layer setBorderColor:borderColor.CGColor];
    [view.layer setBorderWidth:1.0f];
}

- (void)cameraAccessDenied
{
    NSString *alertTitle = @"Camera Access Blocked";
    NSString *alertText = @"Please turn on Camera and Photos access in Settings.";
    NSString *alertButtonTitle = @"Open Settings";
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:alertText
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:alertButtonTitle
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
        }];
    
    [alert addAction:defaultAction];
    [_parentViewController presentViewController:alert animated:YES completion:nil];

}

- (void)cameraAccessGloballyRestricted
{
    NSString *alertTitle = @"Camera Access Restricted";
    NSString *alertText = @"Please turn off the Camera restriction in Settings → General → Restrictions.";
    NSString *alertButtonTitle = @"Open Settings";
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:alertText
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:alertButtonTitle
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {
                                                              [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                                                          }];
    
    [alert addAction:defaultAction];
    [_parentViewController presentViewController:alert animated:YES completion:nil];
    
}

- (BOOL)queryCameraAuthorizationStatusWithCompletionHandler:(void (^)(BOOL granted))handler
{
    AVCaptureDeviceDiscoverySession *captureDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
                                                                                                                            mediaType:AVMediaTypeVideo
                                                                                                                             position:AVCaptureDevicePositionBack];
    NSArray *captureDevices = [captureDeviceDiscoverySession devices];
    
    const NSUInteger numCameras = captureDevices.count;
    
    if (0 == numCameras)
    {
        [self cameraAccessGloballyRestricted];
        return NO; // This can happen even on devices that include a camera, when camera access is restricted globally.
    }

    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (authStatus != AVAuthorizationStatusAuthorized)
    {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:
         ^(BOOL granted) {
             // This block fires on a separate thread, so we need to ensure any actions here
             // are sent to the right place.
             dispatch_async(dispatch_get_main_queue(), ^(void) {
                 if (!granted)
                     [self cameraAccessDenied];
                 
                 if (handler != nil)
                     handler(granted);
             });
         }];
        
        return NO;
    }
    
    return YES;
}

# pragma mark - initialization

- (id)initInViewController:(UIViewController*)parentViewController
{
    _parentViewController = parentViewController;
    
    [self initBatteryIcon];
    [self initStructureMessageLabel];

    [self updateAppStatus];

    if (ALWAYS_SHOW_EVERYTHING)
    {
        [_calibrationOverlay setHidden:NO];
        [_sensorBatteryIcon setHidden:NO];
        [_getStructureView setHidden:NO];
        [_messageLabel setHidden:NO];
    }
    
    return self;
}

- (void)setCaptureSession:(STCaptureSession*)captureSession
{
    _captureSession = captureSession;
}

- (void)initBatteryIcon
{
    const float iconWidth = 60;
    
    CGRect imageFrame = CGRectMake(_parentViewController.view.frame.size.width - (iconWidth + 20),
                                    0,
                                    iconWidth,
                                    35);
    _sensorBatteryIcon = [[UIImageView alloc] initWithFrame: imageFrame];
    _sensorBatteryIcon.contentMode = UIViewContentModeScaleAspectFit;
    _sensorBatteryIcon.image = [UIImage imageNamed:@"SensorBattery"];
    _sensorBatteryIcon.clipsToBounds = YES;
    [_parentViewController.view addSubview:_sensorBatteryIcon];
    
    [_sensorBatteryIcon setHidden:YES];
}

- (void)startBatteryTimer
{
    // Create Battery Timers (First update, then 5s refresh):
    [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(updateBattery) userInfo:nil repeats:NO];
    if(_updateBatteryDisplayTimer)
    {
        [_updateBatteryDisplayTimer invalidate];
        _updateBatteryDisplayTimer = nil;
    }
    _updateBatteryDisplayTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(updateBattery) userInfo:nil repeats:YES];
}

- (void)stopBatteryTimer
{
    [_updateBatteryDisplayTimer invalidate];
    _updateBatteryDisplayTimer = nil;
}

- (void)initStructureMessageLabel
{
    // Fully transparent message label, initially.
    CGRect frame = CGRectMake(0, 200, 1024, 36);
    _messageLabel = [[UILabel alloc] initWithFrame:frame];
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _messageLabel.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.3];
    
    _messageLabel.hidden = YES;
    [_parentViewController.view addSubview:_messageLabel];

    [_parentViewController.view addConstraint:[NSLayoutConstraint
                                               constraintWithItem:_parentViewController.view
                                               attribute:NSLayoutAttributeCenterY
                                               relatedBy:NSLayoutRelationEqual
                                               toItem:_messageLabel
                                               attribute:NSLayoutAttributeCenterY
                                               multiplier:1.0
                                               constant:0.0]];

    [_parentViewController.view addConstraints:[NSLayoutConstraint
                                                constraintsWithVisualFormat:@"H:|[view]|"
                                                options:0
                                                metrics:nil
                                                views:@{@"view" : _messageLabel}]];
}

-(NSMutableAttributedString*) appMessageWithAttributedText:(NSString*)text range:(NSRange)range
{
    const CGFloat fontSize = 30;
    UIFont *lightFont = [UIFont fontWithName:@"OpenSans-Light" size:fontSize];
    UIFont *boldFont = [UIFont fontWithName:@"OpenSans-Semibold" size:fontSize];
    UIColor *foregroundColor = [UIColor whiteColor];
    
    // Create the attributes
    NSDictionary *attrs = @{NSFontAttributeName: lightFont,
                           NSForegroundColorAttributeName: foregroundColor};
    NSDictionary *subAttrs = @{NSFontAttributeName: boldFont,
                              NSForegroundColorAttributeName: foregroundColor};
    
    NSMutableAttributedString *attributedText =
    [[NSMutableAttributedString alloc] initWithString:text
                                           attributes:attrs];
    [attributedText setAttributes:subAttrs range:range];
    
    return attributedText;
}

- (void)showStatusMessage:(NSMutableAttributedString*)attributedText
{
    [_messageLabel setAttributedText:attributedText];
    
    // If we have no record of the sensor connecting, must display "get sensor" view
    [_messageLabel setHidden:NO animated:YES animationDuration:0.3];
}

- (void) hideStatusMessage
{
    //we interpret this message as meaning the sensor is properly connected.
    if (!ALWAYS_SHOW_EVERYTHING)
    {
        [_messageLabel setHidden:YES animated:YES animationDuration:0.3];
    }
}

# pragma mark - UI update based on STCaptureSession information

- (void) updateAppStatus
{
    STCaptureSessionUserInstruction userInstructions = _captureSession.userInstructions;
    _calibrationOverlay.hidden = YES;

    if (userInstructions & STCaptureSessionUserInstructionNeedToConnectSensor)
    {
        NSMutableAttributedString* attributedText = [self appMessageWithAttributedText:@"Please connect Structure Sensor." range:NSMakeRange(15, 16)];\
        [self showStatusMessage:attributedText];
        return;
    }

    
    if (userInstructions & STCaptureSessionUserInstructionNeedToChargeSensor)
    {
        NSMutableAttributedString* attributedText = [self appMessageWithAttributedText:@"Please charge Structure Sensor." range:NSMakeRange(14,16)];
        [self showStatusMessage:attributedText];
        return;
    }

    if (userInstructions & STCaptureSessionUserInstructionNeedToAuthorizeColorCamera)
    {
        NSMutableAttributedString* attributedText = [self appMessageWithAttributedText:@"Please provide color camera access permission." range:NSMakeRange(15, 16)];\
        [self showStatusMessage:attributedText];
        return;
    }

    if (userInstructions & STCaptureSessionUserInstructionNeedToRunCalibrator)
    {
        bool hasApproximateCalibration = _captureSession.calibrationType >= STCalibrationTypeApproximate;

        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        _calibrationOverlay = [CalibrationOverlay calibrationOverlaySubviewOf:_parentViewController.view
                                                                     atCenter:CGPointMake(screenBounds.size.width / 2,
                                                                                          screenBounds.size.height - 128)
                                                    hasApproximateCalibration:hasApproximateCalibration];
        [StructureStatusUI applyUIStyle:_calibrationOverlay];
        _calibrationOverlay.hidden = NO;
    }
    else
    {
        if (_calibrationOverlay) { _calibrationOverlay.hidden = YES; }
    }

    [self hideStatusMessage];
}

# pragma mark - update functions

- (void) updateBattery
{
    if (!_captureSession)
        return;
    
    if(_captureSession.sensorMode == STCaptureSessionSensorModeNotConnected) {
        dNSLog(@"[Error] Why are we calling updateBattery if sensor is not connected?");
        return;
    }
    
    NSInteger percentage = _captureSession.sensorBatteryLevel;
    [_sensorBatteryIcon setHidden: percentage > 5 ];
}

@end
