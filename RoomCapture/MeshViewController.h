/*
  This file is part of the Structure SDK.
  Copyright © 2016 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>
#import <MessageUI/MFMailComposeViewController.h>
#import <Structure/StructureSLAM.h>
#import "EAGLView.h"
#import <CoreLocation/CoreLocation.h>
#import <AddressBook/AddressBook.h>
#import <QuartzCore/QuartzCore.h>

@protocol MeshViewDelegate <NSObject>
- (void)meshViewWillDismiss;
- (void)meshViewDidDismiss;
- (void)meshViewDidRequestRegularMesh;
- (void)meshViewDidRequestHoleFilling;
@end

@interface MeshViewController : UIViewController <UIGestureRecognizerDelegate, MFMailComposeViewControllerDelegate, CLLocationManagerDelegate>

@property (nonatomic, assign) id<MeshViewDelegate> delegate;

@property (nonatomic) BOOL needsDisplay; // force the view to redraw.
@property (strong,nonatomic) NSMutableArray *employeeInfoArray;
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) CLGeocoder *geocoder;
@property (strong, nonatomic) NSString *location, *latitude, *longlitude, *googleDriveFileName;
@property (strong, nonatomic) UIWindow *window;
@property (weak, nonatomic) IBOutlet UILabel *meshViewerMessageLabel;
@property (weak, nonatomic) IBOutlet UILabel *measurementGuideLabel;

@property (weak, nonatomic) IBOutlet UISwitch *topViewSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *XRaySwitch;
@property (weak, nonatomic) IBOutlet UISwitch *holeFillingSwitch;
@property (weak, nonatomic) IBOutlet UIButton *measurementButton;

+ (instancetype) viewController;

- (IBAction)measurementButtonClicked:(id)sender;
- (IBAction)topViewSwitchChanged:(id)sender;
- (IBAction)holeFillingSwitchChanged:(id)sender;
- (IBAction)XRaySwitchChanged:(id)sender;

- (void)showMeshViewerMessage:(UILabel*)label msg:(NSString *)msg;
- (void)hideMeshViewerMessage:(UILabel*)label;

- (void)uploadMesh:(STMesh *)meshRef;

- (void)setHorizontalFieldOfView:(float)fovXRadians aspectRatio:(float)aspectRatio;
- (void)setCameraPose:(GLKMatrix4)pose;
- (void)getMeasuredObjectNameForValue:(NSString *) value whenFinishedMeasurementNo:(NSInteger) doneButtonNumber;

@end
