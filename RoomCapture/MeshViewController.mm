/*
 This file is part of the Structure SDK.
 Copyright © 2016 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "MeshViewController.h"
#import "MeshRenderer.h"
#import "GraphicsRenderer.h"
#import "ViewpointController.h"
#import "Joystick.h"
#import "CustomUIKitStyles.h"
#import "TTOpenInAppActivity.h"
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <Photos/Photos.h>
#include <vector>

// Local Helper Functions
namespace
{
    void saveJpegFromRGBABuffer(const char* filename, unsigned char* src_buffer, int width, int height)
    {
        FILE *file = fopen(filename, "w");
        if(!file)
            return;
        
        CGColorSpaceRef colorSpace;
        CGImageAlphaInfo alphaInfo;
        CGContextRef context;
        
        colorSpace = CGColorSpaceCreateDeviceRGB();
        alphaInfo = kCGImageAlphaNoneSkipLast;
        context = CGBitmapContextCreate(src_buffer, width, height, 8, width * 4, colorSpace, alphaInfo);
        CGImageRef rgbImage = CGBitmapContextCreateImage(context);
        
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        CFMutableDataRef jpgData = CFDataCreateMutable(NULL, 0);
        
        CGImageDestinationRef imageDest = CGImageDestinationCreateWithData(jpgData, CFSTR("public.jpeg"), 1, NULL);
        CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault, // our empty IOSurface properties dictionary
                                                     NULL,
                                                     NULL,
                                                     0,
                                                     &kCFTypeDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
        CGImageDestinationAddImage(imageDest, rgbImage, (CFDictionaryRef)options);
        CGImageDestinationFinalize(imageDest);
        CFRelease(imageDest);
        CFRelease(options);
        CGImageRelease(rgbImage);
        
        fwrite(CFDataGetBytePtr(jpgData), 1, CFDataGetLength(jpgData), file);
        fclose(file);
        CFRelease(jpgData);
    }
    
}

enum MeasurementState {
    Measurement_Clear,
    Measurement_Point1,
    Measurement_Point2,
    // Rafay editing start
     Measurement_Point3,
     Measurement_Point4,
     Measurement_Point5,
     Measurement_Point6,
    // Rafay editing close
    Measurement_Done1,
    Measurement_Done2,
    Measurement_Done3
};

@interface MeshViewController ()
{
    CADisplayLink *_displayLink;
    MeshRenderer *_meshRenderer;
    GraphicsRenderer *_graphicsRenderer1;
    GraphicsRenderer *_graphicsRenderer2;
    GraphicsRenderer *_graphicsRenderer3;
    ViewpointController *_viewpointController;
    
    Joystick *_translationJoystick;
    
    GLKMatrix4 _cameraPoseBeforeUserInteractions;
    float _cameraFovBeforeUserInteractions;
    float _cameraAspectRatioBeforeUserInteractions;
    
    UILabel *_ruler1Text;
    UILabel *_ruler2Text;
    UILabel *_ruler3Text;
    UIImageView * _circle1;
    UIImageView * _circle2;
    // Rafay editing start
    UIImageView * _circle3;
    UIImageView * _circle4;
    UIImageView * _circle5;
    UIImageView * _circle6;
    // Rafay editing close
    
    MeasurementState _measurementState;
    GLKVector3 _pt1;
    GLKVector3 _pt2;
    // Rafay editing start
    GLKVector3 _pt3;
    GLKVector3 _pt4;
    GLKVector3 _pt5;
    GLKVector3 _pt6;
    // Rafay editing close
}

@property STMesh *meshRef;

@property MFMailComposeViewController *mailViewController;

@end

#pragma mark - Initialization

@implementation MeshViewController

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil
{
    
    self.employeeInfoArray  = [[NSMutableArray alloc]initWithCapacity:0];
    // Initialize C++ members.
    _meshRenderer = 0;
    _graphicsRenderer1 = 0;
    _graphicsRenderer2 = 0;
    _graphicsRenderer3 = 0;
    _viewpointController = 0;
    
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(dismissView)];
        
        self.navigationItem.leftBarButtonItem = backButton;
        
        UIBarButtonItem *emailButton = [[UIBarButtonItem alloc] initWithTitle:@"Email"
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(emailMesh)];
        self.navigationItem.rightBarButtonItem = emailButton;
        
        UIBarButtonItem *screenshotButton = [[UIBarButtonItem alloc] initWithTitle:@"Send Measurement"
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                            action:@selector(createCSV:)];
        self.navigationItem.rightBarButtonItem = screenshotButton;
        
        self.title = @"Structure Sensor Room Capture";
        
        // Initialize Joystick.
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        {
            CGRect joystickFrame = CGRectMake(50, 230, 50, 50);
            _translationJoystick = [[Joystick alloc] initWithFrame:joystickFrame
                                                   backgroundImage:@"outerCircle-iphone.png"
                                                     joystickImage:@"innerCircle-iphone.png"];
        }
        else
        {
            const float joystickFrameSize = self.view.frame.size.height * 0.4;
            CGRect joystickFrame = CGRectMake(0, self.view.frame.size.height-joystickFrameSize, joystickFrameSize, joystickFrameSize);
            _translationJoystick = [[Joystick alloc] initWithFrame:joystickFrame
                                                   backgroundImage:@"outerCircle.png"
                                                     joystickImage:@"innerCircle.png"];
        }
        
        [self.view addSubview:_translationJoystick.view];

        [self.measurementButton applyCustomStyleWithBackgroundColor:blueButtonColorWithAlpha];
        [self.measurementGuideLabel applyCustomStyleWithBackgroundColor:blackLabelColorWithLightAlpha];
        
        _ruler1Text = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
        [_ruler1Text applyCustomStyleWithBackgroundColor:blackLabelColorWithAlpha];
        
        _ruler1Text.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:_ruler1Text];
        [self.view sendSubviewToBack:_ruler1Text];
        
        _ruler2Text = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
        [_ruler2Text applyCustomStyleWithBackgroundColor:blackLabelColorWithAlpha];
        
        _ruler2Text.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:_ruler2Text];
        [self.view sendSubviewToBack:_ruler2Text];
        
        _ruler3Text = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
        [_ruler3Text applyCustomStyleWithBackgroundColor:blackLabelColorWithAlpha];
        
        _ruler3Text.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:_ruler3Text];
        [self.view sendSubviewToBack:_ruler3Text];
        
        _circle1 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        _circle2 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        
        _circle3 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        _circle4 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        _circle5 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        _circle6 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        
        CGRect frame = _circle1.frame;
        frame.size = CGSizeMake(50, 50);
        _circle1.frame = frame;
        _circle2.frame = frame;
        
        _circle3.frame = frame;
        _circle4.frame = frame;
        _circle5.frame = frame;
        _circle6.frame = frame;
        
        
        [self.view addSubview:_circle1];
        [self.view addSubview:_circle2];
        
        [self.view addSubview:_circle3];
        [self.view addSubview:_circle4];
        [self.view addSubview:_circle5];
        [self.view addSubview:_circle6];
        
        [self.view sendSubviewToBack:_circle1];
        [self.view sendSubviewToBack:_circle2];
        
        [self.view sendSubviewToBack:_circle3];
        [self.view sendSubviewToBack:_circle4];
        [self.view sendSubviewToBack:_circle5];
        [self.view sendSubviewToBack:_circle6];
       
        
    }
    
    return self;
}

+ (instancetype) viewController
{
    return [[MeshViewController alloc] initWithNibName:@"MeshView" bundle:nil];
}

-(void)dealloc
{
    delete _meshRenderer; _meshRenderer = 0;
    delete _graphicsRenderer1; _graphicsRenderer1 = 0;
    delete _graphicsRenderer2; _graphicsRenderer2 = 0;
    delete _graphicsRenderer3; _graphicsRenderer3 = 0;
    delete _viewpointController; _viewpointController = 0;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.meshViewerMessageLabel.alpha = 0.0;
    self.meshViewerMessageLabel.hidden = true;
    
    [self.meshViewerMessageLabel applyCustomStyleWithBackgroundColor:blackLabelColorWithLightAlpha];
    
    _meshRenderer = new MeshRenderer;
    _graphicsRenderer1 = new GraphicsRenderer(@"measurementTape.png");
    _graphicsRenderer2 = new GraphicsRenderer(@"measurementTape.png");
    _graphicsRenderer3 = new GraphicsRenderer(@"measurementTape.png");
    _viewpointController = new ViewpointController(self.view.frame.size.width, self.view.frame.size.height);
    
    [self setupGL];
    [self setupGestureRecognizer];
    
    self.location = [NSString new];
    self.latitude = [NSString new];
    self.longlitude = [NSString new];
    self.googleDriveFileName = [NSString new];
    self.geocoder = [[CLGeocoder alloc] init];
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.distanceFilter = kCLDistanceFilterNone;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)
        [self.locationManager requestWhenInUseAuthorization];
    
    [self.locationManager startUpdatingLocation];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (_displayLink)
    {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.needsDisplay = true;
    
    _viewpointController->reset();
    [self hideMeshViewerMessage:self.meshViewerMessageLabel];
    [_translationJoystick setEnabled:YES];
    [self.topViewSwitch setOn:NO];
    [self.holeFillingSwitch setEnabled:YES];
    [self.holeFillingSwitch setOn:false];
    [self.XRaySwitch setOn:false];
    
    [self enterMeasurementState:Measurement_Clear];
    
    _meshRenderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:@"Enter file name"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *submit = [UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {
                                                       
                                                       if (alert.textFields.count > 0) {
                                                           UITextField *textField = [alert.textFields firstObject];
                                                           self.googleDriveFileName = textField.text;
                                                       }
                                                       
                                                   }];
    
    [alert addAction:submit];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"File name"; // if needs
    }];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}


- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    CLLocation *location = [locations lastObject];
    self.latitude = [NSString stringWithFormat:@"%f", location.coordinate.latitude];
    self.longlitude = [NSString stringWithFormat:@"%f", location.coordinate.longitude];
    
    [self.geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        CLPlacemark *placemark = [placemarks lastObject];
        
        self.location = @"";
        if (placemark.name != NULL)
            self.location = placemark.name;
        if (placemark.thoroughfare != NULL)
            self.location = [NSString stringWithFormat:@"%@ %@",self.location,placemark.thoroughfare];
        if (placemark.subThoroughfare != NULL)
            self.location = [NSString stringWithFormat:@"%@ %@",self.location,placemark.subThoroughfare];
        if (placemark.locality != NULL)
            self.location = [NSString stringWithFormat:@"%@ %@",self.location,placemark.locality];
        if (placemark.country != NULL)
            self.location = [NSString stringWithFormat:@"%@ %@",self.location,placemark.country];
    
        // stopping locationManager from fetching again
        //[locationManager stopUpdatingLocation];
    }];
    
}


- (void)setupGestureRecognizer
{
    UIPinchGestureRecognizer *pinchScaleGesture = [[UIPinchGestureRecognizer alloc]
                                                   initWithTarget:self
                                                   action:@selector(pinchScaleGesture:)];
    [pinchScaleGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchScaleGesture];
    
    
    UIRotationGestureRecognizer *rotationGesture = [[UIRotationGestureRecognizer alloc]
                                                    initWithTarget:self
                                                    action:@selector(rotationGesture:)];
    [rotationGesture setDelegate:self];
    [self.view addGestureRecognizer:rotationGesture];  
    
    UITapGestureRecognizer *singleTapGesture = [[UITapGestureRecognizer alloc]
                                                initWithTarget:self
                                                action:@selector(singleTapGesture:)];
    singleTapGesture.numberOfTapsRequired = 1;
    
    [self.view addGestureRecognizer:singleTapGesture];
}

- (void)setupGL
{
    _meshRenderer->initializeGL();
    _graphicsRenderer1->initializeGL();
    _graphicsRenderer2->initializeGL();
    _graphicsRenderer3->initializeGL();
    
    NSAssert (glGetError() == 0, @"Unexpected GL error, could not initialize the MeshRenderer");
}

- (void)dismissView
{
    if ([self.delegate respondsToSelector:@selector(meshViewWillDismiss)])
        [self.delegate meshViewWillDismiss];
    
    // Make sure we clear the data we don't need.
    _meshRenderer->releaseGLBuffers();
    _meshRenderer->releaseGLTextures();
    
    [_displayLink invalidate];
    _displayLink = nil;
    
    self.meshRef = nil;
    
    [(EAGLView *)self.view setContext:nil];
    
    [self dismissViewControllerAnimated:YES completion:^{
        if([self.delegate respondsToSelector:@selector(meshViewDidDismiss)])
            [self.delegate meshViewDidDismiss];
    }];
}

#pragma mark - MeshViewer Camera and Mesh Setup

- (void)setHorizontalFieldOfView:(float)fovXRadians aspectRatio:(float)aspectRatio
{
    _viewpointController->setCameraPerspective(fovXRadians, aspectRatio);
    
    // Save them for later in case we need a screenshot.
    _cameraFovBeforeUserInteractions = fovXRadians;
    _cameraAspectRatioBeforeUserInteractions = aspectRatio;
}

- (void)setCameraPose:(GLKMatrix4)pose
{
    _viewpointController->reset();
    _viewpointController->setCameraPose(pose);
    _cameraPoseBeforeUserInteractions = pose;
}

- (void)uploadMesh:(STMesh *)meshRef
{
    self.meshRef = meshRef;
    _meshRenderer->uploadMesh(meshRef);
    self.needsDisplay = true;
}

#pragma mark - Email

- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [self.mailViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)savePreviewImage:(NSString*)screenshotPath
{
    const int width = 320;
    const int height = 240;
    
    GLint currentFrameBuffer;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFrameBuffer);
    
    // Create temp texture, framebuffer, renderbuffer
    glViewport(0, 0, width, height);
    
    // We are going to render the preview to a texture.
    GLuint outputTexture;
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &outputTexture);
    glBindTexture(GL_TEXTURE_2D, outputTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    
    // Create the offscreen framebuffers and attach the outputTexture to them.
    GLuint colorFrameBuffer, depthRenderBuffer;
    glGenFramebuffers(1, &colorFrameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, colorFrameBuffer);
    glGenRenderbuffers(1, &depthRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderBuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, outputTexture, 0);
    
    // Take the screenshot from the initial viewpoint, before user interactions.
    bool isInvertible = false;
    GLKMatrix4 modelViewMatrix = GLKMatrix4Invert(_cameraPoseBeforeUserInteractions, &isInvertible);
    NSAssert (isInvertible, @"Bad viewpoint.");
    GLKMatrix4 projectionMatrix = glProjectionMatrixFromPerspective(_cameraFovBeforeUserInteractions, _cameraAspectRatioBeforeUserInteractions);
    
    // Keep the current render mode
    MeshRenderer::RenderingMode previousRenderingMode = _meshRenderer->getRenderingMode();
    
    // Screenshot rendering mode, always use colors if possible.
    if ([self.meshRef hasPerVertexColors])
    {
        _meshRenderer->setRenderingMode( MeshRenderer::RenderingModePerVertexColor );
    }
    else if ([self.meshRef hasPerVertexUVTextureCoords] && [self.meshRef meshYCbCrTexture])
    {
        _meshRenderer->setRenderingMode( MeshRenderer::RenderingModeTextured );
    }
    else
    {
        _meshRenderer->setRenderingMode( MeshRenderer::RenderingModeLightedGray );
    }
    
    // Render the mesh at the given viewpoint.
    _meshRenderer->clear();
    _meshRenderer->render(projectionMatrix, modelViewMatrix);
    
    // back to current render mode
    _meshRenderer->setRenderingMode( previousRenderingMode );
    
    struct RgbaPixel { uint8_t rgba[4]; };
    std::vector<RgbaPixel> screenShotRgbaBuffer (width*height);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, screenShotRgbaBuffer.data());
    
    // We need to flip the vertice axis, because OpenGL reads out the buffer from the bottom.
    std::vector<RgbaPixel> rowBuffer (width);
    for (int h = 0; h < height/2; ++h)
    {
        RgbaPixel* screenShotDataTopRow    = screenShotRgbaBuffer.data() + h * width;
        RgbaPixel* screenShotDataBottomRow = screenShotRgbaBuffer.data() + (height - h - 1) * width;
        
        // Swap the top and bottom rows, using rowBuffer as a temporary placeholder.
        memcpy(rowBuffer.data(), screenShotDataTopRow, width * sizeof(RgbaPixel));
        memcpy(screenShotDataTopRow, screenShotDataBottomRow, width * sizeof (RgbaPixel));
        memcpy(screenShotDataBottomRow, rowBuffer.data(), width * sizeof (RgbaPixel));
    }
    
    saveJpegFromRGBABuffer([screenshotPath UTF8String], reinterpret_cast<uint8_t*>(screenShotRgbaBuffer.data()), width, height);
    
    glBindFramebuffer(GL_FRAMEBUFFER, currentFrameBuffer);
    
    // Release the rendering buffers.
    glDeleteTextures(1, &outputTexture);
    glDeleteFramebuffers(1, &colorFrameBuffer);
    glDeleteRenderbuffers(1, &depthRenderBuffer);
}

-(void)createCSV:(UIBarButtonItem *)sender
{
//    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
//        UIGraphicsBeginImageContextWithOptions(self.window.bounds.size, NO, [UIScreen mainScreen].scale);
//    }
//    else
//    {
//        UIGraphicsBeginImageContext(self.window.bounds.size);
//
//    }
//    [self.window.layer renderInContext:UIGraphicsGetCurrentContext()];
//    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
//    UIGraphicsEndImageContext();
//    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
//    NSData *imageData = UIImagePNGRepresentation(image);
//    if (imageData) {
//        [imageData writeToFile:@"screenshot.png" atomically:YES];
//    }
//    else
//    {
//        NSLog(@"error while taking screenshot");
//
//    }
//
    
    NSMutableString *csvString = [[NSMutableString alloc]initWithCapacity:0];
    [csvString appendString:@"名, 測定, ロケーション, 時間, 緯度, 経度   \n"];

    for (NSDictionary *dct in self.employeeInfoArray)
    {
        [csvString appendString:[NSString stringWithFormat:@"%@, %@, %@, %@, %@, %@\n",[dct valueForKey:@"ID"],[dct valueForKey:@"VALUE"],[dct valueForKey:@"LOCATION"],[dct valueForKey:@"TIME"],[dct valueForKey:@"LATITUDE"],[dct valueForKey:@"LONGITUDE"]]];
    }


    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MMM d YYYY h:mm a"];
    NSString *fileName = [NSString new];
    if (self.googleDriveFileName.length > 0)
    {
        fileName = [NSString stringWithFormat:@"%@.csv",self.googleDriveFileName];
    }
    else
    {
        fileName = [NSString stringWithFormat:@"Measurement_%@.csv",[dateFormatter stringFromDate:[NSDate date]]];
    }
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *filePath = [NSString stringWithFormat:@"%@/%@", documentsDirectory, fileName];
    [csvString writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSURL *URL = [NSURL fileURLWithPath:filePath];
    TTOpenInAppActivity *openInAppActivity = [[TTOpenInAppActivity alloc] initWithView:self.view andBarButtonItem:sender];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[URL] applicationActivities:@[openInAppActivity]];
    
    activityViewController.popoverPresentationController.barButtonItem = sender;
    //activityViewController.popoverPresentationController.sourceView = self.view;
    //activityViewController.popoverPresentationController.sourceRect = self.navigationController.navigationItem.rightBarButtonItem.accessibilityFrame;
    
    [self presentViewController:activityViewController animated:YES completion:NULL];
    
    
}


- (void) takeScreenshot {
    
    GLint backingWidth2, backingHeight2;
    //Bind the color renderbuffer used to render the OpenGL ES view
    // If your application only creates a single color renderbuffer which is already bound at this point,
    // this call is redundant, but it is needed if you're dealing with multiple renderbuffers.
    // Note, replace "_colorRenderbuffer" with the actual name of the renderbuffer object defined in your class.
   // glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
   // [(EAGLView *)self.view setFramebuffer];
    
    // Get the size of the backing CAEAGLLayer
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth2);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight2);
    
    NSInteger x = 0, y = 0, width2 = backingWidth2, height2 = backingHeight2;
    NSInteger dataLength = width2 * height2 * 4;
    GLubyte *data = (GLubyte*)malloc(dataLength * sizeof(GLubyte));
    
    // Read pixel data from the framebuffer
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(x, y, width2, height2, GL_RGBA, GL_UNSIGNED_BYTE, data);
    
    // Create a CGImage with the pixel data
    // If your OpenGL ES content is opaque, use kCGImageAlphaNoneSkipLast to ignore the alpha channel
    // otherwise, use kCGImageAlphaPremultipliedLast
    CGDataProviderRef ref = CGDataProviderCreateWithData(NULL, data, dataLength, NULL);
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGImageRef iref = CGImageCreate(width2, height2, 8, 32, width2 * 4, colorspace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast,
                                    ref, NULL, true, kCGRenderingIntentDefault);
    
    // OpenGL ES measures data in PIXELS
    // Create a graphics context with the target size measured in POINTS
    NSInteger widthInPoints, heightInPoints;
    if (NULL != UIGraphicsBeginImageContextWithOptions) {
        // On iOS 4 and later, use UIGraphicsBeginImageContextWithOptions to take the scale into consideration
        // Set the scale parameter to your OpenGL ES view's contentScaleFactor
        // so that you get a high-resolution snapshot when its value is greater than 1.0
        CGFloat scale = self.view.contentScaleFactor;
        widthInPoints = width2 / scale;
        heightInPoints = height2 / scale;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(widthInPoints, heightInPoints), NO, scale);
    }
    else {
        // On iOS prior to 4, fall back to use UIGraphicsBeginImageContext
        widthInPoints = width2;
        heightInPoints = height2;
        UIGraphicsBeginImageContext(CGSizeMake(widthInPoints, heightInPoints));
    }
    
    CGContextRef cgcontext = UIGraphicsGetCurrentContext();
    
    // UIKit coordinate system is upside down to GL/Quartz coordinate system
    // Flip the CGImage by rendering it to the flipped bitmap context
    // The size of the destination area is measured in POINTS
    CGContextSetBlendMode(cgcontext, kCGBlendModeCopy);
    CGContextDrawImage(cgcontext, CGRectMake(0.0, 0.0, widthInPoints, heightInPoints), iref);
    
    // Retrieve the UIImage from the current context
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    /*
    UIImageView *tempImageView = [[UIImageView alloc] initWithImage:image];
    UIGraphicsBeginImageContext(tempImageView.frame.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGAffineTransform flipVertical = CGAffineTransformMake(
                                                           1, 0, 0, -1, 0, tempImageView.frame.size.height
                                                           );
    CGContextConcatCTM(context, flipVertical);
    
    [tempImageView.layer renderInContext:context];
    
    UIImage *flippedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImageWriteToSavedPhotosAlbum(flippedImage, nil, nil, nil);
     */
    
    // Clean up
    free(data);
    CFRelease(ref);
    CFRelease(colorspace);
    CGImageRelease(iref);
    
}


- (void)emailMesh
{
    self.mailViewController = [[MFMailComposeViewController alloc] init];
    
    if (!self.mailViewController)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"The email could not be sent."
                                                                       message:@"Please make sure an email account is properly setup on this device."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK"
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * action) { }];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
        
        return;
    }
    
    self.mailViewController.mailComposeDelegate = self;
    
    self.mailViewController.modalPresentationStyle = UIModalPresentationFormSheet;
    
    // Setup names and paths.
    NSString* attachmentDirectory = [NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES ) objectAtIndex:0];
    
    NSString* zipFilename = @"Model.zip";
    NSString* zipTemporaryFilePath = [attachmentDirectory stringByAppendingPathComponent:zipFilename];
    
    NSString* screenShotFilename = @"Preview.jpg";
    NSString* screenShotTemporaryFilePath = [attachmentDirectory stringByAppendingPathComponent:screenShotFilename];
    
    // First save the screenshot to disk.
    [self savePreviewImage:screenShotTemporaryFilePath];
    
    NSMutableDictionary* attachmentInfo;
    
    attachmentInfo = [@{
                                             @"dir": attachmentDirectory,
                                             @"zipFilename": @"Model.zip",
                                             @"screenShotFilename": @"Preview.jpg"
                                             } mutableCopy];
    
    
    [self.mailViewController setSubject:@"3D Model"];
    
    NSString *messageBody =
    @"This model was captured with the open source Room Capture sample app in the Structure SDK.\n\n"
    "Check it out!\n\n"
    "More info about the Structure SDK: http://structure.io/developers";
    
    [self.mailViewController setMessageBody:messageBody isHTML:NO];
    
    // Generate the OBJ file in a background queue to avoid blocking.
    [self showMeshViewerMessage:self.meshViewerMessageLabel msg:@"Preparing Email..."];
    
    dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
        
        [self.mailViewController addAttachmentData:[NSData dataWithContentsOfFile:screenShotTemporaryFilePath]
                                          mimeType:@"image/jpeg"
                                          fileName:screenShotFilename];
        
        // We want a ZIP with OBJ, MTL and JPG inside.
        NSDictionary* fileWriteOptions = @{kSTMeshWriteOptionFileFormatKey: @(STMeshWriteOptionFileFormatObjFileZip) };
        
        // Temporary path for the zip file.
        
        NSError* error;
        BOOL success = [self.meshRef writeToFile:zipTemporaryFilePath options:fileWriteOptions error:&error];
        if (!success)
        {
            NSLog (@"Could not save the mesh: %@", [error localizedDescription]);
            
            dispatch_async(dispatch_get_main_queue() , ^(){
                [self showMeshViewerMessage:self.meshViewerMessageLabel msg:@"Failed to save the OBJ file!"];
                
                // Hide the error message after 2 seconds.
                dispatch_after (dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue() , ^(){
                    [self hideMeshViewerMessage:self.meshViewerMessageLabel];
                });
            });
            
            return;
        }
        
        dispatch_async(dispatch_get_main_queue() , ^(){
            
            NSDictionary* attachmentsInfo = @{
                                              @"zipTemporaryFilePath": zipTemporaryFilePath,
                                              @"zipFilename": zipFilename,
                                              };
            [self didFinishSavingMeshWithAttachmentInfo:attachmentsInfo];
            
        });
    });
    
}

-(void) didFinishSavingMeshWithAttachmentInfo:(NSDictionary*)attachmentsInfo
{
    [self hideMeshViewerMessage:self.meshViewerMessageLabel];
    
    // We know the zip was saved there.
    NSString* zipFilePath = attachmentsInfo[@"zipTemporaryFilePath"];
    NSString* zipFilename = attachmentsInfo[@"zipFilename"];
    
    [self.mailViewController addAttachmentData:[NSData dataWithContentsOfFile:zipFilePath]
                                      mimeType:@"application/zip" fileName:zipFilename];
    
    [self presentViewController:self.mailViewController animated:YES completion:^(){}];
}

#pragma mark - Rendering

- (void)updateViewWith2DPosition:(UIView*)view onScreenPt:(GLKVector2)onScreenPt
{
    // scale point from [-1 1] to frame bound
    CGPoint center;
    center.x = onScreenPt.x;
    center.y = onScreenPt.y;
    view.hidden = false;
    view.center = center;
}

- (void)draw
{
    [(EAGLView *)self.view setFramebuffer];
    
    // Take this opportunity to process the Joystick information.
    _viewpointController->processJoystickRadiusAndTheta([_translationJoystick radius], [_translationJoystick theta]);
    
    static MeasurementState previousState;
    bool viewpointChanged = (_viewpointController->update()) || (_measurementState != previousState);
    previousState = _measurementState;
    
    // If nothing changed, do not waste time and resources rendering.
    if (!_needsDisplay && !viewpointChanged)
        return;
    
    GLKMatrix4 currentModelView = _viewpointController->currentGLModelViewMatrix();
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();
    
    _meshRenderer->clear();
    _meshRenderer->render(currentProjection, currentModelView);
    
    if (_measurementState == Measurement_Point2 || _measurementState == Measurement_Done1)
    {
        GLKVector2 onScreenPt1;
        bool pt1OnScreen = [self point3dToScreenPoint:_pt1 screenPt:onScreenPt1];
        
        if (pt1OnScreen)
            [self updateViewWith2DPosition:_circle1 onScreenPt:onScreenPt1];
        else
            _circle1.hidden = true;
        
        if (_measurementState == Measurement_Done1)
        {
            // from 3d point to screen point to [-1 1]
            GLKVector2 onScreenPt2;
            bool pt2OnScreen = [self point3dToScreenPoint:_pt2 screenPt:onScreenPt2];
            
            if (pt2OnScreen)
                [self updateViewWith2DPosition:_circle2 onScreenPt:onScreenPt2];
            else
                _circle2.hidden = true;
            
            GLKVector2 onScreenCenter;
            bool ptCenterOnScreen = [self point3dToScreenPoint:GLKVector3MultiplyScalar(GLKVector3Add(_pt1, _pt2), 0.5) screenPt:onScreenCenter];
            
            if (ptCenterOnScreen)
                [self updateViewWith2DPosition:_ruler1Text onScreenPt:onScreenCenter];
            else
                _ruler1Text.hidden = true;
        }
    }
    else if (_measurementState == Measurement_Point3 || _measurementState == Measurement_Done2)
    {
        GLKVector2 onScreenPt3;
        bool pt3OnScreen = [self point3dToScreenPoint:_pt3 screenPt:onScreenPt3];
        
        if (pt3OnScreen)
            [self updateViewWith2DPosition:_circle3 onScreenPt:onScreenPt3];
        else
            _circle3.hidden = true;
        
        if (_measurementState == Measurement_Done2)
        {
            // from 3d point to screen point to [-1 1]
            GLKVector2 onScreenPt4;
            bool pt4OnScreen = [self point3dToScreenPoint:_pt4 screenPt:onScreenPt4];
            
            if (pt4OnScreen)
                [self updateViewWith2DPosition:_circle4 onScreenPt:onScreenPt4];
            else
                _circle4.hidden = true;
            
            GLKVector2 onScreenCenter;
            bool ptCenterOnScreen = [self point3dToScreenPoint:GLKVector3MultiplyScalar(GLKVector3Add(_pt3, _pt4), 0.5) screenPt:onScreenCenter];
            
            if (ptCenterOnScreen)
                [self updateViewWith2DPosition:_ruler2Text onScreenPt:onScreenCenter];
            else
                _ruler2Text.hidden = true;
        }
    }
    else if (_measurementState == Measurement_Point5 || _measurementState == Measurement_Done3)
    {
        GLKVector2 onScreenPt5;
        bool pt5OnScreen = [self point3dToScreenPoint:_pt5 screenPt:onScreenPt5];
        
        if (pt5OnScreen)
            [self updateViewWith2DPosition:_circle5 onScreenPt:onScreenPt5];
        else
            _circle5.hidden = true;
        
        if (_measurementState == Measurement_Done3)
        {
            // from 3d point to screen point to [-1 1]
            GLKVector2 onScreenPt6;
            bool pt6OnScreen = [self point3dToScreenPoint:_pt6 screenPt:onScreenPt6];
            
            if (pt6OnScreen)
                [self updateViewWith2DPosition:_circle6 onScreenPt:onScreenPt6];
            else
                _circle6.hidden = true;
            
            GLKVector2 onScreenCenter;
            bool ptCenterOnScreen = [self point3dToScreenPoint:GLKVector3MultiplyScalar(GLKVector3Add(_pt5, _pt6), 0.5) screenPt:onScreenCenter];
            
            if (ptCenterOnScreen)
                [self updateViewWith2DPosition:_ruler3Text onScreenPt:onScreenCenter];
            else
                _ruler3Text.hidden = true;
        }
    }
    
    if (_measurementState == Measurement_Done1)
        _graphicsRenderer1->renderLine(_pt1, _pt2, currentProjection, currentModelView, _circle1.frame.origin.x < _circle2.frame.origin.x);
    else if (_measurementState == Measurement_Done2)
        _graphicsRenderer2->renderLine(_pt3, _pt4, currentProjection, currentModelView, _circle3.frame.origin.x < _circle4.frame.origin.x);
    else if (_measurementState == Measurement_Done3)
        _graphicsRenderer3->renderLine(_pt5, _pt6, currentProjection, currentModelView, _circle5.frame.origin.x < _circle6.frame.origin.x);
    
    [(EAGLView *)self.view presentFramebuffer];
    
    _needsDisplay = false;
}

#pragma mark - UI Control

- (void) hideMeshViewerMessage:(UILabel*)label
{
    [UIView animateWithDuration:0.5f animations:^{
        label.alpha = 0.0f;
    } completion:^(BOOL finished){
        [label setHidden:YES];
    }];
}

- (void)showMeshViewerMessage:(UILabel*)label msg:(NSString *)msg
{
    [label setText:msg];
    
    if (label.hidden == YES)
    {
        [label setHidden:NO];
        
        label.alpha = 0.0f;
        [UIView animateWithDuration:0.5f animations:^{
            label.alpha = 1.0f;
        }];
    }
}

- (IBAction)measurementButtonClicked:(id)sender
{
    
    if(_measurementState == Measurement_Clear)
        [self enterMeasurementState:Measurement_Point1];
    else if(_measurementState == Measurement_Done1 )
        [self enterMeasurementState:Measurement_Clear];
}

- (void)enterMeasurementState:(MeasurementState)state
{
    _measurementState = state;
    switch (_measurementState)
    {
        case Measurement_Clear:
        {
            //[self.employeeInfoArray removeAllObjects];
            self.measurementButton.enabled = true;
            [self.measurementButton setTitle:@"Measure" forState:UIControlStateNormal];
            
            [self hideMeshViewerMessage:self.measurementGuideLabel];
            _ruler1Text.hidden = true;
            _circle1.hidden = true;
            _circle2.hidden = true;
            
            _ruler2Text.hidden = true;
            _circle3.hidden = true;
            _circle4.hidden = true;
            
            _ruler3Text.hidden = true;
            _circle5.hidden = true;
            _circle6.hidden = true;
        }
            break;
        case Measurement_Point1:
        {
            self.measurementButton.enabled = false;
            _ruler1Text.hidden = true;
            _circle1.hidden = true;
            _circle2.hidden = true;
            [self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place first point."];
        }
            break;
        case Measurement_Point2:
        {
            _ruler1Text.hidden = true;
            _circle1.hidden = true;
            _circle2.hidden = true;
            [self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place second point."];
        }
            break;
        case Measurement_Done1:
        {
            self.measurementButton.enabled = true;
            [self.measurementButton setTitle:@"Clear" forState:UIControlStateNormal];
            float distance = GLKVector3Length(GLKVector3Subtract(_pt2, _pt1));
            if (distance > 1.0f)
                _ruler1Text.text = [NSString stringWithFormat:@"%.2f m", distance];
            else
                _ruler1Text.text = [NSString stringWithFormat:@"%.1f cm", distance*100];
            _circle2.hidden = false;
            _ruler1Text.hidden = false;
            [self getMeasuredObjectNameForValue:_ruler1Text.text whenFinishedMeasurementNo:1];
        }
            break;
        case Measurement_Point3:
        {
            _circle3.hidden = true;
            _circle4.hidden = true;
            [self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place fourth point."];
        }
            break;
        case Measurement_Done2:
        {
            float distance = GLKVector3Length(GLKVector3Subtract(_pt4, _pt3));
            if (distance > 1.0f)
                _ruler2Text.text = [NSString stringWithFormat:@"%.2f m", distance];
            else
                _ruler2Text.text = [NSString stringWithFormat:@"%.1f cm", distance*100];
            _circle4.hidden = false;
             _ruler1Text.hidden = false;
             _ruler2Text.hidden = false;
            [self getMeasuredObjectNameForValue:_ruler2Text.text whenFinishedMeasurementNo:2];
        }
            break;
        case Measurement_Point5:
        {
            _circle5.hidden = true;
            _circle6.hidden = true;
            [self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place sixth point."];
        }
             break;
        case Measurement_Done3:
        {
             self.measurementButton.enabled = true;
             [self.measurementButton setTitle:@"Clear" forState:UIControlStateNormal];
            
            float distance = GLKVector3Length(GLKVector3Subtract(_pt6, _pt5));
            if (distance > 1.0f)
                _ruler3Text.text = [NSString stringWithFormat:@"%.2f m", distance];
            else
                _ruler3Text.text = [NSString stringWithFormat:@"%.1f cm", distance*100];
            _circle6.hidden = false;
             _ruler1Text.hidden = false;
             _ruler2Text.hidden = false;
             _ruler3Text.hidden = false;
            [self getMeasuredObjectNameForValue:_ruler3Text.text whenFinishedMeasurementNo:3];
        }
            break;
        default:
            break;
    }
    
    // Make sure we refresh the ruler.
    self.needsDisplay = true;
}

- (void) getMeasuredObjectNameForValue:(NSString *) value whenFinishedMeasurementNo:(NSInteger) doneButtonNumber {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:@"Enter object name"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *submit = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {
                                                       
                                                       if (alert.textFields.count > 0) {
                                                           
                                                           UITextField *textField = [alert.textFields firstObject];
                                                           NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                                                           [dateFormatter setDateFormat:@"MMM d YYYY h:mm a"];
                                                           
                                                           NSMutableDictionary *dict = [[NSMutableDictionary alloc]initWithCapacity:0];
                                                           [dict setValue:textField.text forKey:@"ID"];
                                                           [dict setValue: value forKey:@"VALUE"];
                                                           [dict setValue: self.location forKey:@"LOCATION"];
                                                           [dict setValue:[dateFormatter stringFromDate:[NSDate date]] forKey:@"TIME"];
                                                           [dict setValue: self.latitude forKey:@"LATITUDE"];
                                                           [dict setValue: self.longlitude forKey:@"LONGITUDE"];
                                                           [self.employeeInfoArray addObject:dict];
                                                           
                                                           if (doneButtonNumber == 1){
                                                               //[self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place Third point."];
                                                               [self hideMeshViewerMessage:self.measurementGuideLabel];
                                                           }
                                                           else if (doneButtonNumber == 2){
                                                               [self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place Fifth point."];
                                                           }
                                                           else if (doneButtonNumber == 3) {
                                                               [self hideMeshViewerMessage:self.measurementGuideLabel];
                                                           }
                                                       }
                                                       
                                                   }];
    
    [alert addAction:submit];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Object name"; // if needs
    }];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)topViewSwitchChanged:(id)sender
{
    bool topViewEnabled = [self.topViewSwitch isOn];
    _viewpointController->setTopViewModeEnabled (topViewEnabled);
    [_translationJoystick setEnabled:!topViewEnabled];
    self.needsDisplay = true;
}

- (IBAction)holeFillingSwitchChanged:(id)sender
{
    if (self.holeFillingSwitch.on)
    {
        if ([self.delegate respondsToSelector:@selector(meshViewDidRequestHoleFilling)])
        {
            [self.delegate meshViewDidRequestHoleFilling];
        }
    }
    else
    {
        if ([self.delegate respondsToSelector:@selector(meshViewDidRequestRegularMesh)])
        {
            [self.delegate meshViewDidRequestRegularMesh];
        }
    }
    self.needsDisplay = true;
}

- (IBAction)XRaySwitchChanged:(id)sender
{
    if ([self.XRaySwitch isOn])
        _meshRenderer->setRenderingMode(MeshRenderer::RenderingModeXRay);
    else
        _meshRenderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
    self.needsDisplay = true;
}

#pragma mark - Touch and Gesture

- (void)pinchScaleGesture:(UIPinchGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer numberOfTouches] != 2)
        return;
    
    // Forward to the viewPointController
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onPinchGestureBegan([gestureRecognizer scale]);
    else if ( [gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onPinchGestureChanged([gestureRecognizer scale]);
}

- (void)rotationGesture:(UIRotationGestureRecognizer *)gestureRecognizer
{
    // Forward to the viewPointController
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onRotationGestureBegan([gestureRecognizer rotation]);
    else if ( [gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onRotationGestureChanged([gestureRecognizer rotation]);
}

-(GLKVector3)screenPointTo3dPoint :(GLKVector2)screenPt
{
    
    bool invertible;
    
    GLKMatrix4 invModelView = GLKMatrix4Invert(_viewpointController->currentGLModelViewMatrix(), &invertible);
    
    // scale to [-1 1]
    GLKVector2 screenPtScale = GLKVector2Make(2*screenPt.x/self.view.frame.size.width-1.0, 2*screenPt.y/self.view.frame.size.height-1.0);
    
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();
    
    // revert the projeciton effect
    float cotanX = currentProjection.m00;
    float cotanY = currentProjection.m11;
    GLKVector3 pt = GLKVector3Make(screenPtScale.x/cotanX, -screenPtScale.y/cotanY, 1.0);
    pt = GLKMatrix4MultiplyVector3WithTranslation(invModelView, pt);
    
    return pt;
}

- (bool)point3dToScreenPoint:(GLKVector3)pt screenPt:(GLKVector2&)screenPt
{
    
    GLKMatrix4 currentModelView = _viewpointController->currentGLModelViewMatrix();
    GLKVector3 ptTransformed = GLKMatrix4MultiplyVector3WithTranslation(currentModelView, pt);
    
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();
    
    float width = self.view.frame.size.width;
    float height = self.view.frame.size.height;
    
    float cotanX = currentProjection.m00;
    float cotanY = currentProjection.m11;
    
    screenPt = GLKVector2Make((ptTransformed.x/ptTransformed.z * cotanX + 1.0)*0.5 * width,
                              (-ptTransformed.y/ptTransformed.z * cotanY +1.0)*0.5*height);
    
    bool inView =  ptTransformed.z > 0 && [self.view pointInside:CGPointMake(screenPt.x, screenPt.y) withEvent:nil];
    return inView;
    
}

// measurement control
- (void)singleTapGesture:(UITapGestureRecognizer *)gestureRecognizer
{
    if (_measurementState != Measurement_Point1 && _measurementState != Measurement_Point2 && _measurementState != Measurement_Point3 && _measurementState != Measurement_Point4 && _measurementState != Measurement_Point5 && _measurementState != Measurement_Point6 && _measurementState != Measurement_Done1 && _measurementState != Measurement_Done2 && _measurementState != Measurement_Done3) {
        return;
    }
    
    if ([gestureRecognizer state] == UIGestureRecognizerStateEnded)
    {
        CGPoint touchPoint = [gestureRecognizer locationInView:self.view];
        
        GLKVector3 ptTouch = [self screenPointTo3dPoint:GLKVector2Make(touchPoint.x, touchPoint.y)];
        
        bool invertible;
        
        GLKMatrix4 invModelView = GLKMatrix4Invert(_viewpointController->currentGLModelViewMatrix(), &invertible);
        GLKVector3 ptCamera =GLKMatrix4MultiplyVector3WithTranslation(invModelView, GLKVector3Make(0, 0, 0));
        
        GLKVector3 direction = GLKVector3Subtract(ptTouch, ptCamera);
        float lenth = GLKVector3Length(direction);
        direction = GLKVector3DivideScalar(direction, lenth);
        
        GLKVector3 end = GLKVector3Add(ptCamera, GLKVector3MultiplyScalar(direction, 25));
        
        GLKVector3 intersection;
        STMeshIntersector *meshIntersector = [[STMeshIntersector alloc] initWithMesh:_meshRef];
        bool hasIntersection = [meshIntersector intersectWithRayOrigin:ptCamera
                                                                rayEnd:end
                                                          intersection:&intersection
                                                                normal:nil
                                                        ignoreBackFace:true];
        
        if (hasIntersection)
        {
            if(_measurementState == Measurement_Point1)
            {
                _pt1 = intersection;
                [self enterMeasurementState:Measurement_Point2];
            }
            else if(_measurementState == Measurement_Point2)
            {
                _pt2 = intersection;
                [self enterMeasurementState:Measurement_Done1];
            }
            else if(_measurementState == Measurement_Done1)
            {
                _pt3 = intersection;
                [self enterMeasurementState:Measurement_Point3];
            }
            else if(_measurementState == Measurement_Point3)
            {
                _pt4 = intersection;
                [self enterMeasurementState:Measurement_Done2];
            }
            else if(_measurementState == Measurement_Done2)
            {
                _pt5 = intersection;
                [self enterMeasurementState:Measurement_Point5];
            }
            else if(_measurementState == Measurement_Point5)
            {
                _pt6 = intersection;
                [self enterMeasurementState:Measurement_Done3];
            }
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

// Only accept pinch gestures when the touch point does not lie within the joystick view.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    CGPoint touchPoint = [touch locationInView:_translationJoystick.view];
    if ([_translationJoystick.view pointInside:touchPoint withEvent:nil])
        return NO;
    else
        return YES;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self.view];
    NSTimeInterval timestamp = [touch timestamp];
    
    GLKVector2 touchPosVec;
    touchPosVec.x = touchPoint.x;
    touchPosVec.y = touchPoint.y;
    
    // Forward to the viewPointController
    _viewpointController->onTouchBegan(touchPosVec, timestamp);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self.view];
    NSTimeInterval timestamp = [touch timestamp];
    
    GLKVector2 touchPosVec;
    touchPosVec.x = touchPoint.x;
    touchPosVec.y = touchPoint.y;
    // Forward to the viewPointController
    _viewpointController->onTouchChanged(touchPosVec, timestamp);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self.view];
    
    NSTimeInterval timestamp;
    timestamp = [touch timestamp];
    
    GLKVector2 touchPosVec;
    touchPosVec.x = touchPoint.x;
    touchPosVec.y = touchPoint.y;
    // Forward to the viewPointController
    _viewpointController->onTouchEnded(touchPosVec);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
}

@end
