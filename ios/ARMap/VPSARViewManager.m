#import <React/RCTViewManager.h>
#import <React/RCTView.h>
#import <UIKit/UIKit.h>
#import <ARKit/ARKit.h>
#import <ARCore/ARCore.h>

// 1. 실제 아이폰 카메라 화면(ARKit)과 구글 AI(ARCore)를 담아낼 커스텀 뷰 클래스 선언
@interface VPSARNativeView : UIView <ARSCNViewDelegate, GARSessionDelegate>

// 아이폰 카메라 화면을 출력해주는 기본 클래스
@property (nonatomic, strong) ARSCNView *sceneView;

// 구글 ARCore 엔진 핵심 제어 클래스
@property (nonatomic, strong) GARSession *garSession;

// 화면에 정밀한 위도, 경도, 정확도를 실시간으로 뿌려줄 네이티브 HUD 오버레이 UI
@property (nonatomic, strong) UILabel *debugOverlay;

// React Native(자바스크립트)에서 넘겨받을 Props 변수들
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) double targetLatitude;
@property (nonatomic, assign) double targetLongitude;
@property (nonatomic, copy) RCTBubblingEventBlock onTrackingStatusChange;

@end

@implementation VPSARNativeView

// 뷰가 처음 생성될 때 실행되는 생성자 코드
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        
        // 1) 아이폰 기본 3D AR 뷰(카메라) 초기화
        _sceneView = [[ARSCNView alloc] initWithFrame:self.bounds];
        _sceneView.delegate = self;
        _sceneView.showsStatistics = NO;
        _sceneView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sceneView];
        
        // 2) 구글 VPS 테스트 앱처럼 실시간 정보를 띄워줄 HUD 라벨 생성
        _debugOverlay = [[UILabel alloc] init];
        _debugOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65]; // 반투명 검은색 바탕
        _debugOverlay.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.2 alpha:1.0]; // 터미널 감성의 녹색 폰트
        _debugOverlay.font = [UIFont fontWithName:@"Courier-Bold" size:12.0]; // 고정폭 폰트
        _debugOverlay.numberOfLines = 0;
        _debugOverlay.text = @"[Google VPS Debug HUD]\nWaiting for Geospatial Engine...\nInit Status: Waiting API Key";
        _debugOverlay.layer.cornerRadius = 8;
        _debugOverlay.layer.masksToBounds = YES;
        _debugOverlay.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_debugOverlay];
        
        // 3) 레이아웃 제약 조건 설정 (카메라는 풀스크린, 디버그 라벨은 상단 중앙)
        [NSLayoutConstraint activateConstraints:@[
            // 카메라 렌즈는 전체 화면 채우기
            [_sceneView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_sceneView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_sceneView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_sceneView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            
            // HUD 디버그 라벨은 화면 상단 여백 60pt 지점에 가로 너비 패딩을 줘서 띄우기
            [_debugOverlay.topAnchor constraintEqualToAnchor:self.topAnchor constant:60.0],
            [_debugOverlay.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20.0],
            [_debugOverlay.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20.0],
            [_debugOverlay.heightAnchor constraintGreaterThanOrEqualToConstant:120.0]
        ]];
        
        // 라벨 내부 텍스트 패딩(여백) 설정을 위한 공백 추가 처리
        _debugOverlay.layer.borderWidth = 1.0;
        _debugOverlay.layer.borderColor = [[UIColor colorWithRed:0.0 green:1.0 blue:0.2 alpha:0.4] CGColor];
    }
    return self;
}

// 앱 화면에 실제로 뷰가 부착되어 눈에 보이기 시작할 때 호출됨
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        // 아이폰 카메라(ARKit) 세션 가동 시작
        ARWorldTrackingConfiguration *config = [ARWorldTrackingConfiguration new];
        config.worldAlignment = ARWorldAlignmentGravityAndHeading;
        [_sceneView.session runWithConfiguration:config];
        
        _debugOverlay.text = @"[Google VPS Debug HUD]\nARKit Camera: ACTIVE\nWaiting for Google ARCore...";
        NSLog(@"[VPS-iOS] iOS ARKit Camera Session Started.");
    } else {
        [_sceneView.session pause];
    }
}

// React Native에서 apiKey 프로퍼티를 주입해줄 때 호출
- (void)setApiKey:(NSString *)apiKey {
    _apiKey = apiKey;
    if (apiKey && apiKey.length > 0 && !_garSession) {
        [self initializeARCoreGeospatialSession:apiKey];
    }
}

// 구글 VPS(Geospatial API) 가동
- (void)initializeARCoreGeospatialSession:(NSString *)apiKey {
    NSError *error = nil;
    // 번들 식별자(bundleIdentifier)를 nil로 주어 자동 인식하게 함
    _garSession = [GARSession sessionWithAPIKey:apiKey bundleIdentifier:nil error:&error];
    
    if (error) {
        _debugOverlay.text = [NSString stringWithFormat:@"[Google VPS Error]\nAPI Session Failed:\n%@", error.localizedDescription];
        return;
    }
    
    _garSession.delegate = self;
    
    GARSessionConfiguration *garConfig = [[GARSessionConfiguration alloc] init];
    garConfig.geospatialMode = GARGeospatialModeEnabled;
    
    [_garSession setConfiguration:garConfig error:&error];
    if (error) {
        _debugOverlay.text = [NSString stringWithFormat:@"[Google VPS Error]\nGeospatial Enable Failed:\n%@", error.localizedDescription];
    } else {
        _debugOverlay.text = @"[Google VPS Debug HUD]\nGeospatial Mode: ENABLED\nStatus: SCANNING SURROUNDINGS...\nPlease pan camera slowly.";
        if (self.onTrackingStatusChange) {
            self.onTrackingStatusChange(@{@"status": @"engine_initialized"});
        }
    }
}

#pragma mark - ARSCNViewDelegate (매 프레임마다 네이티브 HUD 화면 정보 실시간 갱신)
- (void)renderer:(id<SCNSceneRenderer>)renderer didRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time {
    ARFrame *frame = _sceneView.session.currentFrame;
    
    if (frame && _garSession) {
        NSError *error = nil;
        GARFrame *garFrame = [_garSession update:frame error:&error];
        
        if (garFrame && garFrame.earth) {
            GAREarthState earthState = garFrame.earth.earthState;
            GARTrackingState trackingState = garFrame.earth.trackingState;
            
            // 실시간으로 디버깅 텍스트 조합
            NSMutableString *debugText = [NSMutableString stringWithString:@"🟢 [Google VPS Debug HUD]\n"];
            
            if (earthState == GAREarthStateEnabled) {
                [debugText appendString:@"Geospatial API: ACTIVE\n"];
                
                if (trackingState == GARTrackingStateTracking) {
                    // iOS ARCore에서는 Pose가 아닌 Transform 객체를 사용합니다.
                    GARGeospatialTransform *pose = garFrame.earth.cameraGeospatialTransform;
                    
                    [debugText appendFormat:@"Tracking State: ✅ TRACKING\n"];
                    [debugText appendFormat:@"Latitude:      %.7f\n", pose.coordinate.latitude];
                    [debugText appendFormat:@"Longitude:     %.7f\n", pose.coordinate.longitude];
                    [debugText appendFormat:@"Altitude:      %.2f m\n", pose.altitude];
                    [debugText appendString:@"------------------------------\n"];
                    [debugText appendFormat:@"Horizontal Acc: %.2f m\n", pose.horizontalAccuracy];
                    [debugText appendFormat:@"Vertical Acc:   %.2f m\n", pose.verticalAccuracy];
                    [debugText appendFormat:@"Orientation Acc:%.2f deg\n", pose.orientationYawAccuracy];
                    
                    // 주니어 개발자를 위해 정확도 수치에 따른 알림판 기능 추가
                    if (pose.horizontalAccuracy < 5.0) {
                        [debugText appendString:@"Accuracy Status: ✨ HIGH ACCURACY!"];
                    } else {
                        [debugText appendString:@"Accuracy Status: ⚠️ REFINING..."];
                    }
                    
                    // React Native에 정확도 정보까지 추가해서 실시간 보고 전송
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.onTrackingStatusChange) {
                            self.onTrackingStatusChange(@{
                                @"status": @"tracking_success",
                                @"latitude": @(pose.coordinate.latitude),
                                @"longitude": @(pose.coordinate.longitude),
                                @"altitude": @(pose.altitude),
                                @"horizontalAccuracy": @(pose.horizontalAccuracy),
                                @"verticalAccuracy": @(pose.verticalAccuracy)
                            });
                        }
                    });
                    
                } else if (trackingState == GARTrackingStatePaused) {
                    [debugText appendString:@"Tracking State: ⏸️ PAUSED\n"];
                    [debugText appendString:@"Hint: Point camera at distinct buildings."];
                } else {
                    [debugText appendString:@"Tracking State: ❌ STOPPED / ERROR"];
                }
            } else {
                [debugText appendFormat:@"Geospatial API: INACTIVE (State:%ld)", (long)earthState];
            }
            
            // UI 업데이트는 반드시 Main 스레드에서 수행되어야 함
            dispatch_async(dispatch_get_main_queue(), ^{
                self.debugOverlay.text = debugText;
            });
        }
    }
}

@end

// 2. React Native 뷰 매니저 정의
@interface VPSARViewManager : RCTViewManager
@end

@implementation VPSARViewManager

RCT_EXPORT_MODULE(VPSARView)

RCT_EXPORT_VIEW_PROPERTY(apiKey, NSString)
RCT_EXPORT_VIEW_PROPERTY(targetLatitude, double)
RCT_EXPORT_VIEW_PROPERTY(targetLongitude, double)
RCT_EXPORT_VIEW_PROPERTY(onTrackingStatusChange, RCTBubblingEventBlock)

- (UIView *)view {
    return [[VPSARNativeView alloc] init];
}

@end
