import CoreLocation
import Foundation
import UIKit

struct ARLabelOverlay: Equatable {
    let spotID: TourismSpot.ID
    let title: String
    let subtitle: String
    let normalizedX: Double
    let normalizedY: Double
    let confidence: RecognitionConfidence
    let isSceneSemanticsAdjusted: Bool
}

struct MatrixProjectionDebugOverlay: Equatable {
    let spotID: TourismSpot.ID
    let title: String
    let normalizedX: Double
    let normalizedY: Double
    let isInsideView: Bool
    let insidePointCount: Int
    let totalPointCount: Int
}

struct EdgeMarkerOverlay: Identifiable, Equatable {
    let id: TourismSpot.ID
    let shortTitle: String
    let distanceText: String?
    let normalizedX: Double
    let normalizedY: Double
    let scale: Double
    let systemImageName: String
}

struct OnScreenCandidateMarkerOverlay: Identifiable, Equatable {
    enum Role: Equatable {
        case primary
        case secondary
    }

    let id: TourismSpot.ID
    let shortTitle: String
    let distanceText: String?
    let normalizedX: Double
    let normalizedY: Double
    let scale: Double
    let role: Role
}

struct RadarMarkerOverlay: Identifiable, Equatable {
    let id: TourismSpot.ID
    let shortTitle: String
    let distanceText: String
    let normalizedX: Double
    let normalizedY: Double
    let isSelected: Bool
    let isArrivalNearby: Bool
    let isBehind: Bool
}

struct RouteArrowPathSnapshot: Equatable {
    let spotID: TourismSpot.ID
    let spotName: String
    let arrows: [RouteArrowSnapshot]
}

enum RouteTurnDirection: String, Equatable {
    case left
    case right

    var displayName: String {
        switch self {
        case .left:
            return "좌회전"
        case .right:
            return "우회전"
        }
    }
}

struct RouteArrowSnapshot: Identifiable, Equatable {
    let id: Int
    let position: SIMD3<Float>
    let yawRadians: Float
    let distanceFromOriginMeters: Double
    let turnDirection: RouteTurnDirection
    /// 화살표를 둘 "가는 방향"(현재 위치 → 회전 지점 방위, 도). 주행 방향 앵커링에 쓴다.
    let bearingDegrees: Double
}

struct RouteRibbonSnapshot: Equatable {
    let spotID: TourismSpot.ID
    /// 바닥 리본을 뻗을 "가는 방향"(현재 위치 → 다음 안내점 방위, 도).
    let bearingDegrees: Double
}

struct ArrivalPinSnapshot: Equatable {
    let spotID: TourismSpot.ID
    let spotName: String
    /// 현재 위치에서 목적지(도착 좌표)로의 방위(도). 핀을 "가는 방향"에 배치할 때 쓴다.
    let bearingDegrees: Double
    /// 현재 위치와 도착 좌표 사이 거리(m).
    let distanceMeters: Double
}

private struct NavigationGuidance {
    let title: String
    let detail: String
    let systemImageName: String
    let horizontalOffsetRatio: Double
    let isArrivalNearby: Bool
    var isConservative: Bool = false
}

struct DebugStatusRow: Identifiable, Equatable {
    let title: String
    let value: String

    var id: String { title }
}

enum IndoorDebugScenario: String, CaseIterable, Identifiable {
    case front30m
    case near5m
    case corner10m
    case opposite30m
    case far120m

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front30m:
            return "정면 30m"
        case .near5m:
            return "근거리 5m"
        case .corner10m:
            return "모서리 10m"
        case .opposite30m:
            return "반대 방향"
        case .far120m:
            return "장거리 120m"
        }
    }

    var description: String {
        switch self {
        case .front30m:
            return "POI 남쪽 30m에서 관광지를 바라봅니다."
        case .near5m:
            return "POI 남쪽 5m에서 근거리 라벨을 검증합니다."
        case .corner10m:
            return "POI 남동쪽 10m에서 대각선/모서리 후보를 검증합니다."
        case .opposite30m:
            return "POI 남쪽 30m에 있지만 반대 방향을 바라봅니다."
        case .far120m:
            return "POI 남쪽 120m에서 장거리 표시를 검증합니다."
        }
    }

    var offsetMeters: (east: Double, north: Double) {
        switch self {
        case .front30m:
            return (0, -30)
        case .near5m:
            return (0, -5)
        case .corner10m:
            return (10, -10)
        case .opposite30m:
            return (0, -30)
        case .far120m:
            return (0, -120)
        }
    }

    var reversesHeading: Bool {
        self == .opposite30m
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var spots: [TourismSpot]
    @Published var recognitionResult: RecognitionResult = .none(reason: "아직 인식을 시작하지 않았습니다.")
    @Published var selectedSpot: TourismSpot?
    @Published var cameraTextInput = ""
    @Published var locationConfidence: RecognitionConfidence = .high
    @Published var polygonValidatedSpotID: TourismSpot.ID?
    @Published var apiKeys: APIKeys
    @Published var latestLocationSnapshot: LocationSnapshot?
    @Published var latestCoreLocationSnapshot: LocationSnapshot?
    @Published var latestGeospatialLocationSnapshot: LocationSnapshot?
    @Published var geospatialStatus = "ARCore Geospatial 세션을 아직 시작하지 않았습니다."
    @Published var sceneSemanticsOverlayImage: UIImage?
    @Published var sceneSemanticsStatus = "Scene Semantics를 아직 시작하지 않았습니다."
    @Published var sceneSemanticsScoringDiagnostics = "Scene Semantics 라벨 보정을 아직 계산하지 않았습니다."
    @Published var arLabelOverlay: ARLabelOverlay?
    @Published var arLabelOverlayDiagnostics = "AR 라벨 후보를 아직 계산하지 않았습니다."
    @Published var matrixProjectionDebugOverlay: MatrixProjectionDebugOverlay?
    @Published var edgeMarkerOverlays: [EdgeMarkerOverlay] = []
    @Published var onScreenCandidateMarkerOverlays: [OnScreenCandidateMarkerOverlay] = []
    @Published var radarMarkerOverlays: [RadarMarkerOverlay] = []
    @Published var radarDiagnostics = "반원형 레이더를 아직 계산하지 않았습니다."
    @Published var isNavigationModeEnabled = false
    @Published var navigationDestinationSpotID: TourismSpot.ID?
    @Published var navigationSearchQuery = ""
    @Published var navigationSearchResults: [TMAPPOISearchResult] = []
    @Published var navigationSearchStatus = "목적지를 직접 입력해 TMAP 검색 결과로 길찾기를 시작할 수 있습니다."
    @Published var routeArrowPath: RouteArrowPathSnapshot?
    @Published var routeArrowDiagnostics = "길찾기 바닥 화살표 경로를 아직 계산하지 않았습니다."
    @Published var routeArrowComputationDiagnostics = "길찾기 화살표 계산 로그를 아직 만들지 않았습니다."
    @Published var routeArrowRenderDiagnostics = "길찾기 화살표 렌더 로그를 아직 받지 못했습니다."
    @Published var navigationGuidanceTitle = "목적지를 선택하세요"
    @Published var navigationGuidanceDetail = "TMAP 경로를 준비하면 다음 진행 방향을 표시합니다."
    @Published var navigationGuidanceSystemImageName = "location.fill"
    @Published var navigationGuidanceHorizontalOffsetRatio: Double = 0
    @Published var navigationGuidanceIsArrivalNearby = false
    @Published var navigationStabilityDiagnostics = "위치/방향 안정화를 아직 계산하지 않았습니다."
    @Published var arrivalPin: ArrivalPinSnapshot?
    @Published var routeRibbonPath: RouteRibbonSnapshot?
    @Published var navigationGuidanceIsConservative = false
    /// 활성 회전 화살표가 있을 때의 카운트다운 안내("15m 후 우회전"). 없으면 nil.
    @Published var navigationTurnBanner: String?
    @Published var showsMatrixDebugMarker = FeatureFlags.enableLegacyMatrixDebugOverlay
    @Published var showsOnScreenCandidateDebugMarkers = FeatureFlags.enableLegacyOnScreenCandidateDebugMarkers
    @Published var shows3DGeospatialDebugMarker = FeatureFlags.enableLegacyGeospatial3DMarkers
    @Published var showsFullDebugLogs = FeatureFlags.enableLegacyFullDebugLogs
    @Published var cameraHeadingDegrees: Double?
    @Published var cameraHeadingSampleCount = 0
    @Published var cameraHeadingLastUpdatedAt: Date?
    @Published var cameraHeadingDeltaDegrees: Double?
    @Published var cameraHeadingDiagnostics = "카메라 heading 샘플을 아직 받지 못했습니다."
    @Published var cameraPoseSnapshot: CameraPoseSnapshot?
    @Published var cameraPoseDiagnostics = "AR camera pose 샘플을 아직 받지 못했습니다."
    @Published var cameraProjectionSnapshot: CameraProjectionSnapshot?
    @Published var cameraProjectionDiagnostics = "ARFrame camera matrix 샘플을 아직 받지 못했습니다."
    @Published var effectiveSpatialConfidence: RecognitionConfidence = .high
    @Published var spatialTrackingDiagnostics = "위치/heading 안정도 샘플을 아직 받지 못했습니다."
    @Published var stableOriginDiagnostics = "3D stable origin을 아직 확정하지 않았습니다."
    @Published var spatialAlignmentDiagnostics = "선택 Polygon과 카메라 heading 정렬을 아직 계산하지 않았습니다."
    @Published var localCoordinateDiagnostics = "local ENU 좌표 변환을 아직 계산하지 않았습니다."
    @Published var polygonProjectionDiagnostics = "선택 Polygon 화면 투영을 아직 계산하지 않았습니다."
    @Published var matrixProjectionComparisonDiagnostics = "projection matrix 비교 좌표를 아직 계산하지 않았습니다."
    @Published var buildingFacadeAnchorDiagnostics = "3D 외벽 후보점을 아직 계산하지 않았습니다."
    @Published var buildingLabelHeightDiagnostics = "3D 라벨 높이 기준값을 아직 계산하지 않았습니다."
    @Published var geospatialWGS84CandidateDiagnostics = "WGS84 Anchor 후보를 아직 계산하지 않았습니다."
    @Published var geospatialAnchorStateDiagnostics = "WGS84 Anchor 생성 상태를 아직 받지 못했습니다."
    @Published var cameraDirectionSpotID: TourismSpot.ID?
    @Published var cameraDirectionStatus = "카메라 방향 후보를 아직 계산하지 않았습니다."
    @Published var polygonValidationStatus = "Polygon 자동 후보를 아직 계산하지 않았습니다."
    @Published var polygonLookupStartedAt: Date?
    @Published var polygonLookupFinishedAt: Date?
    @Published var polygonLookupLogs: [String] = []
    @Published var buildingPolygonsBySpotID: [TourismSpot.ID: BuildingPolygon] = [:]
    @Published var resolvedBuildingHeightsBySpotID: [TourismSpot.ID: ResolvedBuildingHeight] = [:]
    @Published var tmapArrivalRoutesBySpotID: [TourismSpot.ID: TMAPPedestrianRoute] = [:]
    @Published var tmapRouteStatus = "TMAP 도착 좌표를 아직 조회하지 않았습니다."
    @Published var tourismDataStatus = "TourAPI는 비활성화되어 있고 테스트 목업 건물 후보를 사용 중입니다."
    @Published var isIndoorDebugModeEnabled = false
    @Published var indoorDebugStatus = "실내 디버그 모드는 꺼져 있습니다."
    @Published var indoorDebugSelectedSpotID: TourismSpot.ID?
    @Published var indoorDebugScenario: IndoorDebugScenario = .front30m
    @Published var pendingIndoorDebugMapTapCoordinate: CLLocationCoordinate2D?
    @Published var hasAppliedIndoorNavigationMapTapLocation = false
    @Published var indoorDebugSimulatesPoorAccuracy = false
    // 카메라 영상 해상도. 기본 false(저해상도, 발열 절감), 토글로 고해상도 전환.
    @Published var prefersHighResolutionCamera = false

    private let recognitionPipeline: RecognitionPipeline
    private let cameraDirectionCandidateProvider: CameraDirectionCandidateProvider
    private let tourAPIClient: any TourAPIClient
    private let vworldClient: any VWorldClient
    private let tmapClient: any TMAPClient
    private let nearbySpotRadiusMeters: CLLocationDistance = 3_000
    private let headingInstabilityThresholdDegrees: Double = 12
    private let projectionHorizontalFOVDegrees: Double = 60
    private let projectionVerticalFOVDegrees: Double = 45
    private let fovFallbackMaxHeadingDeltaDegrees: Double = 75
    private let maxEdgeMarkerCount = 3
    private let maxRadarMarkerCount = 12
    private let radarRadiusMeters: CLLocationDistance = 1_000
    private let distantMarkerThresholdMeters: CLLocationDistance = 1_000
    private let distantMarkerScale = 0.78
    private let geospatial3DCreateRadiusMeters: CLLocationDistance = 120
    private let geospatial3DDeleteRadiusMeters: CLLocationDistance = 140
    private let maxActiveGeospatial3DAnchorCount = 3
    private let routeArrivalCompletionMeters: CLLocationDistance = 10
    private let routeArrowLookAheadMeters: CLLocationDistance = 120
    private let routeTurnBoundaryMeters: CLLocationDistance = 18
    private let routeArrowForwardDistanceMeters: Float = 3.0
    private let routeArrowCameraHeightOffsetMeters: Float = -0.05
    private let maxRouteArrowCount = 1
    private let routeTurnMinimumAngleDegrees: Double = 45
    private let routeTurnAlignedThresholdDegrees: Double = 22
    private let routeArrowFacingToleranceDegrees: Double = 60
    private let routeTurnSampleDistanceMeters: CLLocationDistance = 6
    private let tmapRouteDebounceDistanceMeters: CLLocationDistance = 1
    private let tmapRouteDebounceInterval: TimeInterval = 1.5
    private let geospatial3DAnchorRefreshInterval: TimeInterval = 2.0
    private let stableOriginMaxAccuracyMeters: CLLocationAccuracy = 10
    private let stableOriginMaxJumpMeters: CLLocationDistance = 12
    private let stableOriginConfirmationInterval: TimeInterval = 1.2
    private let stableOriginDegradedTimeout: TimeInterval = 3.0
    private let polygonBoundaryToleranceMeters: CLLocationDistance = 0.8
    private let markerPlacementToleranceMeters: CLLocationDistance = 8
    private let buildingHeightResolver = BuildingHeightResolver()
    private var loadedTourismSpots: [TourismSpot] = []
    private var polygonLookupTask: Task<Void, Never>?
    private var polygonLookupInFlightSpotID: TourismSpot.ID?
    private var polygonPrefetchTasksBySpotID: [TourismSpot.ID: Task<Void, Never>] = [:]
    private var polygonLookupNotFoundSpotIDs: Set<TourismSpot.ID> = []
    private var tmapRouteTasksBySpotID: [TourismSpot.ID: Task<Void, Never>] = [:]
    private var tmapRouteFailedSpotIDs: Set<TourismSpot.ID> = []
    private var navigationSearchTask: Task<Void, Never>?
    private var navigationRouteTask: Task<Void, Never>?
    private var navigationRouteTaskSpotID: TourismSpot.ID?
    private var lastNavigationRouteRequestSpotID: TourismSpot.ID?
    private var lastNavigationRouteRequestOrigin: CLLocationCoordinate2D?
    private var lastNavigationRouteRequestAt: Date?
    private var latestSceneSemanticsSnapshot: SceneSemanticsSnapshot?
    private var sceneSemanticsEvidenceBySpotID: [TourismSpot.ID: SceneSemanticsSpotEvidence] = [:]
    private var stableGeospatial3DOrigin: LocationSnapshot?
    private var pendingStableGeospatial3DOrigin: LocationSnapshot?
    private var pendingStableOriginFirstSeenAt: Date?
    private var stableOriginLastAcceptedAt: Date?
    private var stableOriginIsUsableFor3DAnchors = false
    private var lastGeospatial3DAnchorRefreshAt: Date?
    private var lastRequestedTerrainAnchorSpotIDs: Set<TourismSpot.ID> = []
    private var activeGeospatial3DSpotIDs: Set<TourismSpot.ID> = []
    private var stableFacadeSelectionsBySpotID: [TourismSpot.ID: StableBuildingFacadeSelection] = [:]
    private var fixedNearestFacadeCandidatesBySpotID: [TourismSpot.ID: BuildingFacadeCandidate] = [:]
    private var markerPlacementDiagnosticsBySpotID: [TourismSpot.ID: String] = [:]
    private let facadeSwitchRayDistanceImprovementMeters: Double = 1.5
    private let facadeSwitchConfirmationInterval: TimeInterval = 0.5
    private let indoorDegradedAccuracyMeters: CLLocationAccuracy = 30
    private var guidanceStabilizer = NavigationGuidanceStabilizer()
    private var movementTracker = MovementDirectionTracker()
    let geospatialSessionManager: GeospatialSessionManager

    init(
        spots: [TourismSpot] = MockTourismSpots.testBuildings,
        recognitionPipeline: RecognitionPipeline = RecognitionPipeline(),
        cameraDirectionCandidateProvider: CameraDirectionCandidateProvider = CameraDirectionCandidateProvider(),
        apiKeys: APIKeys = APIKeyProvider.load(),
        tourAPIClient: (any TourAPIClient)? = nil,
        vworldClient: (any VWorldClient)? = nil,
        tmapClient: (any TMAPClient)? = nil
    ) {
        self.spots = spots
        self.recognitionPipeline = recognitionPipeline
        self.cameraDirectionCandidateProvider = cameraDirectionCandidateProvider
        self.apiKeys = apiKeys
        self.tourAPIClient = tourAPIClient ?? LocalGovernmentHubTourAPIClient(
            apiKey: apiKeys.tourAPI,
            requests: [TourAPIAreaRequests.gimhae]
        )
        self.vworldClient = vworldClient ?? VWorldDataAPIClient(apiKey: apiKeys.vworld)
        self.tmapClient = tmapClient ?? SKOpenAPITMAPClient(apiKey: apiKeys.tmap)
        self.loadedTourismSpots = spots
        self.geospatialSessionManager = GeospatialSessionManager(apiKeysProvider: { apiKeys })
        self.cameraTextInput = ""
        self.polygonValidatedSpotID = nil
        self.geospatialSessionManager.onSnapshotUpdated = { [weak self] snapshot in
            Task { @MainActor in
                guard self?.isIndoorDebugModeEnabled != true else {
                    return
                }
                self?.latestLocationSnapshot = snapshot
                switch snapshot.source {
                case .coreLocation:
                    self?.latestCoreLocationSnapshot = snapshot
                case .arCoreGeospatial:
                    self?.latestGeospatialLocationSnapshot = snapshot
                }
                self?.locationConfidence = Self.locationConfidence(for: snapshot.horizontalAccuracy)
                self?.movementTracker.update(coordinate: snapshot.coordinate, now: snapshot.capturedAt)
                let stableOriginDidChange = self?.updateStableGeospatial3DOrigin(with: snapshot) ?? false
                self?.refreshSpatialTrackingConfidence()
                self?.applyNearbySpotFilter()
                self?.updateCameraDirectionCandidate()
                self?.refreshLocalCoordinateDiagnostics()
                self?.refreshBuildingFacadeAnchorDiagnostics()
                self?.refreshBuildingLabelHeightDiagnostics()
                if stableOriginDidChange {
                    self?.refreshGeospatial3DAnchorRequestsIfPossible()
                }
                self?.refreshMatrixProjectionComparisonDiagnostics()
                self?.refreshEdgeMarkerOverlays()
                self?.refreshOnScreenCandidateMarkerOverlays()
                self?.refreshRadarMarkerOverlays()
                self?.refreshRouteArrowPath()
            }
        }
        self.geospatialSessionManager.onStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.geospatialStatus = status
            }
        }
        self.geospatialSessionManager.onSceneSemanticsUpdated = { [weak self] snapshot in
            Task { @MainActor in
                self?.sceneSemanticsOverlayImage = snapshot.overlayImage
                self?.latestSceneSemanticsSnapshot = snapshot
                self?.refreshSceneSemanticsScoring()
                self?.runRecognition()
                self?.refreshARLabelOverlay()
            }
        }
        self.geospatialSessionManager.onSceneSemanticsStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.sceneSemanticsStatus = status
            }
        }
        self.geospatialSessionManager.onTerrainAnchorStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.geospatialAnchorStateDiagnostics = status
            }
        }

        applyMockSpots()
    }

    func startMainMapLocationUpdates() {
        geospatialSessionManager.requestLocationPermission()
        geospatialSessionManager.startLocationUpdates()
    }

    func loadTourAPISpots() async {
        tourismDataStatus = "TourAPI 김해 후보와 테스트 목업 건물을 불러오는 중입니다."

        do {
            let fetchedSpots = try await tourAPIClient.fetchTourismSpots()
            let mergedSpots = (fetchedSpots + MockTourismSpots.testBuildings).deduplicatedByID()
            guard !mergedSpots.isEmpty else {
                useMockFallback(reason: "TourAPI 응답과 목업 후보가 모두 비어 있습니다.")
                return
            }

            loadedTourismSpots = mergedSpots
            clearManualSpatialSelections()
            applyNearbySpotFilter()
            updateCameraDirectionCandidate()
            runRecognition()
        } catch {
            useMockFallback(reason: "TourAPI 김해 후보 로딩 실패: \(error.localizedDescription)")
        }
    }

    func enableTourAPILoadingForLater() async {
        tourismDataStatus = "TourAPI 김해 중심 관광지 데이터를 불러오는 중입니다."

        do {
            let fetchedSpots = try await tourAPIClient.fetchTourismSpots()
            guard !fetchedSpots.isEmpty else {
                useMockFallback(reason: "TourAPI 응답에서 좌표가 있는 김해 관광지 후보를 찾지 못했습니다.")
                return
            }

            loadedTourismSpots = fetchedSpots
            clearManualSpatialSelections()
            applyNearbySpotFilter()
            updateCameraDirectionCandidate()
            runRecognition()
        } catch {
            useMockFallback(reason: error.localizedDescription)
        }
    }

    func loadHaeundaeTourAPIDebugSpots() async {
        tourismDataStatus = "TourAPI 부산 해운대구 실내 디버그 후보를 불러오는 중입니다."
        indoorDebugStatus = "해운대구 TourAPI 후보 로딩 중..."

        do {
            let client = LocalGovernmentHubTourAPIClient(
                apiKey: apiKeys.tourAPI,
                requests: [TourAPIAreaRequests.busanHaeundae]
            )
            let fetchedSpots = try await client.fetchTourismSpots()
            guard !fetchedSpots.isEmpty else {
                indoorDebugStatus = "해운대구 TourAPI 응답에서 좌표가 있는 후보를 찾지 못했습니다."
                tourismDataStatus = indoorDebugStatus
                return
            }

            loadedTourismSpots = fetchedSpots
            clearManualSpatialSelections()
            spots = fetchedSpots
            indoorDebugSelectedSpotID = fetchedSpots.first?.id
            selectedSpot = fetchedSpots.first
            tourismDataStatus = "TourAPI 부산 해운대구 실내 디버그 후보 \(fetchedSpots.count)개를 불러왔습니다."
            indoorDebugStatus = "해운대구 후보 \(fetchedSpots.count)개 로딩 완료. 시나리오를 선택해 debug origin을 주입하세요."

            if isIndoorDebugModeEnabled {
                applyIndoorDebugScenario(indoorDebugScenario)
            } else {
                runRecognition()
            }
        } catch {
            indoorDebugStatus = "해운대구 TourAPI 로딩 실패: \(error.localizedDescription)"
            tourismDataStatus = indoorDebugStatus
        }
    }

    func setIndoorDebugModeEnabled(_ isEnabled: Bool) {
        isIndoorDebugModeEnabled = isEnabled
        guidanceStabilizer.reset()
        movementTracker.reset()
        if isEnabled {
            hasAppliedIndoorNavigationMapTapLocation = false
            pendingIndoorDebugMapTapCoordinate = nil
            routeArrowPath = nil
            indoorDebugStatus = "실내 테스트 모드가 켜졌습니다. 하단 2D 지도에서 내 위치를 탭한 뒤 적용을 눌러야 TMAP 경로를 요청합니다."
            routeArrowDiagnostics = "실내 테스트 대기 / 지도 탭 후 적용 전까지 TMAP 요청 안 함"
            routeArrowComputationDiagnostics = "실내 테스트 모드 진입만으로는 위치 주입/경로 요청을 수행하지 않습니다."
        } else {
            hasAppliedIndoorNavigationMapTapLocation = false
            indoorDebugStatus = "실내 디버그 모드를 종료했습니다. 실제 CoreLocation/ARCore snapshot을 다시 사용합니다."
            stableGeospatial3DOrigin = nil
            pendingStableGeospatial3DOrigin = nil
            pendingStableOriginFirstSeenAt = nil
            stableOriginLastAcceptedAt = nil
            stableOriginIsUsableFor3DAnchors = false
            stableOriginDiagnostics = "실내 디버그 종료로 3D stable origin을 초기화했습니다."
            geospatialSessionManager.clearAllGeospatialDebugAnchors(reason: "실내 디버그 종료로 WGS84 Anchor를 모두 제거했습니다.")
            activeGeospatial3DSpotIDs = []
            fixedNearestFacadeCandidatesBySpotID = [:]
            lastRequestedTerrainAnchorSpotIDs = []
            routeArrowPath = nil
            routeArrowDiagnostics = "실내 디버그 종료로 길찾기 화살표를 초기화했습니다."
            routeArrowComputationDiagnostics = "실내 디버그 종료로 화살표 계산 로그를 초기화했습니다."
            radarMarkerOverlays = []
            radarDiagnostics = "실내 디버그 종료로 반원형 레이더를 초기화했습니다."
            refreshSpatialTrackingConfidence()
        }
    }

    func selectIndoorDebugSpot(id: TourismSpot.ID) {
        indoorDebugSelectedSpotID = id
        selectedSpot = spots.first(where: { $0.id == id })
        refreshRadarMarkerOverlays()
        refreshRouteArrowPath()
    }

    func applyIndoorNavigationDebug(spotID: TourismSpot.ID, scenario: IndoorDebugScenario) {
        guard let spot = spots.first(where: { $0.id == spotID }) else {
            indoorDebugStatus = "실내 길찾기 디버그 대상 POI를 찾지 못했습니다."
            return
        }

        if navigationRouteTaskSpotID != spot.id {
            navigationRouteTask?.cancel()
            navigationRouteTask = nil
            navigationRouteTaskSpotID = nil
        }
        isIndoorDebugModeEnabled = true
        isNavigationModeEnabled = true
        hasAppliedIndoorNavigationMapTapLocation = true
        indoorDebugSelectedSpotID = spot.id
        navigationDestinationSpotID = spot.id
        selectedSpot = spot
        routeArrowPath = nil
        tmapRouteFailedSpotIDs.remove(spot.id)
        routeArrowDiagnostics = "\(spot.name) 실내 길찾기 디버그 / \(scenario.title) 시나리오 적용"
        routeArrowComputationDiagnostics = "\(spot.name) 실내 디버그 origin 주입 후 TMAP route 재계산"
        applyIndoorDebugScenario(scenario)
        ensureNavigationRouteForDestination()
    }

    func selectIndoorNavigationDebugDestination(_ spot: TourismSpot) {
        indoorDebugSelectedSpotID = spot.id
        navigationDestinationSpotID = spot.id
        selectedSpot = spot
        isNavigationModeEnabled = true
        hasAppliedIndoorNavigationMapTapLocation = false
        pendingIndoorDebugMapTapCoordinate = nil
        routeArrowPath = nil
        routeArrowDiagnostics = "\(spot.name) 실내 테스트 목적지 선택 / 지도에서 내 위치를 탭하세요."
        routeArrowComputationDiagnostics = "\(spot.name) 실내 테스트 목적지 선택 / 적용 전까지 위치와 경로는 변경하지 않습니다."
        indoorDebugStatus = "\(spot.name) 선택됨. 하단 2D 지도에서 테스트할 내 위치를 탭한 뒤 적용을 누르세요."
    }

    func recordIndoorNavigationMapTapLocation(_ coordinate: CLLocationCoordinate2D) {
        guard let destination = navigationDestinationSpot ?? selectedSpot else {
            indoorDebugStatus = "실내 테스트 위치를 저장하려면 먼저 길찾기 목적지를 선택해야 합니다."
            routeArrowDiagnostics = "실내 지도 탭 대기 / 목적지 없음"
            routeArrowComputationDiagnostics = "하단 2D 지도 탭 좌표 \(coordinate.shortText), 목적지 없음"
            return
        }

        isIndoorDebugModeEnabled = true
        isNavigationModeEnabled = true
        hasAppliedIndoorNavigationMapTapLocation = false
        indoorDebugSelectedSpotID = destination.id
        navigationDestinationSpotID = destination.id
        selectedSpot = destination
        pendingIndoorDebugMapTapCoordinate = coordinate

        let headingText = cameraHeadingDegrees.map { "\(Int($0))도" } ?? "수신 대기"
        indoorDebugStatus = "\(destination.name) / 적용 대기 위치 \(coordinate.shortText) / 실제 heading \(headingText)"
        routeArrowDiagnostics = "\(destination.name) 실내 지도 탭 저장 / 적용 버튼을 누르면 이 좌표에서 경로를 새로 요청합니다."
        routeArrowComputationDiagnostics = "\(destination.name) pending origin \(coordinate.shortText) / 아직 latestLocationSnapshot에는 반영하지 않았습니다."
    }

    func applyPendingIndoorNavigationMapTapLocation() {
        guard let coordinate = pendingIndoorDebugMapTapCoordinate else {
            indoorDebugStatus = "하단 2D 지도에서 테스트할 내 위치를 먼저 탭하세요."
            routeArrowDiagnostics = "실내 지도 탭 적용 실패 / pending 좌표 없음"
            routeArrowComputationDiagnostics = "적용 버튼을 눌렀지만 pendingIndoorDebugMapTapCoordinate가 없습니다."
            return
        }

        applyIndoorNavigationMapTapLocation(coordinate)
    }

    private func applyIndoorNavigationMapTapLocation(_ coordinate: CLLocationCoordinate2D) {
        guard let destination = navigationDestinationSpot ?? selectedSpot else {
            indoorDebugStatus = "실내 테스트 위치를 주입하려면 먼저 길찾기 목적지를 선택해야 합니다."
            routeArrowDiagnostics = "실내 지도 탭 무시 / 목적지 없음"
            routeArrowComputationDiagnostics = "하단 2D 지도 탭 좌표 \(coordinate.shortText), 목적지 없음"
            return
        }

        isIndoorDebugModeEnabled = true
        isNavigationModeEnabled = true
        hasAppliedIndoorNavigationMapTapLocation = true
        indoorDebugSelectedSpotID = destination.id
        navigationDestinationSpotID = destination.id
        selectedSpot = destination
        routeArrowPath = nil
        tmapRouteFailedSpotIDs.remove(destination.id)

        // 실내 재현용: 정확도 저하 토글이 켜져 있으면 오차 원을 키워 3.6 불안정 경로를 실내에서 검증할 수 있게 한다.
        let injectedAccuracy: CLLocationAccuracy = indoorDebugSimulatesPoorAccuracy ? indoorDegradedAccuracyMeters : 1
        let snapshot = LocationSnapshot(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitude: latestGeospatialLocationSnapshot?.altitude ?? latestCoreLocationSnapshot?.altitude,
            horizontalAccuracy: injectedAccuracy,
            verticalAccuracy: latestGeospatialLocationSnapshot?.verticalAccuracy ?? latestCoreLocationSnapshot?.verticalAccuracy,
            heading: cameraHeadingDegrees,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )

        latestLocationSnapshot = snapshot
        latestGeospatialLocationSnapshot = snapshot
        movementTracker.update(coordinate: coordinate, now: snapshot.capturedAt)
        locationConfidence = Self.locationConfidence(for: injectedAccuracy)
        effectiveSpatialConfidence = locationConfidence
        stableGeospatial3DOrigin = snapshot
        pendingStableGeospatial3DOrigin = nil
        pendingStableOriginFirstSeenAt = nil
        stableOriginLastAcceptedAt = Date()
        stableOriginIsUsableFor3DAnchors = true
        stableOriginDiagnostics = "3D stable origin 확정(실내 지도 탭) / 정확도 \(Int(injectedAccuracy))m / \(coordinate.shortText)"
        geospatialStatus = "실내 디버그 모드: 하단 2D 지도 탭 좌표를 현재 위치로 사용합니다."

        let headingText = cameraHeadingDegrees.map { "\(Int($0))도" } ?? "수신 대기"
        indoorDebugStatus = "\(destination.name) / 적용된 내 위치 \(coordinate.shortText) / 실제 heading \(headingText) / TMAP 경로 재요청"
        routeArrowDiagnostics = "\(destination.name) 실내 지도 탭 위치 적용 / 적용 좌표 기준 TMAP 경로 재요청"
        routeArrowComputationDiagnostics = "\(destination.name) 실내 지도 탭 origin \(coordinate.shortText) / 실제 heading \(headingText) / 새 TMAP route 요청"

        applyNearbySpotFilter()
        updateBuildingPolygon(for: destination)
        updateCameraDirectionCandidate()
        refreshSpatialTrackingConfidence()
        refreshLocalCoordinateDiagnostics()
        refreshBuildingFacadeAnchorDiagnostics()
        refreshBuildingLabelHeightDiagnostics()
        refreshMatrixProjectionComparisonDiagnostics()
        refreshEdgeMarkerOverlays()
        refreshOnScreenCandidateMarkerOverlays()
        refreshRadarMarkerOverlays()
        refreshARLabelOverlay()
        refreshRouteArrowPath()
        runRecognition()
        ensureNavigationRouteForDestination()
    }

    func setNavigationModeEnabled(_ isEnabled: Bool) {
        isNavigationModeEnabled = isEnabled
        // 길찾기 진입/종료 시 경로 맥락이 바뀌므로 위치/방향 안정화 상태를 초기화한다.
        guidanceStabilizer.reset()
        movementTracker.reset()

        if isEnabled {
            if navigationDestinationSpotID == nil {
                navigationDestinationSpotID = selectedSpot?.id ?? recognitionResult.labelSpot?.id
            }
            if let destinationID = navigationDestinationSpotID {
                selectedSpot = spots.first(where: { $0.id == destinationID }) ?? selectedSpot
                activeGeospatial3DSpotIDs = activeGeospatial3DSpotIDs.intersection([destinationID])
                geospatialSessionManager.clearAllGeospatialDebugAnchors(reason: "길찾기 진입 / 선택 목적지 외 3D 마커 정리")
            }
            routeArrowDiagnostics = navigationDestinationSpotID == nil
                ? "길찾기 모드 켜짐 / 목적지를 선택하세요."
                : "길찾기 모드 켜짐 / 목적지 경로를 준비합니다."
            refreshRadarMarkerOverlays()
            refreshRouteArrowPath()
            ensureNavigationRouteForDestination()
        } else {
            navigationRouteTask?.cancel()
            navigationRouteTask = nil
            navigationRouteTaskSpotID = nil
            routeArrowPath = nil
            arrivalPin = nil
            routeRibbonPath = nil
            navigationTurnBanner = nil
            routeArrowDiagnostics = "길찾기 모드 꺼짐 / 목적지를 선택하면 화살표를 표시합니다."
            routeArrowComputationDiagnostics = "길찾기 모드 꺼짐 / 화살표 계산 안 함"
            setNavigationGuidance(title: "길찾기 꺼짐", detail: "목적지를 선택하면 TMAP 경로 기준 방향 안내를 표시합니다.")
            refreshRadarMarkerOverlays()
            refreshGeospatial3DAnchorRequestsIfPossible(force: true)
        }
    }

    func selectNavigationDestination(_ spot: TourismSpot) {
        if navigationRouteTaskSpotID != nil, navigationRouteTaskSpotID == spot.id {
            navigationDestinationSpotID = spot.id
            selectedSpot = spot
            routeArrowDiagnostics = "\(spot.name) 길찾기 요청 중 / 중복 요청을 보내지 않습니다."
            routeArrowComputationDiagnostics = "\(spot.name) 기존 TMAP 요청 유지 / 길찾기 버튼 연타 방지"
            return
        }

        navigationRouteTask?.cancel()
        navigationRouteTask = nil
        navigationRouteTaskSpotID = nil
        isNavigationModeEnabled = true
        navigationDestinationSpotID = spot.id
        selectedSpot = spot
        routeArrowPath = nil
        activeGeospatial3DSpotIDs = activeGeospatial3DSpotIDs.intersection([spot.id])
        geospatialSessionManager.clearAllGeospatialDebugAnchors(reason: "\(spot.name) 길찾기 시작 / 선택 목적지 외 3D 마커 제거")
        routeArrowDiagnostics = "\(spot.name) 길찾기 목적지 선택 / TMAP 경로를 준비합니다."
        routeArrowComputationDiagnostics = "\(spot.name) 목적지 선택 / 현재 위치 기준 TMAP route 준비"
        setNavigationGuidance(title: "\(spot.name) 경로 준비 중", detail: "현재 위치에서 목적지까지의 TMAP 보행자 경로를 요청합니다.")
        refreshGeospatial3DAnchorRequestsIfPossible(force: true)
        refreshRadarMarkerOverlays()
        refreshRouteArrowPath()
        ensureNavigationRouteForDestination()
    }

    func searchNavigationDestinationFromInput() {
        let keyword = navigationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            navigationSearchStatus = "검색어를 입력하세요."
            return
        }

        guard apiKeys.tmap.isRuntimeConfiguredAPIKey else {
            navigationSearchStatus = "TMAP_API_KEY가 비어 있어 목적지를 검색할 수 없습니다."
            return
        }

        navigationSearchTask?.cancel()
        navigationSearchTask = nil
        let origin = stableGeospatial3DOrigin ?? latestGeospatialLocationSnapshot ?? latestLocationSnapshot
        navigationSearchStatus = "\"\(keyword)\" TMAP 목적지 검색 중..."
        setNavigationGuidance(title: "목적지 검색 중", detail: "\"\(keyword)\" 검색 결과를 기반으로 길찾기를 준비합니다.")

        navigationSearchTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let results = try await self.tmapClient.searchPOIs(
                    keyword: keyword,
                    near: origin?.coordinate
                )
                guard !Task.isCancelled else {
                    return
                }

                self.navigationSearchTask = nil
                self.navigationSearchResults = results
                guard let firstResult = results.first else {
                    self.navigationSearchStatus = "\"\(keyword)\" 검색 결과 없음"
                    self.setNavigationGuidance(title: "검색 결과 없음", detail: "목적지 이름을 더 구체적으로 입력해 주세요.")
                    return
                }

                self.navigationSearchStatus = "\"\(keyword)\" 검색 결과 \(results.count)개 / 첫 결과 \(firstResult.name)로 길찾기 시작"
                self.selectNavigationSearchResult(firstResult)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self.navigationSearchTask = nil
                self.navigationSearchResults = []
                self.navigationSearchStatus = "\"\(keyword)\" 검색 실패: \(error.localizedDescription)"
                self.setNavigationGuidance(title: "목적지 검색 실패", detail: error.localizedDescription)
            }
        }
    }

    func selectNavigationSearchResult(_ result: TMAPPOISearchResult) {
        let spot = tourismSpot(from: result)
        upsertNavigationSearchSpot(spot)
        navigationSearchQuery = result.name
        navigationSearchStatus = "\(result.name) 선택 / \(result.address) / \(result.coordinate.shortText)"
        selectNavigationDestination(spot)
    }

    private func tourismSpot(from result: TMAPPOISearchResult) -> TourismSpot {
        TourismSpot(
            id: "tmap-\(result.id)",
            name: result.name,
            address: result.address,
            districtName: "TMAP 검색",
            category: "사용자 입력 목적지",
            source: .tmap,
            geometryKind: .point,
            center: result.coordinate,
            recognitionHints: [result.name],
            notes: "사용자가 직접 입력한 TMAP POI 검색 결과입니다.",
            preferredMarkerCoordinate: result.coordinate,
            entranceCoordinate: result.coordinate
        )
    }

    private func upsertNavigationSearchSpot(_ spot: TourismSpot) {
        if let index = spots.firstIndex(where: { $0.id == spot.id }) {
            spots[index] = spot
        } else {
            spots.insert(spot, at: 0)
        }

        if let loadedIndex = loadedTourismSpots.firstIndex(where: { $0.id == spot.id }) {
            loadedTourismSpots[loadedIndex] = spot
        } else {
            loadedTourismSpots.insert(spot, at: 0)
        }
    }

    func applyIndoorDebugScenario(_ scenario: IndoorDebugScenario) {
        indoorDebugScenario = scenario
        guard isIndoorDebugModeEnabled else {
            indoorDebugStatus = "실내 디버그 모드는 꺼져 있습니다."
            return
        }

        guard let targetSpot = indoorDebugTargetSpot else {
            indoorDebugStatus = "실내 디버그 대상 POI가 없습니다. 해운대구 TourAPI 후보를 먼저 불러오세요."
            return
        }

        let targetOrigin = LocationSnapshot(
            latitude: targetSpot.center.latitude,
            longitude: targetSpot.center.longitude,
            altitude: latestGeospatialLocationSnapshot?.altitude ?? latestCoreLocationSnapshot?.altitude,
            horizontalAccuracy: 1,
            verticalAccuracy: latestGeospatialLocationSnapshot?.verticalAccuracy ?? latestCoreLocationSnapshot?.verticalAccuracy,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let offset = scenario.offsetMeters
        let debugCoordinate = LocalENUProjector.coordinate(
            eastMeters: offset.east,
            northMeters: offset.north,
            from: targetOrigin
        )
        let rawHeading = debugCoordinate.bearing(to: targetSpot.center)
        let debugHeading = scenario.reversesHeading
            ? (rawHeading + 180).normalizedDegrees
            : rawHeading.normalizedDegrees
        let snapshot = LocationSnapshot(
            latitude: debugCoordinate.latitude,
            longitude: debugCoordinate.longitude,
            altitude: targetOrigin.altitude,
            horizontalAccuracy: 1,
            verticalAccuracy: targetOrigin.verticalAccuracy,
            heading: debugHeading,
            headingAccuracy: 1,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )

        injectIndoorDebugSnapshot(snapshot, headingDegrees: debugHeading, targetSpot: targetSpot, scenario: scenario)
    }

    var indoorDebugTargetSpot: TourismSpot? {
        if let indoorDebugSelectedSpotID,
           let spot = spots.first(where: { $0.id == indoorDebugSelectedSpotID }) {
            return spot
        }

        return spots.first
    }

    var debugOverviewRows: [DebugStatusRow] {
        let mode = isIndoorDebugModeEnabled ? "실내 디버그" : "실제 위치"
        let targetName = selectedSpot?.name ?? cameraDirectionSpotName ?? "선택 없음"
        let scenarioText = isIndoorDebugModeEnabled ? indoorDebugScenario.title : "해당 없음"
        let distanceText = selectedSpotDistanceText ?? "거리 미계산"
        let navigationText = isNavigationModeEnabled
            ? (navigationDestinationSpot?.name ?? "목적지 선택 필요")
            : "꺼짐"

        return [
            DebugStatusRow(title: "모드", value: mode),
            DebugStatusRow(title: "대상", value: targetName),
            DebugStatusRow(title: "시나리오", value: scenarioText),
            DebugStatusRow(title: "길찾기", value: navigationText),
            DebugStatusRow(title: "거리", value: distanceText),
            DebugStatusRow(title: "인식", value: recognitionSummaryText)
        ]
    }

    var locationDebugRows: [DebugStatusRow] {
        var rows: [DebugStatusRow] = []
        let locationMode = isIndoorDebugModeEnabled ? "실내 디버그 origin" : "실제 위치 수신"
        rows.append(DebugStatusRow(title: "기준", value: locationMode))

        if let latestLocationSnapshot {
            rows.append(
                DebugStatusRow(
                    title: "origin",
                    value: "\(latestLocationSnapshot.source.rawValue) \(latestLocationSnapshot.coordinate.shortText) / 정확도 \(Int(latestLocationSnapshot.horizontalAccuracy))m"
                )
            )
        } else {
            rows.append(DebugStatusRow(title: "origin", value: "위치 수신 대기"))
        }

        if let cameraHeadingDegrees {
            rows.append(DebugStatusRow(title: "heading", value: "\(Int(cameraHeadingDegrees))도"))
        } else {
            rows.append(DebugStatusRow(title: "heading", value: "수신 대기"))
        }

        rows.append(DebugStatusRow(title: "3D 기준", value: compactDiagnosticText(stableOriginDiagnostics)))
        return rows
    }

    var dataDebugRows: [DebugStatusRow] {
        var rows = [
            DebugStatusRow(title: "TourAPI", value: compactDiagnosticText(tourismDataStatus)),
            DebugStatusRow(title: "TMAP", value: tmapRouteSummaryText),
            DebugStatusRow(title: "표시 후보", value: "\(spots.count)개"),
            DebugStatusRow(title: "VWorld", value: compactDiagnosticText(polygonValidationStatus)),
            DebugStatusRow(title: "Polygon 로그", value: polygonLookupLogs.isEmpty ? "없음" : "\(polygonLookupLogs.count)줄")
        ]
        rows.append(contentsOf: tmapArrivalDebugRows)
        return rows
    }

    var displayDebugRows: [DebugStatusRow] {
        let labelText: String
        if let arLabelOverlay {
            labelText = "화면 안 / x \(Int(arLabelOverlay.normalizedX * 100))% y \(Int(arLabelOverlay.normalizedY * 100))%"
        } else {
            labelText = "숨김"
        }

        let matrixText: String
        if let matrixProjectionDebugOverlay {
            matrixText = "\(matrixProjectionDebugOverlay.isInsideView ? "화면 안" : "화면 밖") / \(matrixProjectionDebugOverlay.insidePointCount)/\(matrixProjectionDebugOverlay.totalPointCount)개"
        } else {
            matrixText = "없음"
        }

        return [
            DebugStatusRow(title: "2D 라벨", value: labelText),
            DebugStatusRow(title: "edge marker", value: "\(edgeMarkerOverlays.count)개"),
            DebugStatusRow(title: "화면 후보", value: "\(onScreenCandidateMarkerOverlays.count)개"),
            DebugStatusRow(title: "레이더", value: compactDiagnosticText(radarDiagnostics)),
            DebugStatusRow(title: "경로 화살표", value: compactDiagnosticText(routeArrowDiagnostics)),
            DebugStatusRow(title: "화살표 계산", value: compactDiagnosticText(routeArrowComputationDiagnostics)),
            DebugStatusRow(title: "화살표 렌더", value: compactDiagnosticText(routeArrowRenderDiagnostics)),
            DebugStatusRow(title: "matrix", value: matrixText)
        ]
    }

    func updateRouteArrowRenderDiagnostics(_ diagnostics: String) {
        guard routeArrowRenderDiagnostics != diagnostics else {
            return
        }
        routeArrowRenderDiagnostics = diagnostics
    }

    var anchorDebugRows: [DebugStatusRow] {
        [
            DebugStatusRow(title: "활성 앵커", value: "\(activeGeospatial3DSpotIDs.count)개"),
            DebugStatusRow(title: "WGS84 후보", value: compactDiagnosticText(geospatialWGS84CandidateDiagnostics)),
            DebugStatusRow(title: "WGS84 앵커", value: compactDiagnosticText(geospatialAnchorStateDiagnostics)),
            DebugStatusRow(title: "3D 위치", value: compactDiagnosticText(buildingFacadeAnchorDiagnostics)),
            DebugStatusRow(title: "높이", value: compactDiagnosticText(buildingLabelHeightDiagnostics))
        ]
    }

    private var cameraDirectionSpotName: String? {
        guard let cameraDirectionSpotID else {
            return nil
        }

        return spots.first(where: { $0.id == cameraDirectionSpotID })?.name
    }

    private var selectedSpotDistanceText: String? {
        guard let latestLocationSnapshot,
              let spot = selectedSpot ?? indoorDebugTargetSpot else {
            return nil
        }

        let distanceMeters = latestLocationSnapshot.coordinate.distance(to: spot.center)
        return "\(Int(distanceMeters))m"
    }

    var navigationDestinationSpot: TourismSpot? {
        guard let navigationDestinationSpotID else {
            return nil
        }

        return spots.first(where: { $0.id == navigationDestinationSpotID })
    }

    private var recognitionSummaryText: String {
        switch recognitionResult {
        case let .recognized(spot, confidence, _):
            return "\(spot.name) / \(confidence.displayName)"
        case let .nearby(spot, _):
            return "\(spot.name) / 근처 후보"
        case let .ambiguous(candidates, _):
            return "후보 \(candidates.count)개"
        case .none:
            return "없음"
        }
    }

    private func compactDiagnosticText(_ text: String, maxLength: Int = 72) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        guard normalized.count > maxLength else {
            return normalized
        }

        return String(normalized.prefix(maxLength)) + "..."
    }

    private var tmapRouteSummaryText: String {
        let cachedCount = tmapArrivalRoutesBySpotID.count
        let requestCount = tmapRouteTasksBySpotID.count
        let failedCount = tmapRouteFailedSpotIDs.count

        if cachedCount == 0, requestCount == 0, failedCount == 0 {
            return "도착 좌표 없음"
        }

        var parts: [String] = []
        if cachedCount > 0 {
            parts.append("도착 좌표 \(cachedCount)개")
        }
        if requestCount > 0 {
            parts.append("요청 중 \(requestCount)개")
        }
        if failedCount > 0 {
            parts.append("실패 \(failedCount)개")
        }
        return parts.joined(separator: " / ")
    }

    private var tmapArrivalDebugRows: [DebugStatusRow] {
        spots.enumerated().compactMap { index, spot -> DebugStatusRow? in
            guard let route = tmapArrivalRoutesBySpotID[spot.id] else {
                return nil
            }

            let offsetMeters = spot.center.distance(to: route.arrivalCoordinate)
            let distanceText = route.totalDistanceMeters.map { " / 경로 \(Int($0))m" } ?? ""
            return DebugStatusRow(
                title: "TMAP \(index + 1)",
                value: "\(spot.edgeMarkerShortTitle) \(route.arrivalCoordinate.shortText) / POI 보정 \(String(format: "%.1f", offsetMeters))m\(distanceText)"
            )
        }
    }

    func updateCameraTextFromLiveOCR(_ text: String) {
        cameraTextInput = text
        runRecognition()
    }

    private func injectIndoorDebugSnapshot(
        _ snapshot: LocationSnapshot,
        headingDegrees: Double,
        targetSpot: TourismSpot,
        scenario: IndoorDebugScenario
    ) {
        latestLocationSnapshot = snapshot
        latestGeospatialLocationSnapshot = snapshot
        locationConfidence = .high
        effectiveSpatialConfidence = .high
        cameraHeadingDegrees = headingDegrees
        cameraHeadingSampleCount += 1
        cameraHeadingLastUpdatedAt = Date()
        cameraHeadingDeltaDegrees = 0
        cameraHeadingDiagnostics = "실내 디버그 heading 사용 / \(Int(headingDegrees))도 / \(scenario.title)"

        if cameraPoseSnapshot == nil {
            cameraPoseSnapshot = CameraPoseSnapshot(
                headingDegrees: headingDegrees,
                pitchDegrees: 0,
                yawDegrees: headingDegrees,
                rollDegrees: 0,
                positionX: 0,
                positionY: 0,
                positionZ: 0,
                timestamp: Date().timeIntervalSince1970
            )
            cameraPoseDiagnostics = "실내 디버그 pose fallback / pitch 0도 / heading \(Int(headingDegrees))도"
        }

        stableGeospatial3DOrigin = snapshot
        pendingStableGeospatial3DOrigin = nil
        pendingStableOriginFirstSeenAt = nil
        stableOriginLastAcceptedAt = Date()
        stableOriginIsUsableFor3DAnchors = true
        stableOriginDiagnostics = "3D stable origin 확정(실내 디버그) / 정확도 1m / \(scenario.title)"
        geospatialStatus = "실내 디버그 모드: 실제 VPS 대신 debug origin을 사용합니다."
        indoorDebugStatus = "\(targetSpot.name) / \(scenario.title) / debugOrigin \(snapshot.latitude.formatted(.number.precision(.fractionLength(6)))), \(snapshot.longitude.formatted(.number.precision(.fractionLength(6)))) / heading \(Int(headingDegrees))도"

        selectedSpot = targetSpot
        cameraTextInput = targetSpot.name
        applyNearbySpotFilter()
        updateBuildingPolygon(for: targetSpot)
        updateCameraDirectionCandidate()
        refreshSpatialTrackingConfidence()
        refreshLocalCoordinateDiagnostics()
        refreshBuildingFacadeAnchorDiagnostics()
        refreshBuildingLabelHeightDiagnostics()
        refreshMatrixProjectionComparisonDiagnostics()
        refreshEdgeMarkerOverlays()
        refreshOnScreenCandidateMarkerOverlays()
        refreshRadarMarkerOverlays()
        refreshARLabelOverlay()
        runRecognition()
    }

    func updateCameraHeading(_ headingDegrees: Double) {
        let previousHeading = cameraHeadingDegrees
        cameraHeadingDegrees = headingDegrees
        cameraHeadingSampleCount += 1
        cameraHeadingLastUpdatedAt = Date()

        if let previousHeading {
            cameraHeadingDeltaDegrees = previousHeading.angularDifference(to: headingDegrees)
            let modeText = isIndoorDebugModeEnabled ? "실내 디버그 위치 + 실제 heading" : "실시간 heading"
            cameraHeadingDiagnostics = "\(modeText) 수신 중 / 샘플 \(cameraHeadingSampleCount)개 / 변화량 \(Int(cameraHeadingDeltaDegrees ?? 0))도"
        } else {
            cameraHeadingDeltaDegrees = nil
            cameraHeadingDiagnostics = "첫 heading 수신 / 샘플 \(cameraHeadingSampleCount)개"
        }

        refreshSpatialTrackingConfidence()
        updateCameraDirectionCandidate()
        refreshLocalCoordinateDiagnostics()
        refreshBuildingFacadeAnchorDiagnostics()
        refreshBuildingLabelHeightDiagnostics()
        refreshMatrixProjectionComparisonDiagnostics()
        refreshEdgeMarkerOverlays()
        refreshOnScreenCandidateMarkerOverlays()
        refreshRouteArrowPath()
        runRecognition()
    }

    func updateCameraPose(_ pose: CameraPoseSnapshot) {
        cameraPoseSnapshot = pose
        cameraPoseDiagnostics = "pose 수신 / pitch \(Int(pose.pitchDegrees))도 / yaw \(Int(pose.yawDegrees))도 / roll \(Int(pose.rollDegrees))도 / position x \(pose.positionX.formatted(.number.precision(.fractionLength(2)))) y \(pose.positionY.formatted(.number.precision(.fractionLength(2)))) z \(pose.positionZ.formatted(.number.precision(.fractionLength(2))))"
        updateCameraHeading(pose.headingDegrees)
    }

    func updateCameraProjection(_ projection: CameraProjectionSnapshot) {
        cameraProjectionSnapshot = projection
        cameraProjectionDiagnostics = projection.diagnosticText
        refreshLocalCoordinateDiagnostics()
        refreshBuildingFacadeAnchorDiagnostics()
        refreshBuildingLabelHeightDiagnostics()
        refreshMatrixProjectionComparisonDiagnostics()
        refreshARLabelOverlay()
        refreshEdgeMarkerOverlays()
        refreshOnScreenCandidateMarkerOverlays()
        refreshRadarMarkerOverlays()
    }

    func runMockRecognition() {
        cameraTextInput = "투썸플레이스"
        locationConfidence = .high
        refreshSpatialTrackingConfidence()
        runRecognition()
    }

    func runRecognition() {
        // 길찾기 중에는 건물 인식 파이프라인을 돌리지 않는다(둘러보기 전용, 발열/CPU 절감).
        // 단 길찾기 화살표/리본 갱신은 유지한다.
        guard !isNavigationModeEnabled else {
            refreshRouteArrowPath()
            return
        }

        recognitionResult = recognitionPipeline.recognize(
            candidates: spots,
            cameraText: cameraTextInput,
            locationConfidence: effectiveSpatialConfidence,
            cameraDirectionSpotIDs: Set([cameraDirectionSpotID].compactMap { $0 }),
            polygonValidatedSpotIDs: Set([polygonValidatedSpotID].compactMap { $0 })
        )

        if case let .recognized(spot, _, _) = recognitionResult {
            selectedSpot = spot
            refreshEdgeMarkerOverlays()
        }
        refreshARLabelOverlay()
        refreshRadarMarkerOverlays()
        refreshRouteArrowPath()
    }

    func selectCandidate(_ spot: TourismSpot) {
        selectedSpot = spot
        recognitionResult = .recognized(
            spot: spot,
            confidence: .medium,
            reason: "사용자가 모호한 건물 후보 중 \(spot.name)을 선택했습니다."
        )
        refreshEdgeMarkerOverlays()
        refreshARLabelOverlay()
        refreshRadarMarkerOverlays()
        refreshRouteArrowPath()
    }

    private func updateCameraDirectionCandidate() {
        // 길찾기 중에는 카메라 방향 후보/VWorld Polygon 자동 조회(네트워크)를 돌리지 않는다.
        // 길찾기는 TMAP 경로 기반이라 이 신호가 필요 없고, 네트워크/CPU/발열만 늘린다.
        guard !isNavigationModeEnabled else {
            return
        }

        guard let heading = cameraHeadingDegrees else {
            cameraDirectionSpotID = nil
            polygonValidatedSpotID = nil
            cameraDirectionStatus = "카메라 heading을 아직 받지 못했습니다."
            polygonValidationStatus = "카메라 heading이 없어 Polygon 자동 후보를 계산할 수 없습니다."
            spatialAlignmentDiagnostics = "카메라 heading이 없어 선택 Polygon 정렬을 계산할 수 없습니다."
            refreshLocalCoordinateDiagnostics()
            buildingFacadeAnchorDiagnostics = "카메라 heading이 없어 현재 방향 후보의 3D 외벽 후보점을 계산하지 않았습니다."
            buildingLabelHeightDiagnostics = "카메라 heading이 없어 현재 방향 후보의 3D 라벨 높이 기준값을 계산하지 않았습니다."
            polygonProjectionDiagnostics = "카메라 heading이 없어 Polygon 화면 투영을 계산할 수 없습니다."
            matrixProjectionComparisonDiagnostics = "카메라 heading이 없어 projection matrix 비교를 계산할 수 없습니다."
            matrixProjectionDebugOverlay = nil
            edgeMarkerOverlays = []
            onScreenCandidateMarkerOverlays = []
            arLabelOverlay = nil
            arLabelOverlayDiagnostics = "카메라 heading이 없어 AR 라벨 위치를 계산할 수 없습니다."
            polygonLookupTask?.cancel()
            polygonLookupInFlightSpotID = nil
            return
        }

        guard let latestLocationSnapshot else {
            cameraDirectionSpotID = nil
            polygonValidatedSpotID = nil
            cameraDirectionStatus = "현재 위치가 없어 카메라 방향 후보를 계산할 수 없습니다."
            polygonValidationStatus = "현재 위치가 없어 Polygon 자동 후보를 계산할 수 없습니다."
            spatialAlignmentDiagnostics = "현재 위치가 없어 선택 Polygon 정렬을 계산할 수 없습니다."
            refreshLocalCoordinateDiagnostics()
            refreshBuildingFacadeAnchorDiagnostics()
            refreshBuildingLabelHeightDiagnostics()
            polygonProjectionDiagnostics = "현재 위치가 없어 Polygon 화면 투영을 계산할 수 없습니다."
            matrixProjectionComparisonDiagnostics = "현재 위치가 없어 projection matrix 비교를 계산할 수 없습니다."
            matrixProjectionDebugOverlay = nil
            edgeMarkerOverlays = []
            onScreenCandidateMarkerOverlays = []
            arLabelOverlay = nil
            arLabelOverlayDiagnostics = "현재 위치가 없어 AR 라벨 위치를 계산할 수 없습니다."
            polygonLookupTask?.cancel()
            polygonLookupInFlightSpotID = nil
            return
        }

        guard let candidate = cameraDirectionCandidateProvider.candidate(
            from: latestLocationSnapshot,
            cameraHeadingDegrees: heading,
            spots: spots
        ) else {
            cameraDirectionSpotID = nil
            polygonValidatedSpotID = nil
            cameraDirectionStatus = "카메라 방향과 일치하는 관광지 후보가 없습니다."
            polygonValidationStatus = "카메라 시야 방향과 일치하는 목업 Polygon 후보가 없습니다."
            spatialAlignmentDiagnostics = "현재 heading과 일치하는 후보가 없어 Polygon 정렬을 계산하지 않았습니다."
            refreshLocalCoordinateDiagnostics()
            refreshBuildingFacadeAnchorDiagnostics()
            refreshBuildingLabelHeightDiagnostics()
            polygonProjectionDiagnostics = "현재 heading과 일치하는 후보가 없어 Polygon 화면 투영을 계산하지 않았습니다."
            matrixProjectionComparisonDiagnostics = "현재 heading과 일치하는 후보가 없어 projection matrix 비교를 계산하지 않았습니다."
            matrixProjectionDebugOverlay = nil
            edgeMarkerOverlays = []
            onScreenCandidateMarkerOverlays = []
            arLabelOverlay = nil
            arLabelOverlayDiagnostics = "현재 heading과 일치하는 후보가 없어 AR 라벨을 숨깁니다."
            polygonLookupTask?.cancel()
            polygonLookupInFlightSpotID = nil
            return
        }

        let previousCandidateID = cameraDirectionSpotID
        cameraDirectionSpotID = candidate.spot.id
        cameraDirectionStatus = "\(candidate.spot.name) 방향 후보 / 각도 차이 \(Int(candidate.headingDifferenceDegrees))도 / 거리 \(Int(candidate.distanceMeters))m"
        updateSpatialAlignmentDiagnostics(for: candidate)
        updateBuildingPolygon(for: candidate.spot)
        refreshLocalCoordinateDiagnostics()
        refreshBuildingFacadeAnchorDiagnostics()
        refreshBuildingLabelHeightDiagnostics()
        refreshMatrixProjectionComparisonDiagnostics()
        refreshSceneSemanticsScoring()

        if previousCandidateID != candidate.spot.id {
            runRecognition()
        }
    }

    private func updateBuildingPolygon(for spot: TourismSpot) {
        if let polygon = buildingPolygonsBySpotID[spot.id] {
            let resolvedHeight = resolvedBuildingHeightsBySpotID[spot.id] ?? buildingHeightResolver.resolve(polygon: polygon)
            resolvedBuildingHeightsBySpotID[spot.id] = resolvedHeight
            polygonValidatedSpotID = spot.id
            polygonValidationStatus = "\(spot.name) 브이월드 Polygon 확보 / 외곽 좌표 \(polygon.vertexCount)개 / 높이 \(resolvedHeight.displayText)"
            updateSpatialAlignmentDiagnostics(for: spot, polygon: polygon)
            refreshEdgeMarkerOverlays()
            refreshLocalCoordinateDiagnostics()
            refreshBuildingFacadeAnchorDiagnostics()
            refreshBuildingLabelHeightDiagnostics()
            refreshMatrixProjectionComparisonDiagnostics()
            refreshSceneSemanticsScoring()
            return
        }

        if polygonLookupInFlightSpotID == spot.id {
            polygonValidationStatus = "\(spot.name) 브이월드 Polygon 조회 중입니다."
            return
        }

        if polygonLookupNotFoundSpotIDs.contains(spot.id) {
            polygonValidatedSpotID = nil
            polygonValidationStatus = "\(spot.name) 주변에서 브이월드 건물 Polygon을 찾지 못했습니다."
            return
        }

        polygonValidatedSpotID = nil
        polygonLookupStartedAt = Date()
        polygonLookupFinishedAt = nil
        polygonLookupLogs = []
        appendPolygonLookupLog("\(spot.name) Polygon 조회 시작")
        polygonValidationStatus = "\(spot.name) 브이월드 Polygon 조회 중입니다."
        polygonLookupInFlightSpotID = spot.id
        polygonLookupTask?.cancel()
        polygonLookupTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let lookupResult: VWorldPolygonLookupResult
                if let diagnosticClient = self.vworldClient as? any VWorldDiagnosticClient {
                    lookupResult = try await diagnosticClient.fetchBuildingPolygonWithDiagnostics(for: spot)
                } else {
                    lookupResult = VWorldPolygonLookupResult(
                        polygon: try await self.vworldClient.fetchBuildingPolygon(for: spot),
                        logs: ["브이월드 진단 로그 미지원 클라이언트"]
                    )
                }
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self.cameraDirectionSpotID == spot.id else {
                        return
                    }

                    self.appendPolygonLookupLogs(lookupResult.logs)

                    if let polygon = lookupResult.polygon {
                        let resolvedHeight = self.buildingHeightResolver.resolve(polygon: polygon)
                        self.buildingPolygonsBySpotID[spot.id] = polygon
                        self.resolvedBuildingHeightsBySpotID[spot.id] = resolvedHeight
                        self.polygonLookupNotFoundSpotIDs.remove(spot.id)
                        self.polygonValidatedSpotID = spot.id
                        self.polygonLookupFinishedAt = Date()
                        self.polygonLookupInFlightSpotID = nil
                        self.appendPolygonLookupLog("앱 높이 결정: \(resolvedHeight.displayText)")
                        self.appendPolygonLookupLog("앱 높이 결정 사유: \(resolvedHeight.explanation)")
                        self.polygonValidationStatus = "\(spot.name) 브이월드 Polygon 확보 / 외곽 좌표 \(polygon.vertexCount)개 / 높이 \(resolvedHeight.displayText)"
                        self.updateSpatialAlignmentDiagnostics(for: spot, polygon: polygon)
                        self.refreshLocalCoordinateDiagnostics()
                        self.refreshBuildingFacadeAnchorDiagnostics()
                        self.refreshBuildingLabelHeightDiagnostics()
                        self.refreshMatrixProjectionComparisonDiagnostics()
                        self.refreshSceneSemanticsScoring()
                    } else {
                        self.polygonLookupNotFoundSpotIDs.insert(spot.id)
                        self.polygonValidatedSpotID = nil
                        self.polygonLookupFinishedAt = Date()
                        self.polygonLookupInFlightSpotID = nil
                        self.polygonValidationStatus = "\(spot.name) 주변에서 브이월드 건물 Polygon을 찾지 못했습니다."
                    }
                    self.runRecognition()
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard self.cameraDirectionSpotID == spot.id else {
                        return
                    }
                    self.polygonValidatedSpotID = nil
                    self.polygonLookupFinishedAt = Date()
                    self.polygonLookupInFlightSpotID = nil
                    self.appendPolygonLookupLog("브이월드 조회 실패: \(error.localizedDescription)")
                    self.polygonValidationStatus = "\(spot.name) 브이월드 Polygon 조회 실패: \(error.localizedDescription)"
                    self.runRecognition()
                }
            }
        }
    }

    private func useMockFallback(reason: String) {
        loadedTourismSpots = MockTourismSpots.testBuildings
        clearManualSpatialSelections()
        applyNearbySpotFilter(fallbackReason: reason)
        updateCameraDirectionCandidate()
        runRecognition()
    }

    private func applyMockSpots() {
        loadedTourismSpots = MockTourismSpots.testBuildings
        spots = MockTourismSpots.testBuildings
        clearManualSpatialSelections()
        tourismDataStatus = "TourAPI 김해/부산 후보는 비활성화되어 있고 테스트 목업 건물 \(MockTourismSpots.testBuildings.count)개를 사용 중입니다."
        updateCameraDirectionCandidate()
        runRecognition()
    }

    private func clearManualSpatialSelections() {
        polygonValidatedSpotID = nil
        polygonLookupStartedAt = nil
        polygonLookupFinishedAt = nil
        polygonLookupLogs = []
        polygonLookupInFlightSpotID = nil
        polygonPrefetchTasksBySpotID.values.forEach { $0.cancel() }
        polygonPrefetchTasksBySpotID = [:]
        polygonLookupNotFoundSpotIDs = []
        tmapRouteTasksBySpotID.values.forEach { $0.cancel() }
        tmapRouteTasksBySpotID = [:]
        tmapRouteFailedSpotIDs = []
        navigationRouteTask?.cancel()
        navigationRouteTask = nil
        navigationRouteTaskSpotID = nil
        navigationDestinationSpotID = nil
        isNavigationModeEnabled = false
        tmapArrivalRoutesBySpotID = [:]
        tmapRouteStatus = "후보 초기화로 TMAP 도착 좌표를 초기화했습니다."
        resolvedBuildingHeightsBySpotID = [:]
        sceneSemanticsEvidenceBySpotID = [:]
        sceneSemanticsScoringDiagnostics = "후보 초기화로 Scene Semantics 라벨 보정도 초기화했습니다."
        stableGeospatial3DOrigin = nil
        pendingStableGeospatial3DOrigin = nil
        pendingStableOriginFirstSeenAt = nil
        stableOriginLastAcceptedAt = nil
        stableOriginIsUsableFor3DAnchors = false
        lastGeospatial3DAnchorRefreshAt = nil
        stableOriginDiagnostics = "후보 초기화로 3D stable origin도 초기화했습니다."
        lastRequestedTerrainAnchorSpotIDs = []
            activeGeospatial3DSpotIDs = []
            routeArrowPath = nil
            routeArrowDiagnostics = "후보 초기화로 길찾기 화살표를 초기화했습니다."
            routeArrowComputationDiagnostics = "후보 초기화로 화살표 계산 로그를 초기화했습니다."
            routeArrowRenderDiagnostics = "후보 초기화로 화살표 렌더 로그를 초기화했습니다."
            geospatialSessionManager.clearAllGeospatialDebugAnchors(reason: "후보 초기화로 WGS84 Anchor를 모두 제거했습니다.")
        stableFacadeSelectionsBySpotID = [:]
        fixedNearestFacadeCandidatesBySpotID = [:]
        arLabelOverlay = nil
        arLabelOverlayDiagnostics = "후보 초기화로 AR 라벨도 초기화했습니다."
        matrixProjectionDebugOverlay = nil
        edgeMarkerOverlays = []
        onScreenCandidateMarkerOverlays = []
        localCoordinateDiagnostics = "후보 초기화로 local ENU 좌표 변환도 초기화했습니다."
        buildingFacadeAnchorDiagnostics = "후보 초기화로 3D 외벽 후보점도 초기화했습니다."
        buildingLabelHeightDiagnostics = "후보 초기화로 3D 라벨 높이 기준값도 초기화했습니다."
        geospatialWGS84CandidateDiagnostics = "후보 초기화로 WGS84 Anchor 후보도 초기화했습니다."
        geospatialAnchorStateDiagnostics = "후보 초기화로 WGS84 Anchor 생성 상태도 초기화했습니다."
        matrixProjectionComparisonDiagnostics = "후보 초기화로 projection matrix 비교도 초기화했습니다."
        cameraDirectionSpotID = nil
        selectedSpot = nil
        polygonLookupTask?.cancel()
    }

    private func applyNearbySpotFilter(fallbackReason: String? = nil) {
        guard let latestLocationSnapshot else {
            spots = []
            if let fallbackReason {
                tourismDataStatus = "TourAPI 대신 테스트 목업 후보를 불러왔지만, 현재 위치를 기다리는 중입니다. 사유: \(fallbackReason)"
            } else if loadedTourismSpots.isEmpty {
                tourismDataStatus = "TourAPI 김해 중심 관광지 데이터를 아직 불러오지 않았습니다."
            } else if loadedTourismSpots.isMockFallback {
                tourismDataStatus = "TourAPI 대신 테스트 목업 후보를 불러왔고, 현재 위치를 기다리는 중입니다."
            } else {
                tourismDataStatus = "TourAPI 김해 중심 관광지 \(loadedTourismSpots.count)개를 불러왔고, 현재 위치를 기다리는 중입니다."
            }
            return
        }

        let currentLocation = CLLocation(
            latitude: latestLocationSnapshot.latitude,
            longitude: latestLocationSnapshot.longitude
        )
        let filteredSpots = loadedTourismSpots.filter { spot in
            let spotLocation = CLLocation(
                latitude: spot.center.latitude,
                longitude: spot.center.longitude
            )
            return currentLocation.distance(from: spotLocation) <= nearbySpotRadiusMeters
        }

        spots = filteredSpots
        dropSelectionsOutsideVisibleSpots()
        updateTMAPRouteStatus(extra: "자동 프리패치 비활성화 / 길찾기 목적지 선택 또는 실내 테스트 적용 시에만 호출")
        refreshRadarMarkerOverlays()
        if let stableGeospatial3DOrigin, stableOriginReadyFor3DAnchors {
            prefetchNearbyBuildingPolygonsFor3DAnchors(from: stableGeospatial3DOrigin)
        }

        let radiusText = "\(Int(nearbySpotRadiusMeters / 1_000))km"
        if let fallbackReason {
            tourismDataStatus = "TourAPI 대신 테스트 목업 후보를 사용 중입니다. 현재 위치 기준 \(radiusText) 이내 \(filteredSpots.count)/\(loadedTourismSpots.count)개 표시. 사유: \(fallbackReason)"
        } else if loadedTourismSpots.isMockFallback {
            tourismDataStatus = "TourAPI 대신 테스트 목업 후보를 사용 중입니다. 현재 위치 기준 \(radiusText) 이내 \(filteredSpots.count)/\(loadedTourismSpots.count)개 표시."
        } else {
            tourismDataStatus = "TourAPI 김해 중심 관광지 \(loadedTourismSpots.count)개 중 현재 위치 기준 \(radiusText) 이내 \(filteredSpots.count)개를 표시합니다."
        }
    }

    private func dropSelectionsOutsideVisibleSpots() {
        let visibleSpotIDs = Set(spots.map(\.id))

        if let polygonValidatedSpotID, !visibleSpotIDs.contains(polygonValidatedSpotID) {
            self.polygonValidatedSpotID = nil
        }
        if let cameraDirectionSpotID, !visibleSpotIDs.contains(cameraDirectionSpotID) {
            self.cameraDirectionSpotID = nil
        }
        if let selectedSpot, !visibleSpotIDs.contains(selectedSpot.id) {
            self.selectedSpot = nil
        }
        if let navigationDestinationSpotID, !visibleSpotIDs.contains(navigationDestinationSpotID) {
            self.navigationDestinationSpotID = nil
            self.routeArrowPath = nil
            routeArrowDiagnostics = "길찾기 목적지가 표시 후보 밖이라 초기화했습니다."
            routeArrowComputationDiagnostics = "길찾기 목적지가 현재 표시 후보 밖입니다."
        }
        tmapArrivalRoutesBySpotID = tmapArrivalRoutesBySpotID.filter { visibleSpotIDs.contains($0.key) }
        tmapRouteFailedSpotIDs = tmapRouteFailedSpotIDs.filter { visibleSpotIDs.contains($0) }
        edgeMarkerOverlays.removeAll { !visibleSpotIDs.contains($0.id) }
        onScreenCandidateMarkerOverlays.removeAll { !visibleSpotIDs.contains($0.id) }
        radarMarkerOverlays.removeAll { !visibleSpotIDs.contains($0.id) }
        if let routeArrowPath, !visibleSpotIDs.contains(routeArrowPath.spotID) {
            self.routeArrowPath = nil
            routeArrowDiagnostics = "길찾기 화살표 숨김 / 표시 후보 밖"
            routeArrowComputationDiagnostics = "routeArrowPath spotID가 현재 표시 후보 밖입니다."
        }
    }

    private func prefetchTMAPArrivalRoutes(from origin: LocationSnapshot) {
        guard apiKeys.tmap.isRuntimeConfiguredAPIKey else {
            tmapRouteStatus = "TMAP_API_KEY가 비어 있어 도착 좌표를 조회하지 않습니다."
            return
        }

        let candidates = spots
            .sorted {
                origin.coordinate.distance(to: $0.center) < origin.coordinate.distance(to: $1.center)
            }
            .filter { spot in
                tmapArrivalRoutesBySpotID[spot.id] == nil
                    && tmapRouteTasksBySpotID[spot.id] == nil
                    && !tmapRouteFailedSpotIDs.contains(spot.id)
            }
            .prefix(maxActiveGeospatial3DAnchorCount)

        if candidates.isEmpty {
            updateTMAPRouteStatus()
            return
        }

        updateTMAPRouteStatus(extra: "조회 중 \(candidates.count)개")
        for spot in candidates {
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    let route = try await self.tmapClient.fetchPedestrianRoute(
                        from: origin.coordinate,
                        to: spot
                    )
                    guard !Task.isCancelled else {
                        return
                    }

                    self.tmapRouteTasksBySpotID[spot.id] = nil
                    self.tmapArrivalRoutesBySpotID[spot.id] = route
                    self.updateTMAPRouteStatus()
                    self.refreshRouteArrowPath()
                    self.refreshGeospatial3DAnchorRequestsIfPossible(force: true)
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    self.tmapRouteTasksBySpotID[spot.id] = nil
                    self.tmapRouteFailedSpotIDs.insert(spot.id)
                    self.updateTMAPRouteStatus(extra: "\(spot.name) 실패: \(error.localizedDescription)")
                    self.refreshRouteArrowPath()
                }
            }
            tmapRouteTasksBySpotID[spot.id] = task
        }
    }

    private func updateTMAPRouteStatus(extra: String? = nil) {
        let routeSummaries = spots.compactMap { spot -> String? in
            guard let route = tmapArrivalRoutesBySpotID[spot.id] else {
                return nil
            }
            let offsetMeters = spot.center.distance(to: route.arrivalCoordinate)
            return "\(spot.name) 도착 \(route.arrivalCoordinate.shortText) / POI 보정 \(String(format: "%.1f", offsetMeters))m"
        }

        let failedText = tmapRouteFailedSpotIDs.isEmpty
            ? ""
            : " / 실패 \(tmapRouteFailedSpotIDs.count)개"
        let inFlightText = tmapRouteTasksBySpotID.isEmpty
            ? ""
            : " / 요청 중 \(tmapRouteTasksBySpotID.count)개"
        let extraText = extra.map { " / \($0)" } ?? ""

        if routeSummaries.isEmpty {
            tmapRouteStatus = "TMAP 도착 좌표 없음\(inFlightText)\(failedText)\(extraText)"
        } else {
            tmapRouteStatus = "TMAP 도착 좌표 \(routeSummaries.count)개 / " + routeSummaries.joined(separator: " | ") + inFlightText + failedText + extraText
        }
    }

    private func ensureNavigationRouteForDestination() {
        guard isNavigationModeEnabled else {
            return
        }

        guard let destination = navigationDestinationSpot else {
            routeArrowPath = nil
            routeArrowDiagnostics = "길찾기 모드 켜짐 / 목적지를 선택하세요."
            routeArrowComputationDiagnostics = "목적지 없음 / TMAP 요청 안 함"
            return
        }

        if isIndoorDebugModeEnabled, !hasAppliedIndoorNavigationMapTapLocation {
            routeArrowPath = nil
            routeArrowDiagnostics = "\(destination.name) 실내 테스트 대기 / 지도에서 내 위치를 탭하고 적용하세요."
            routeArrowComputationDiagnostics = "\(destination.name) 실내 테스트 위치 미적용 / TMAP 요청 안 함"
            return
        }

        guard let origin = stableGeospatial3DOrigin ?? latestGeospatialLocationSnapshot ?? latestLocationSnapshot else {
            routeArrowPath = nil
            routeArrowDiagnostics = "\(destination.name) 길찾기 대기 / 현재 위치 수신 필요"
            routeArrowComputationDiagnostics = "\(destination.name) / origin 없음 / CoreLocation 또는 ARCore Geospatial snapshot 대기"
            return
        }

        guard navigationRouteTask == nil else {
            routeArrowDiagnostics = "\(destination.name) TMAP 요청 중 / 중복 호출 방지"
            routeArrowComputationDiagnostics = "\(destination.name) 기존 navigationRouteTask 유지 / 새 요청 안 함"
            return
        }

        if shouldDebounceNavigationRouteRequest(destination: destination, origin: origin) {
            routeArrowDiagnostics = "\(destination.name) 길찾기 요청 무시 / 같은 위치에서 너무 빠른 재요청"
            routeArrowComputationDiagnostics = "\(destination.name) 연타 방지 / origin \(origin.coordinate.shortText) / \(String(format: "%.1f", tmapRouteDebounceInterval))초 이내 중복 요청"
            return
        }

        guard apiKeys.tmap.isRuntimeConfiguredAPIKey else {
            let route = fallbackNavigationRoute(destination: destination, from: origin)
            tmapArrivalRoutesBySpotID[destination.id] = route
            routeArrowDiagnostics = "\(destination.name) TMAP 키 없음 / POI 직선 fallback 경로 사용"
            routeArrowComputationDiagnostics = routeSummaryDiagnostics(
                destination: destination,
                route: route,
                origin: origin,
                source: "POI fallback"
            )
            refreshRadarMarkerOverlays()
            refreshRouteArrowPath()
            refreshGeospatial3DAnchorRequestsIfPossible(force: true)
            return
        }

        routeArrowPath = nil
        routeArrowDiagnostics = "\(destination.name) TMAP 보행자 경로 요청 중 / 현재 위치 기준"
        routeArrowComputationDiagnostics = "\(destination.name) TMAP 요청 시작 / origin \(origin.coordinate.shortText) / destination \(destination.center.shortText)"
        updateTMAPRouteStatus(extra: "\(destination.name) 길찾기 요청 중")
        recordNavigationRouteRequest(destination: destination, origin: origin)

        navigationRouteTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let route = try await self.tmapClient.fetchPedestrianRoute(
                    from: origin.coordinate,
                    to: destination
                )
                guard !Task.isCancelled else {
                    return
                }

                self.navigationRouteTask = nil
                self.navigationRouteTaskSpotID = nil
                self.tmapRouteFailedSpotIDs.remove(destination.id)
                self.tmapArrivalRoutesBySpotID[destination.id] = route
                self.routeArrowComputationDiagnostics = self.routeSummaryDiagnostics(
                    destination: destination,
                    route: route,
                    origin: origin,
                    source: "TMAP 응답 성공"
                )
                self.updateTMAPRouteStatus(extra: "\(destination.name) 길찾기 경로 확보")
                self.refreshRadarMarkerOverlays()
                self.refreshRouteArrowPath()
                self.refreshGeospatial3DAnchorRequestsIfPossible(force: true)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self.navigationRouteTask = nil
                self.navigationRouteTaskSpotID = nil
                self.tmapRouteFailedSpotIDs.insert(destination.id)
                let route = self.fallbackNavigationRoute(destination: destination, from: origin)
                self.tmapArrivalRoutesBySpotID[destination.id] = route
                self.updateTMAPRouteStatus(extra: "\(destination.name) 실패: \(error.localizedDescription)")
                self.routeArrowDiagnostics = "\(destination.name) TMAP 요청 실패 / POI 직선 fallback 경로 사용"
                self.routeArrowComputationDiagnostics = self.routeSummaryDiagnostics(
                    destination: destination,
                    route: route,
                    origin: origin,
                    source: "TMAP 실패 fallback: \(error.localizedDescription)"
                )
                self.refreshRadarMarkerOverlays()
                self.refreshRouteArrowPath()
                self.refreshGeospatial3DAnchorRequestsIfPossible(force: true)
            }
        }
    }

    private func shouldDebounceNavigationRouteRequest(
        destination: TourismSpot,
        origin: LocationSnapshot
    ) -> Bool {
        guard lastNavigationRouteRequestSpotID == destination.id,
              let lastNavigationRouteRequestOrigin,
              let lastNavigationRouteRequestAt else {
            return false
        }

        let elapsed = Date().timeIntervalSince(lastNavigationRouteRequestAt)
        let originDelta = lastNavigationRouteRequestOrigin.distance(to: origin.coordinate)
        return elapsed < tmapRouteDebounceInterval && originDelta <= tmapRouteDebounceDistanceMeters
    }

    private func recordNavigationRouteRequest(
        destination: TourismSpot,
        origin: LocationSnapshot
    ) {
        navigationRouteTaskSpotID = destination.id
        lastNavigationRouteRequestSpotID = destination.id
        lastNavigationRouteRequestOrigin = origin.coordinate
        lastNavigationRouteRequestAt = Date()
    }

    private func fallbackNavigationRoute(
        destination: TourismSpot,
        from origin: LocationSnapshot
    ) -> TMAPPedestrianRoute {
        let distance = origin.coordinate.distance(to: destination.center)
        return TMAPPedestrianRoute(
            destinationName: destination.name,
            requestedStart: origin.coordinate,
            requestedDestination: destination.center,
            arrivalCoordinate: destination.center,
            routeCoordinates: [origin.coordinate, destination.center],
            totalDistanceMeters: distance,
            totalTimeSeconds: nil
        )
    }

    private func routeSummaryDiagnostics(
        destination: TourismSpot,
        route: TMAPPedestrianRoute,
        origin: LocationSnapshot,
        source: String
    ) -> String {
        let routeLength = routePolylineLengthMeters(route.routeCoordinates)
        let startDelta = route.requestedStart.distance(to: origin.coordinate)
        let poiOffset = destination.center.distance(to: route.arrivalCoordinate)
        let totalDistanceText = route.totalDistanceMeters.map { "\(Int($0))m" } ?? "없음"
        let totalTimeText = route.totalTimeSeconds.map { "\(Int($0))초" } ?? "없음"
        return "\(destination.name) \(source) / route 좌표 \(route.routeCoordinates.count)개 / polyline \(Int(routeLength))m / 총거리 \(totalDistanceText) / 예상시간 \(totalTimeText) / 시작점 차이 \(Int(startDelta))m / 도착 \(route.arrivalCoordinate.shortText) / POI-도착 보정 \(String(format: "%.1f", poiOffset))m"
    }

    private func refreshRouteArrowPath() {
        // 기본은 도착 핀/바닥 리본/회전 배너 없음. 아래 분기에서 안내 가능할 때만 다시 설정한다.
        arrivalPin = nil
        routeRibbonPath = nil
        navigationTurnBanner = nil
        guard isNavigationModeEnabled else {
            routeArrowPath = nil
            routeArrowDiagnostics = "길찾기 모드 꺼짐 / 목적지를 선택하면 화살표를 표시합니다."
            routeArrowComputationDiagnostics = "길찾기 모드 꺼짐 / routeArrowPath nil"
            setNavigationGuidance(title: "길찾기 꺼짐", detail: "목적지를 선택하면 TMAP 경로 기준 방향 안내를 표시합니다.")
            return
        }

        guard navigationDestinationSpotID != nil else {
            routeArrowPath = nil
            routeArrowDiagnostics = "길찾기 화살표 숨김 / 목적지를 선택하세요."
            routeArrowComputationDiagnostics = "목적지 미선택 / routeArrowPath nil"
            setNavigationGuidance(title: "목적지를 선택하세요", detail: "길찾기 모드에서 안내할 관광지/건물을 선택해야 합니다.")
            return
        }

        guard let origin = stableGeospatial3DOrigin ?? latestGeospatialLocationSnapshot ?? latestLocationSnapshot else {
            routeArrowPath = nil
            routeArrowDiagnostics = "길찾기 화살표 숨김 / 현재 위치 기준 없음"
            routeArrowComputationDiagnostics = "origin 없음 / routeArrowPath nil"
            setNavigationGuidance(title: "현재 위치 대기", detail: "CoreLocation 또는 ARCore Geospatial 위치가 들어오면 방향 안내를 계산합니다.")
            return
        }

        guard let targetSpot = routeArrowTargetSpot() else {
            routeArrowPath = nil
            routeArrowDiagnostics = "길찾기 화살표 숨김 / 선택 목적지가 표시 후보 밖"
            routeArrowComputationDiagnostics = "선택 목적지가 spots 목록에 없음 / routeArrowPath nil"
            setNavigationGuidance(title: "목적지 후보 없음", detail: "선택한 목적지가 현재 후보 목록에 없어 안내를 계산하지 못했습니다.")
            return
        }

        guard let route = tmapArrivalRoutesBySpotID[targetSpot.id] else {
            routeArrowPath = nil
            routeArrowDiagnostics = "\(targetSpot.name) 길찾기 화살표 대기 / TMAP 경로 없음"
            routeArrowComputationDiagnostics = "\(targetSpot.name) TMAP route 없음 / routeArrowPath nil"
            setNavigationGuidance(title: "\(targetSpot.name) 경로 대기", detail: "TMAP 보행자 경로 응답을 기다리는 중입니다.")
            return
        }

        // 3.6 위치 불안정 대응: 현재 위치를 오차 원으로 보고 경로선 스냅/위치 튐 유지를 적용한 뒤,
        // 이후 도착/회전/방향 안내는 모두 이 보정 위치(guidedOrigin)를 기준으로 계산한다.
        let guidanceFix = guidanceStabilizer.stabilize(
            rawCoordinate: origin.coordinate,
            accuracyRadiusMeters: origin.horizontalAccuracy,
            routeCoordinates: route.routeCoordinates,
            now: Date()
        )
        let guidedOrigin = origin.replacingCoordinate(guidanceFix.coordinate)
        updateNavigationStabilityDiagnostics(guidanceFix: guidanceFix, rawOrigin: origin)

        let arrivalDistance = guidedOrigin.coordinate.distance(to: route.arrivalCoordinate)
        if arrivalDistance <= routeArrivalCompletionMeters {
            routeArrowPath = nil
            // 도착: 길안내 종료 + 목적지 방향 3D 대형 핀 표시 + 목적지 2D 라벨/edge marker 숨김.
            arrivalPin = ArrivalPinSnapshot(
                spotID: targetSpot.id,
                spotName: targetSpot.name,
                bearingDegrees: guidedOrigin.coordinate.bearing(to: route.arrivalCoordinate),
                distanceMeters: arrivalDistance
            )
            edgeMarkerOverlays = []
            arLabelOverlay = nil
            routeArrowDiagnostics = "\(targetSpot.name) 도착 완료 / TMAP 도착 좌표 \(Int(arrivalDistance))m 이내 / 길안내 종료"
            routeArrowComputationDiagnostics = "\(targetSpot.name) 도착 완료 / AR 화살표 제거 / 목적지 방향 3D 도착 핀 표시"
            updateNavigationGuidance(for: route, targetSpot: targetSpot, origin: guidedOrigin, guidanceFix: guidanceFix)
            return
        }

        // 안내 중(도착 전): 가는 방향으로 뻗는 바닥 리본을 계산한다. 위치/heading이 불안정하면 숨긴다.
        routeRibbonPath = navigationRibbonSnapshot(
            for: route,
            targetSpot: targetSpot,
            origin: guidedOrigin,
            guidanceFix: guidanceFix
        )

        let arrows = routeArrowSnapshots(
            for: route,
            from: guidedOrigin,
            accuracyRadiusMeters: guidanceFix.accuracyRadiusMeters,
            allowsTurnCommitment: guidanceFix.allowsTurnCommitment
        )
        guard !arrows.isEmpty else {
            routeArrowPath = nil
            routeArrowDiagnostics = "\(targetSpot.name) 전방 3D 화살표 숨김 / \(Int(routeTurnBoundaryMeters))m turn boundary 안 활성 회전 없음 / \(guidanceFix.quality.displayName)"
            routeArrowComputationDiagnostics = routeArrowRejectionDiagnostics(
                route: route,
                origin: guidedOrigin,
                targetSpot: targetSpot
            )
            updateNavigationGuidance(for: route, targetSpot: targetSpot, origin: guidedOrigin, guidanceFix: guidanceFix)
            return
        }

        routeArrowPath = RouteArrowPathSnapshot(
            spotID: targetSpot.id,
            spotName: targetSpot.name,
            arrows: arrows
        )
        if let firstArrow = arrows.first {
            // 거리 카운트다운: "Nm 후 좌/우회전". 거리는 현재 위치→회전 지점 직선 거리.
            navigationTurnBanner = "\(Int(firstArrow.distanceFromOriginMeters.rounded()))m 후 \(firstArrow.turnDirection.displayName)"
        }
        routeArrowDiagnostics = "\(targetSpot.name) 전방 3D 대형 화살표 \(arrows.count)개 / turn boundary \(Int(routeTurnBoundaryMeters))m / \(Int(routeTurnMinimumAngleDegrees))도 이상 꺾임 / \(guidanceFix.quality.displayName)"
        let first = arrows.first
        let firstText = first.map { "활성 회전 \(String(format: "%.0f", $0.distanceFromOriginMeters))m / \($0.turnDirection.displayName) / 카메라 전방 \(String(format: "%.1f", abs($0.position.z)))m / 높이 offset \(String(format: "%.2f", $0.position.y))m" } ?? "활성 회전 화살표 없음"
        let routeLength = routePolylineLengthMeters(route.routeCoordinates)
        routeArrowComputationDiagnostics = "\(targetSpot.name) route 좌표 \(route.routeCoordinates.count)개 / 경로 길이 \(Int(routeLength))m -> turn boundary 안 전방 AR 화살표 \(arrows.count)개 생성 / guidedOrigin \(guidedOrigin.source.rawValue) \(guidedOrigin.coordinate.shortText) / \(guidanceFix.quality.displayName) / \(firstText)"
        updateNavigationGuidance(for: route, targetSpot: targetSpot, origin: guidedOrigin, guidanceFix: guidanceFix)
    }

    private func updateNavigationStabilityDiagnostics(guidanceFix: GuidanceFix, rawOrigin: LocationSnapshot) {
        let offRouteText = guidanceFix.offRouteDistanceMeters.map { "경로선 \(Int($0))m" } ?? "경로선 거리 없음"
        let snapText = guidanceFix.didSnapToRoute ? "경로 스냅 적용" : "원시 위치 사용"
        let movementText: String
        if movementTracker.isWalking(now: Date()), let bearing = movementTracker.movementBearingDegrees {
            movementText = "이동 방향 \(Int(bearing))도(걷는 중)"
        } else {
            movementText = "이동 방향 미확정(정지/대기)"
        }
        navigationStabilityDiagnostics = "위치 \(guidanceFix.quality.displayName) / 정확도 \(Int(guidanceFix.accuracyRadiusMeters))m / \(offRouteText) / \(snapText) / \(movementText)"
    }

    private func updateNavigationGuidance(
        for route: TMAPPedestrianRoute,
        targetSpot: TourismSpot,
        origin: LocationSnapshot,
        guidanceFix: GuidanceFix
    ) {
        let guidance = navigationGuidance(for: route, targetSpot: targetSpot, origin: origin, guidanceFix: guidanceFix)
        setNavigationGuidance(guidance)
    }

    /// 가는 방향(다음 안내점 방위)으로 뻗는 바닥 리본. 위치 불안정 또는 heading 신뢰 불가 시 nil(숨김).
    private func navigationRibbonSnapshot(
        for route: TMAPPedestrianRoute,
        targetSpot: TourismSpot,
        origin: LocationSnapshot,
        guidanceFix: GuidanceFix
    ) -> RouteRibbonSnapshot? {
        guard guidanceFix.allowsTurnCommitment else {
            return nil
        }

        let facing = HeadingGuidance.facingEstimate(
            compassHeadingDegrees: cameraHeadingDegrees,
            compassDeltaDegrees: cameraHeadingDeltaDegrees,
            movementBearingDegrees: movementTracker.movementBearingDegrees,
            isWalking: movementTracker.isWalking(now: Date()),
            instabilityThresholdDegrees: headingInstabilityThresholdDegrees
        )
        guard facing.isConfident else {
            return nil
        }

        guard let nextCoordinate = nextRouteGuidanceCoordinate(
            from: origin.coordinate,
            routeCoordinates: route.routeCoordinates
        ) else {
            return nil
        }

        return RouteRibbonSnapshot(
            spotID: targetSpot.id,
            bearingDegrees: origin.coordinate.bearing(to: nextCoordinate)
        )
    }

    private func setNavigationGuidance(_ guidance: NavigationGuidance) {
        navigationGuidanceTitle = guidance.title
        navigationGuidanceDetail = guidance.detail
        navigationGuidanceSystemImageName = guidance.systemImageName
        navigationGuidanceHorizontalOffsetRatio = guidance.horizontalOffsetRatio
        navigationGuidanceIsArrivalNearby = guidance.isArrivalNearby
        navigationGuidanceIsConservative = guidance.isConservative
    }

    private func setNavigationGuidance(
        title: String,
        detail: String,
        systemImageName: String = "location.fill",
        horizontalOffsetRatio: Double = 0
    ) {
        setNavigationGuidance(
        NavigationGuidance(
            title: title,
            detail: detail,
            systemImageName: systemImageName,
            horizontalOffsetRatio: horizontalOffsetRatio,
            isArrivalNearby: false
        )
        )
    }

    private func navigationGuidance(
        for route: TMAPPedestrianRoute,
        targetSpot: TourismSpot,
        origin: LocationSnapshot,
        guidanceFix: GuidanceFix
    ) -> NavigationGuidance {
        let arrivalDistance = origin.coordinate.distance(to: route.arrivalCoordinate)
        if arrivalDistance <= routeArrivalCompletionMeters {
            return NavigationGuidance(
                title: "\(targetSpot.name) 도착",
                detail: "도착 좌표 \(Int(routeArrivalCompletionMeters))m 이내입니다. 길안내를 종료하고 도착 핀을 표시합니다.",
                systemImageName: "mappin.circle.fill",
                horizontalOffsetRatio: 0,
                isArrivalNearby: true
            )
        }

        guard let nextCoordinate = nextRouteGuidanceCoordinate(
            from: origin.coordinate,
            routeCoordinates: route.routeCoordinates
        ) else {
            let bearing = origin.coordinate.bearing(to: route.arrivalCoordinate)
            return NavigationGuidance(
                title: "\(targetSpot.name) 방향으로 이동",
                detail: "경로 좌표가 부족해 도착 좌표 방향각 \(Int(bearing))도를 기준으로 안내합니다.",
                systemImageName: "location.north.fill",
                horizontalOffsetRatio: 0,
                isArrivalNearby: false
            )
        }

        let targetBearing = origin.coordinate.bearing(to: nextCoordinate)
        let distanceToNext = origin.coordinate.distance(to: nextCoordinate)
        let remainingDistance = remainingRouteDistance(
            from: origin.coordinate,
            routeCoordinates: route.routeCoordinates,
            fallbackDestination: route.arrivalCoordinate
        )
        let remainingText = remainingDistance.map { "\(Int($0))m" } ?? "\(Int(arrivalDistance))m"

        // 3.7 heading 불안정 대응: 걷는 중이면 이동 방향을, 아니면 나침반 heading을 쓰되 변화량이 크면 신뢰하지 않는다.
        let facing = HeadingGuidance.facingEstimate(
            compassHeadingDegrees: cameraHeadingDegrees,
            compassDeltaDegrees: cameraHeadingDeltaDegrees,
            movementBearingDegrees: movementTracker.movementBearingDegrees,
            isWalking: movementTracker.isWalking(now: Date()),
            instabilityThresholdDegrees: headingInstabilityThresholdDegrees
        )

        // 향한 방향을 신뢰할 수 없거나(나침반 흔들림/정지) 위치가 불안정하면 좌/우를 확정하지 않고 보수적으로 안내한다.
        guard let facingBearing = facing.bearingDegrees,
              facing.isConfident,
              guidanceFix.allowsTurnCommitment else {
            let reason: String
            if facing.bearingDegrees == nil {
                reason = "방향 신호 대기"
            } else if !facing.isConfident {
                reason = "heading 불안정"
            } else {
                reason = guidanceFix.quality.displayName
            }
            return NavigationGuidance(
                title: DirectionZone.uncertain.title,
                detail: "\(targetSpot.name)까지 약 \(remainingText) / \(reason)로 좌우 안내를 보수적으로 표시합니다.",
                systemImageName: DirectionZone.uncertain.systemImageName,
                horizontalOffsetRatio: DirectionZone.uncertain.horizontalOffsetRatio,
                isArrivalNearby: false,
                isConservative: true
            )
        }

        let signedDelta = facingBearing.signedAngularDifference(to: targetBearing)
        let zone = HeadingGuidance.zone(forSignedDeltaDegrees: signedDelta)
        let facingSourceText = facing.usedMovementDirection ? "이동 방향" : "heading"
        return NavigationGuidance(
            title: zone.title,
            detail: "\(targetSpot.name)까지 약 \(remainingText) / 다음 기준점 \(Int(distanceToNext))m / \(facingSourceText) \(Int(facingBearing))도 -> 경로 \(Int(targetBearing))도 / 차이 \(Int(signedDelta))도",
            systemImageName: zone.systemImageName,
            horizontalOffsetRatio: zone.horizontalOffsetRatio,
            isArrivalNearby: false
        )
    }

    private func nextRouteGuidanceCoordinate(
        from origin: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        guard !routeCoordinates.isEmpty else {
            return nil
        }

        let nearestIndex = routeCoordinates.indices.min {
            origin.distance(to: routeCoordinates[$0]) < origin.distance(to: routeCoordinates[$1])
        } ?? routeCoordinates.startIndex

        let lookAheadDistance: CLLocationDistance = 8
        for index in routeCoordinates.indices where index >= nearestIndex {
            let coordinate = routeCoordinates[index]
            if origin.distance(to: coordinate) >= lookAheadDistance {
                return coordinate
            }
        }

        return routeCoordinates.last
    }

    private func remainingRouteDistance(
        from origin: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        fallbackDestination: CLLocationCoordinate2D
    ) -> CLLocationDistance? {
        guard routeCoordinates.count >= 2 else {
            return origin.distance(to: fallbackDestination)
        }

        let nearestIndex = routeCoordinates.indices.min {
            origin.distance(to: routeCoordinates[$0]) < origin.distance(to: routeCoordinates[$1])
        } ?? routeCoordinates.startIndex

        var distance = origin.distance(to: routeCoordinates[nearestIndex])
        guard nearestIndex < routeCoordinates.index(before: routeCoordinates.endIndex) else {
            return distance
        }

        for index in routeCoordinates.index(after: nearestIndex)..<routeCoordinates.endIndex {
            distance += routeCoordinates[index - 1].distance(to: routeCoordinates[index])
        }
        return distance
    }

    private func routeArrowTargetSpot() -> TourismSpot? {
        guard let navigationDestinationSpotID else {
            return nil
        }

        return spots.first(where: { $0.id == navigationDestinationSpotID })
    }

    private func routeArrowSnapshots(
        for route: TMAPPedestrianRoute,
        from origin: LocationSnapshot,
        accuracyRadiusMeters: CLLocationAccuracy,
        allowsTurnCommitment: Bool
    ) -> [RouteArrowSnapshot] {
        // 위치가 불안정하면 turn boundary 안이어도 전방 화살표를 확정하지 않는다(3.6/3.7 보수적 처리).
        guard allowsTurnCommitment else {
            return []
        }

        // 회전 판정은 TMAP 안내점(turnType)을 우선 사용한다. 작은 각도 갈림길도 인정하고
        // 완만한 도로 굽이는 무시하기 위함이다(TURN_UX_RULES_V2 §1). 안내점이 없으면 기하 각도로 fallback.
        let turnManeuvers = route.maneuvers.filter { $0.kind.isTurn }
        if !turnManeuvers.isEmpty {
            return maneuverArrowSnapshots(
                route: route,
                origin: origin,
                accuracyRadiusMeters: accuracyRadiusMeters,
                turnManeuvers: turnManeuvers
            )
        }

        let routeCoordinates = route.routeCoordinates
        guard routeCoordinates.count >= 3 else {
            return []
        }

        var arrows: [RouteArrowSnapshot] = []
        let nearestIndex = routeCoordinates.indices.min {
            origin.coordinate.distance(to: routeCoordinates[$0]) < origin.coordinate.distance(to: routeCoordinates[$1])
        } ?? routeCoordinates.startIndex
        let startIndex = max(routeCoordinates.index(after: routeCoordinates.startIndex), nearestIndex)

        for index in startIndex..<(routeCoordinates.count - 1) {
            guard let turnMetrics = routeTurnMetrics(
                routeCoordinates: routeCoordinates,
                turnIndex: index,
                origin: origin
            ) else {
                continue
            }

            if turnMetrics.distanceFromOrigin > routeArrowLookAheadMeters {
                continue
            }

            guard abs(turnMetrics.signedTurnDegrees) >= routeTurnMinimumAngleDegrees else {
                continue
            }

            // 위치를 오차 원으로 보고, 오차 원이 turn boundary와 겹치면 회전 준비로 인정한다(3.6).
            guard RouteGeometry.turnBoundaryReached(
                distanceToTurnMeters: turnMetrics.distanceFromOrigin,
                accuracyRadiusMeters: accuracyRadiusMeters,
                boundaryMeters: routeTurnBoundaryMeters
            ) else {
                continue
            }

            if let heading = cameraHeadingDegrees {
                let headingTargetBearing = turnMetrics.distanceFromOrigin < 3
                    ? turnMetrics.outgoingBearing
                    : origin.coordinate.bearing(to: routeCoordinates[index])
                let facingDelta = heading.signedAngularDifference(to: headingTargetBearing)
                guard abs(facingDelta) <= routeArrowFacingToleranceDegrees else {
                    continue
                }

                let alignedDelta = heading.signedAngularDifference(to: turnMetrics.outgoingBearing)
                if abs(alignedDelta) <= routeTurnAlignedThresholdDegrees {
                    continue
                }
            }

            let position = SIMD3<Float>(
                0,
                routeArrowCameraHeightOffsetMeters,
                -routeArrowForwardDistanceMeters
            )
            arrows.append(
                RouteArrowSnapshot(
                    id: arrows.count,
                    position: position,
                    yawRadians: 0,
                    distanceFromOriginMeters: turnMetrics.distanceFromOrigin,
                    turnDirection: turnMetrics.signedTurnDegrees > 0 ? .right : .left,
                    bearingDegrees: origin.coordinate.bearing(to: routeCoordinates[index])
                )
            )

            if arrows.count >= maxRouteArrowCount {
                break
            }
        }

        return arrows
    }

    /// TMAP 회전 안내점 기준 전방 화살표 1개. TMAP이 이미 회전으로 판정한 지점이라 기하 각도(45°)는 보지 않고,
    /// boundary(오차 원 반영)·회전점 시야·정렬 여부 게이트만 적용한다.
    private func maneuverArrowSnapshots(
        route: TMAPPedestrianRoute,
        origin: LocationSnapshot,
        accuracyRadiusMeters: CLLocationAccuracy,
        turnManeuvers: [TMAPRouteManeuver]
    ) -> [RouteArrowSnapshot] {
        let routeCoordinates = route.routeCoordinates
        let sortedByDistance = turnManeuvers
            .map { (maneuver: $0, distance: origin.coordinate.distance(to: $0.coordinate)) }
            .sorted { $0.distance < $1.distance }

        for entry in sortedByDistance {
            guard let direction = entry.maneuver.kind.turnDirection else {
                continue
            }
            let distance = entry.distance
            if distance > routeArrowLookAheadMeters {
                continue
            }
            guard RouteGeometry.turnBoundaryReached(
                distanceToTurnMeters: distance,
                accuracyRadiusMeters: accuracyRadiusMeters,
                boundaryMeters: routeTurnBoundaryMeters
            ) else {
                continue
            }

            let bearingToTurn = origin.coordinate.bearing(to: entry.maneuver.coordinate)
            let outgoingBearing = maneuverOutgoingBearing(
                maneuver: entry.maneuver,
                routeCoordinates: routeCoordinates
            )

            if let heading = cameraHeadingDegrees {
                let headingTargetBearing = distance < 3 ? (outgoingBearing ?? bearingToTurn) : bearingToTurn
                let facingDelta = heading.signedAngularDifference(to: headingTargetBearing)
                guard abs(facingDelta) <= routeArrowFacingToleranceDegrees else {
                    continue
                }
                if let outgoingBearing {
                    let alignedDelta = heading.signedAngularDifference(to: outgoingBearing)
                    if abs(alignedDelta) <= routeTurnAlignedThresholdDegrees {
                        continue
                    }
                }
            }

            let position = SIMD3<Float>(
                0,
                routeArrowCameraHeightOffsetMeters,
                -routeArrowForwardDistanceMeters
            )
            return [
                RouteArrowSnapshot(
                    id: 0,
                    position: position,
                    yawRadians: 0,
                    distanceFromOriginMeters: distance,
                    turnDirection: direction,
                    bearingDegrees: bearingToTurn
                )
            ]
        }

        return []
    }

    /// 안내점 좌표에서 경로 진출 방위(샘플 거리 앞)를 구한다. 정렬/시야 판정용. 계산 불가 시 nil.
    private func maneuverOutgoingBearing(
        maneuver: TMAPRouteManeuver,
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> Double? {
        guard !routeCoordinates.isEmpty else {
            return nil
        }
        let nearestIndex = routeCoordinates.indices.min {
            maneuver.coordinate.distance(to: routeCoordinates[$0]) < maneuver.coordinate.distance(to: routeCoordinates[$1])
        }
        guard let nearestIndex,
              let outgoing = routeCoordinate(
                after: nearestIndex,
                distanceMeters: routeTurnSampleDistanceMeters,
                in: routeCoordinates
              ) else {
            return nil
        }
        return maneuver.coordinate.bearing(to: outgoing)
    }

    private struct RouteTurnMetrics {
        let incomingBearing: Double
        let outgoingBearing: Double
        let signedTurnDegrees: Double
        let incomingSampleDistance: CLLocationDistance
        let outgoingSampleDistance: CLLocationDistance
        let distanceFromOrigin: CLLocationDistance
    }

    private func routeTurnMetrics(
        routeCoordinates: [CLLocationCoordinate2D],
        turnIndex: Int,
        origin: LocationSnapshot
    ) -> RouteTurnMetrics? {
        guard routeCoordinates.indices.contains(turnIndex),
              let incomingCoordinate = routeCoordinate(
                before: turnIndex,
                distanceMeters: routeTurnSampleDistanceMeters,
                in: routeCoordinates
              ),
              let outgoingCoordinate = routeCoordinate(
                after: turnIndex,
                distanceMeters: routeTurnSampleDistanceMeters,
                in: routeCoordinates
              ) else {
            return nil
        }

        let turnCoordinate = routeCoordinates[turnIndex]
        let incomingDistance = incomingCoordinate.distance(to: turnCoordinate)
        let outgoingDistance = turnCoordinate.distance(to: outgoingCoordinate)
        guard incomingDistance > 1.0, outgoingDistance > 1.0 else {
            return nil
        }

        let incomingBearing = incomingCoordinate.bearing(to: turnCoordinate)
        let outgoingBearing = turnCoordinate.bearing(to: outgoingCoordinate)
        return RouteTurnMetrics(
            incomingBearing: incomingBearing,
            outgoingBearing: outgoingBearing,
            signedTurnDegrees: incomingBearing.signedAngularDifference(to: outgoingBearing),
            incomingSampleDistance: incomingDistance,
            outgoingSampleDistance: outgoingDistance,
            distanceFromOrigin: origin.coordinate.distance(to: turnCoordinate)
        )
    }

    private func routeCoordinate(
        before index: Int,
        distanceMeters targetDistance: CLLocationDistance,
        in coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        guard coordinates.indices.contains(index), index > coordinates.startIndex else {
            return nil
        }

        var remainingDistance = targetDistance
        var cursor = coordinates[index]
        var cursorIndex = index
        while cursorIndex > coordinates.startIndex {
            let previousIndex = coordinates.index(before: cursorIndex)
            let previous = coordinates[previousIndex]
            let segmentLength = previous.distance(to: cursor)
            if segmentLength >= remainingDistance {
                return coordinateAlongSegment(from: cursor, to: previous, distanceMeters: remainingDistance)
            }

            remainingDistance -= segmentLength
            cursor = previous
            cursorIndex = previousIndex
        }

        return coordinates.first
    }

    private func routeCoordinate(
        after index: Int,
        distanceMeters targetDistance: CLLocationDistance,
        in coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        guard coordinates.indices.contains(index), index < coordinates.index(before: coordinates.endIndex) else {
            return nil
        }

        var remainingDistance = targetDistance
        var cursor = coordinates[index]
        var cursorIndex = index
        while cursorIndex < coordinates.index(before: coordinates.endIndex) {
            let nextIndex = coordinates.index(after: cursorIndex)
            let next = coordinates[nextIndex]
            let segmentLength = cursor.distance(to: next)
            if segmentLength >= remainingDistance {
                return coordinateAlongSegment(from: cursor, to: next, distanceMeters: remainingDistance)
            }

            remainingDistance -= segmentLength
            cursor = next
            cursorIndex = nextIndex
        }

        return coordinates.last
    }

    private func coordinateAlongSegment(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        distanceMeters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let segmentLength = startLocation.distance(from: endLocation)
        guard segmentLength > 0 else {
            return start
        }

        let ratio = min(max(distanceMeters / segmentLength, 0), 1)
        return CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * ratio,
            longitude: start.longitude + (end.longitude - start.longitude) * ratio
        )
    }

    private func routeArrowRejectionDiagnostics(
        route: TMAPPedestrianRoute,
        origin: LocationSnapshot,
        targetSpot: TourismSpot
    ) -> String {
        let routeCoordinates = route.routeCoordinates
        guard routeCoordinates.count >= 3 else {
            return "\(targetSpot.name) route 좌표 \(routeCoordinates.count)개 / 회전 계산 불가: 최소 3개 좌표 필요 / origin \(origin.coordinate.shortText)"
        }

        let nearestDistance = routeCoordinates
            .map { origin.coordinate.distance(to: $0) }
            .min()
        let nearestText = nearestDistance.map { "\(Int($0))m" } ?? "없음"
        var candidates: [String] = []

        let nearestIndex = routeCoordinates.indices.min {
            origin.coordinate.distance(to: routeCoordinates[$0]) < origin.coordinate.distance(to: routeCoordinates[$1])
        } ?? routeCoordinates.startIndex
        let startIndex = max(routeCoordinates.index(after: routeCoordinates.startIndex), nearestIndex)

        for index in startIndex..<(routeCoordinates.count - 1) {
            let turnDistance = origin.coordinate.distance(to: routeCoordinates[index])
            guard let turnMetrics = routeTurnMetrics(
                routeCoordinates: routeCoordinates,
                turnIndex: index,
                origin: origin
            ) else {
                candidates.append("#\(index) 제외: 전후 \(Int(routeTurnSampleDistanceMeters))m 샘플 부족")
                continue
            }

            let alignedDelta = cameraHeadingDegrees.map { $0.signedAngularDifference(to: turnMetrics.outgoingBearing) }
            let headingTargetBearing = turnMetrics.distanceFromOrigin < 3
                ? turnMetrics.outgoingBearing
                : origin.coordinate.bearing(to: routeCoordinates[index])
            let facingDelta = cameraHeadingDegrees.map { $0.signedAngularDifference(to: headingTargetBearing) }
            let reason: String
            if abs(turnMetrics.signedTurnDegrees) < routeTurnMinimumAngleDegrees {
                reason = "회전각 부족"
            } else if turnMetrics.distanceFromOrigin > routeTurnBoundaryMeters {
                reason = "boundary 밖"
            } else if let facingDelta, abs(facingDelta) > routeArrowFacingToleranceDegrees {
                reason = "카메라가 회전 지점 안 봄"
            } else if let alignedDelta, abs(alignedDelta) <= routeTurnAlignedThresholdDegrees {
                reason = "이미 방향 정렬"
            } else if turnDistance > routeArrowLookAheadMeters {
                reason = "lookAhead 밖"
            } else {
                reason = "조건 통과 예상"
            }

            let headingText: String
            if let facingDelta, let alignedDelta {
                headingText = "heading->turn \(Int(facingDelta))도 / heading->out \(Int(alignedDelta))도"
            } else {
                headingText = "heading 없음"
            }
            candidates.append(
                "#\(index) \(reason) / 거리 \(Int(turnMetrics.distanceFromOrigin))m / 회전 \(Int(turnMetrics.signedTurnDegrees))도 / in \(Int(turnMetrics.incomingBearing))도 out \(Int(turnMetrics.outgoingBearing))도 / 샘플 \(Int(turnMetrics.incomingSampleDistance))m-\(Int(turnMetrics.outgoingSampleDistance))m / \(headingText)"
            )

            if candidates.count >= 4 {
                break
            }
        }

        let candidateText = candidates.isEmpty ? "회전 후보 없음" : candidates.joined(separator: " | ")
        return "\(targetSpot.name) route 좌표 \(routeCoordinates.count)개 / 최근접 \(nearestText) / 기준: boundary \(Int(routeTurnBoundaryMeters))m, 전후 샘플 \(Int(routeTurnSampleDistanceMeters))m, 회전 \(Int(routeTurnMinimumAngleDegrees))도 이상, 회전지점 시야 \(Int(routeArrowFacingToleranceDegrees))도 이내, 정렬 \(Int(routeTurnAlignedThresholdDegrees))도 초과 / \(candidateText)"
    }

    private func routePolylineLengthMeters(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count >= 2 else {
            return 0
        }

        var length: CLLocationDistance = 0
        for index in 1..<coordinates.count {
            length += coordinates[index - 1].distance(to: coordinates[index])
        }
        return length
    }

    private func prefetchNearbyBuildingPolygonsFor3DAnchors(from origin: LocationSnapshot) {
        let candidates = spots
            .filter { spot in
                guard buildingPolygonsBySpotID[spot.id] == nil,
                      polygonPrefetchTasksBySpotID[spot.id] == nil,
                      !polygonLookupNotFoundSpotIDs.contains(spot.id) else {
                    return false
                }

                return origin.coordinate.distance(to: spot.center) <= geospatial3DCreateRadiusMeters
            }
            .prefix(maxActiveGeospatial3DAnchorCount)

        for spot in candidates {
            let task = Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let polygon = try await self.vworldClient.fetchBuildingPolygon(for: spot)
                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        self.polygonPrefetchTasksBySpotID[spot.id] = nil
                        guard let polygon else {
                            self.polygonLookupNotFoundSpotIDs.insert(spot.id)
                            self.refreshBuildingLabelHeightDiagnostics()
                            return
                        }

                        let resolvedHeight = self.buildingHeightResolver.resolve(polygon: polygon)
                        self.buildingPolygonsBySpotID[spot.id] = polygon
                        self.resolvedBuildingHeightsBySpotID[spot.id] = resolvedHeight
                        self.polygonLookupNotFoundSpotIDs.remove(spot.id)
                        self.refreshEdgeMarkerOverlays()
                        self.refreshOnScreenCandidateMarkerOverlays()
                        self.refreshBuildingLabelHeightDiagnostics()
                    }
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        self.polygonPrefetchTasksBySpotID[spot.id] = nil
                    }
                }
            }
            polygonPrefetchTasksBySpotID[spot.id] = task
        }
    }

    private func refreshEdgeMarkerOverlays() {
        // 길찾기 중에는 하단 2D 지도가 경로 진실을 담당하므로 카메라 상단 2D 방향 라벨/edge marker를 띄우지 않는다.
        // 방향은 바닥 리본/회전 chevron이, 불안정/도착은 텍스트 배너가 담당한다.
        if isNavigationModeEnabled {
            edgeMarkerOverlays = []
            return
        }
        updateEdgeMarkerOverlays(focusing: recognitionResult.labelSpot ?? selectedSpot)
    }

    private func refreshOnScreenCandidateMarkerOverlays() {
        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees,
              let pose = cameraPoseSnapshot else {
            onScreenCandidateMarkerOverlays = []
            return
        }

        let visibleCandidates = spots.compactMap { spot -> (spot: TourismSpot, anchor: CGPoint, centerDistance: Double)? in
            let polygon = buildingPolygonsBySpotID[spot.id]
            let fovProjectedPoints = projectedPoints(
                for: spot,
                polygon: polygon,
                from: latestLocationSnapshot,
                heading: heading,
                pitch: pose.pitchDegrees
            )
            let matrixProjectedPoints = matrixProjectedPoints(for: spot, polygon: polygon, from: latestLocationSnapshot)
            let isOnScreen = edgeMarkerScreenVisibility(
                for: spot,
                polygon: polygon,
                fovProjectedPoints: fovProjectedPoints,
                matrixProjectedPoints: matrixProjectedPoints,
                from: latestLocationSnapshot,
                headingDegrees: heading
            )
            guard isOnScreen else {
                return nil
            }

            let anchor = matrixProjectedPoints.contains(where: \.isInsideView)
                ? matrixFallbackAnchor(for: matrixProjectedPoints)
                : overlayFallbackAnchor(for: fovProjectedPoints)
            let centerDistance = hypot(Double(anchor.x) - 0.5, Double(anchor.y) - 0.5)
            return (spot, anchor, centerDistance)
        }
        .sorted { $0.centerDistance < $1.centerDistance }

        onScreenCandidateMarkerOverlays = visibleCandidates.enumerated().map { index, item in
            let distance = latestLocationSnapshot.coordinate.distance(to: item.spot.center)
            return OnScreenCandidateMarkerOverlay(
                id: item.spot.id,
                shortTitle: item.spot.edgeMarkerShortTitle,
                distanceText: markerDistanceText(for: distance),
                normalizedX: Double(item.anchor.x).clamped(to: 0.08...0.92),
                normalizedY: Double(item.anchor.y).clamped(to: 0.12...0.78),
                scale: markerScale(for: distance),
                role: index == 0 ? .primary : .secondary
            )
        }
    }

    private func refreshRadarMarkerOverlays() {
        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees else {
            radarMarkerOverlays = []
            radarDiagnostics = "반원형 레이더 숨김 / 위치 또는 heading 없음"
            return
        }

        let selectedSpotID = selectedSpot?.id ?? recognitionResult.labelSpot?.id
        let markers = spots.compactMap { spot -> (marker: RadarMarkerOverlay, distance: CLLocationDistance)? in
            let targetCoordinate = tmapArrivalRoutesBySpotID[spot.id]?.arrivalCoordinate ?? spot.center
            let distance = latestLocationSnapshot.coordinate.distance(to: targetCoordinate)
            guard distance <= radarRadiusMeters else {
                return nil
            }

            let bearing = latestLocationSnapshot.coordinate.bearing(to: targetCoordinate)
            let signedDelta = heading.signedAngularDifference(to: bearing)
            let clampedDelta = signedDelta.clamped(to: -90...90)
            let isBehind = abs(signedDelta) > 90
            let distanceRatio = min(distance / radarRadiusMeters, 1)
            let angleRadians = (180 - clampedDelta).degreesToRadians
            let radiusRatio = 0.18 + distanceRatio * 0.78
            let normalizedX = 0.5 + cos(angleRadians) * radiusRatio * 0.48
            let normalizedY = 0.96 - sin(angleRadians) * radiusRatio * 0.88

            return (
                RadarMarkerOverlay(
                    id: spot.id,
                    shortTitle: spot.edgeMarkerShortTitle,
                    distanceText: radarDistanceText(for: distance),
                    normalizedX: normalizedX.clamped(to: 0.06...0.94),
                    normalizedY: normalizedY.clamped(to: 0.08...0.96),
                    isSelected: spot.id == selectedSpotID,
                    isArrivalNearby: spot.id == selectedSpotID && distance <= routeArrivalCompletionMeters,
                    isBehind: isBehind
                ),
                distance
            )
        }
        .sorted { lhs, rhs in
            if lhs.marker.isSelected != rhs.marker.isSelected {
                return lhs.marker.isSelected
            }
            return lhs.distance < rhs.distance
        }
        .prefix(maxRadarMarkerCount)
        .map(\.marker)

        radarMarkerOverlays = Array(markers)
        radarDiagnostics = radarMarkerOverlays.isEmpty
            ? "반원형 레이더 표시 후보 없음 / \(Int(radarRadiusMeters))m 이내"
            : "반원형 레이더 \(radarMarkerOverlays.count)개 / 반경 \(Int(radarRadiusMeters))m"
    }

    private func updateEdgeMarkerOverlays(focusing focusedSpot: TourismSpot?) {
        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees,
              let pose = cameraPoseSnapshot else {
            edgeMarkerOverlays = []
            return
        }

        let focusedSpotID = focusedSpot?.id
        let visibleLabelSpotID = arLabelOverlay?.spotID
        let overlays = spots
            .compactMap { spot -> (overlay: EdgeMarkerOverlay, priority: Double)? in
                let polygon = buildingPolygonsBySpotID[spot.id]
                let targetCoordinate = polygon?.centroid ?? spot.center
                let fovProjectedPoints = projectedPoints(for: spot, polygon: polygon, from: latestLocationSnapshot, heading: heading, pitch: pose.pitchDegrees)
                let matrixProjectedPoints = matrixProjectedPoints(for: spot, polygon: polygon, from: latestLocationSnapshot)
                let isOnScreen = edgeMarkerScreenVisibility(
                    for: spot,
                    polygon: polygon,
                    fovProjectedPoints: fovProjectedPoints,
                    matrixProjectedPoints: matrixProjectedPoints,
                    from: latestLocationSnapshot,
                    headingDegrees: heading
                )

                if spot.id == visibleLabelSpotID {
                    return nil
                }

                if spot.id != focusedSpotID, isOnScreen {
                    return nil
                }

                if spot.id == focusedSpotID, isOnScreen {
                    return nil
                }

                let projectedPoint = projectCoordinate(
                    targetCoordinate,
                    from: latestLocationSnapshot.coordinate,
                    headingDegrees: heading,
                    pitchDegrees: pose.pitchDegrees
                )
                let edgePosition = edgeMarkerPosition(forScreenX: projectedPoint.screenX, screenY: projectedPoint.screenY)
                let distance = latestLocationSnapshot.coordinate.distance(to: spot.center)
                let overlay = EdgeMarkerOverlay(
                    id: spot.id,
                    shortTitle: spot.edgeMarkerShortTitle,
                    distanceText: markerDistanceText(for: distance),
                    normalizedX: edgePosition.x,
                    normalizedY: edgePosition.y,
                    scale: markerScale(for: distance),
                    systemImageName: edgePosition.systemImageName
                )
                return (overlay, abs(projectedPoint.horizontalDeltaDegrees))
            }
            .sorted { $0.priority < $1.priority }
            .prefix(maxEdgeMarkerCount)
            .map(\.overlay)
        edgeMarkerOverlays = overlays.enumerated().map { index, overlay in
            EdgeMarkerOverlay(
                id: overlay.id,
                shortTitle: overlay.shortTitle,
                distanceText: overlay.distanceText,
                normalizedX: overlay.normalizedX,
                normalizedY: (overlay.normalizedY + Double(index) * 0.065).clamped(to: 0.12...0.82),
                scale: overlay.scale,
                systemImageName: overlay.systemImageName
            )
        }
    }

    private func markerScale(for distance: CLLocationDistance) -> Double {
        distance > distantMarkerThresholdMeters ? distantMarkerScale : 1
    }

    private func markerDistanceText(for distance: CLLocationDistance) -> String? {
        guard distance > distantMarkerThresholdMeters else {
            return nil
        }

        return distance >= 10_000
            ? "\(Int((distance / 1_000).rounded()))km"
            : String(format: "%.1fkm", distance / 1_000)
    }

    private func radarDistanceText(for distance: CLLocationDistance) -> String {
        if distance < 100 {
            return "\(Int(distance))m"
        }
        if distance < 1_000 {
            return "\(Int((distance / 10).rounded() * 10))m"
        }
        return String(format: "%.1fkm", distance / 1_000)
    }

    private func projectedPoints(
        for spot: TourismSpot,
        polygon: BuildingPolygon?,
        from latestLocationSnapshot: LocationSnapshot,
        heading: Double,
        pitch: Double
    ) -> [ProjectedPolygonPoint] {
        let coordinates = polygon?.rings.flatMap { $0 } ?? [spot.center]
        return coordinates.map {
            projectCoordinate(
                $0,
                from: latestLocationSnapshot.coordinate,
                headingDegrees: heading,
                pitchDegrees: pitch
            )
        }
    }

    private func edgeMarkerScreenVisibility(
        for spot: TourismSpot,
        polygon: BuildingPolygon?,
        fovProjectedPoints: [ProjectedPolygonPoint],
        matrixProjectedPoints: [CameraMatrixProjectedPoint],
        from latestLocationSnapshot: LocationSnapshot,
        headingDegrees: Double
    ) -> Bool {
        if matrixProjectedPoints.contains(where: \.isInsideView) {
            return true
        }

        let fallbackHeadingDelta = fovFallbackHeadingDelta(
            for: spot,
            polygon: polygon,
            from: latestLocationSnapshot,
            headingDegrees: headingDegrees
        )
        return polygonIntersectsView(fovProjectedPoints)
            && fallbackHeadingDelta <= fovFallbackMaxHeadingDeltaDegrees
    }

    private func edgeMarkerPosition(forScreenX screenX: Double, screenY: Double) -> (x: Double, y: Double, systemImageName: String) {
        let minX = 0.07
        let maxX = 0.93
        let minY = 0.12
        let maxY = 0.82
        let centerX = 0.5
        let centerY = 0.5
        let dx = screenX - centerX
        let dy = screenY - centerY

        guard abs(dx) > 0.001 || abs(dy) > 0.001 else {
            return (maxX, centerY, "chevron.right")
        }

        var candidates: [(t: Double, x: Double, y: Double, systemImageName: String)] = []
        if dx > 0 {
            let t = (maxX - centerX) / dx
            candidates.append((t, maxX, centerY + dy * t, "chevron.right"))
        } else if dx < 0 {
            let t = (minX - centerX) / dx
            candidates.append((t, minX, centerY + dy * t, "chevron.left"))
        }

        if dy > 0 {
            let t = (maxY - centerY) / dy
            candidates.append((t, centerX + dx * t, maxY, "chevron.down"))
        } else if dy < 0 {
            let t = (minY - centerY) / dy
            candidates.append((t, centerX + dx * t, minY, "chevron.up"))
        }

        let validCandidates = candidates
            .filter { $0.t > 0 }
            .map {
                (
                    t: $0.t,
                    x: $0.x.clamped(to: minX...maxX),
                    y: $0.y.clamped(to: minY...maxY),
                    systemImageName: $0.systemImageName
                )
            }

        guard let closestEdge = validCandidates.min(by: { $0.t < $1.t }) else {
            return (maxX, centerY, "chevron.right")
        }

        return (closestEdge.x, closestEdge.y, closestEdge.systemImageName)
    }

    private func appendPolygonLookupLog(_ message: String) {
        appendPolygonLookupLogs([message])
    }

    private func appendPolygonLookupLogs(_ messages: [String]) {
        polygonLookupLogs.append(contentsOf: messages)
        if polygonLookupLogs.count > 90 {
            polygonLookupLogs = Array(polygonLookupLogs.suffix(90))
        }
    }

    private func refreshSpatialTrackingConfidence() {
        let headingIsStable = (cameraHeadingDeltaDegrees ?? 0) <= headingInstabilityThresholdDegrees
        effectiveSpatialConfidence = headingIsStable ? locationConfidence : locationConfidence.downgraded

        let headingText = headingIsStable
            ? "heading 안정"
            : "heading 불안정: 변화량 \(Int(cameraHeadingDeltaDegrees ?? 0))도"
        spatialTrackingDiagnostics = "공간 신뢰도 \(effectiveSpatialConfidence.displayName) / 위치 \(locationConfidence.displayName) / \(headingText) / \(stableOriginDiagnostics)"
    }

    private func updateStableGeospatial3DOrigin(with snapshot: LocationSnapshot) -> Bool {
        guard snapshot.source == .arCoreGeospatial else {
            markStableOriginDegraded("3D stable origin 대기 / CoreLocation은 목록 필터링에만 사용하고 3D WGS84 기준 위치로는 사용하지 않습니다.")
            return false
        }

        guard snapshot.horizontalAccuracy > 0,
              snapshot.horizontalAccuracy <= stableOriginMaxAccuracyMeters else {
            markStableOriginDegraded("3D stable origin 대기 / \(snapshot.source.rawValue) 정확도 \(Int(snapshot.horizontalAccuracy))m가 기준 \(Int(stableOriginMaxAccuracyMeters))m 초과")
            return false
        }

        if let stableGeospatial3DOrigin {
            let distanceFromStable = stableGeospatial3DOrigin.coordinate.distance(to: snapshot.coordinate)
            if distanceFromStable > stableOriginMaxJumpMeters {
                stableOriginIsUsableFor3DAnchors = false
                return updatePendingStableOrigin(with: snapshot, reason: "기존 stable origin에서 \(Int(distanceFromStable))m 점프")
            }

            self.stableGeospatial3DOrigin = snapshot
            pendingStableGeospatial3DOrigin = nil
            pendingStableOriginFirstSeenAt = nil
            stableOriginLastAcceptedAt = Date()
            stableOriginIsUsableFor3DAnchors = true
            stableOriginDiagnostics = "3D stable origin 유지(위치 기준) / \(snapshot.source.rawValue) 정확도 \(Int(snapshot.horizontalAccuracy))m / 기존 기준과 차이 \(Int(distanceFromStable))m"
            return false
        }

        return updatePendingStableOrigin(with: snapshot, reason: "초기 stable origin 후보")
    }

    private var stableOriginReadyFor3DAnchors: Bool {
        guard stableGeospatial3DOrigin != nil,
              stableOriginIsUsableFor3DAnchors,
              let stableOriginLastAcceptedAt else {
            return false
        }

        return Date().timeIntervalSince(stableOriginLastAcceptedAt) <= stableOriginDegradedTimeout
    }

    private func markStableOriginDegraded(_ message: String) {
        let now = Date()
        if let stableOriginLastAcceptedAt,
           now.timeIntervalSince(stableOriginLastAcceptedAt) <= stableOriginDegradedTimeout {
            let age = now.timeIntervalSince(stableOriginLastAcceptedAt)
            stableOriginDiagnostics = "\(message) / 마지막 안정 위치 \(String(format: "%.1f", age))초 유지"
            return
        }

        stableOriginIsUsableFor3DAnchors = false
        pendingStableGeospatial3DOrigin = nil
        pendingStableOriginFirstSeenAt = nil
        lastGeospatial3DAnchorRefreshAt = nil
        if !activeGeospatial3DSpotIDs.isEmpty || !lastRequestedTerrainAnchorSpotIDs.isEmpty {
            geospatialSessionManager.clearAllGeospatialDebugAnchors(reason: "3D stable origin 불안정으로 WGS84 Anchor를 일시 제거했습니다.")
            activeGeospatial3DSpotIDs = []
            fixedNearestFacadeCandidatesBySpotID = [:]
            lastRequestedTerrainAnchorSpotIDs = []
            geospatialWGS84CandidateDiagnostics = "WGS84 Anchor 후보 일시정지 / \(message)"
        }
        stableOriginDiagnostics = "\(message) / 3D anchor 갱신 일시정지"
    }

    private func updatePendingStableOrigin(with snapshot: LocationSnapshot, reason: String) -> Bool {
        let now = Date()
        if let pendingStableGeospatial3DOrigin,
           let pendingStableOriginFirstSeenAt {
            let distanceFromPending = pendingStableGeospatial3DOrigin.coordinate.distance(to: snapshot.coordinate)
            if distanceFromPending <= stableOriginMaxJumpMeters {
                let pendingDuration = now.timeIntervalSince(pendingStableOriginFirstSeenAt)
                if pendingDuration >= stableOriginConfirmationInterval {
                    stableGeospatial3DOrigin = snapshot
                    self.pendingStableGeospatial3DOrigin = nil
                    self.pendingStableOriginFirstSeenAt = nil
                    stableOriginLastAcceptedAt = now
                    stableOriginIsUsableFor3DAnchors = true
                    stableOriginDiagnostics = "3D stable origin 확정(위치 기준) / \(snapshot.source.rawValue) 정확도 \(Int(snapshot.horizontalAccuracy))m / 후보 유지 \(String(format: "%.1f", pendingDuration))초"
                    return true
                }

                stableOriginDiagnostics = "3D stable origin 후보 확인 중 / \(reason) / 후보 차이 \(Int(distanceFromPending))m / \(String(format: "%.1f", pendingDuration))초"
                return false
            }
        }

        pendingStableGeospatial3DOrigin = snapshot
        pendingStableOriginFirstSeenAt = now
        stableOriginDiagnostics = "3D stable origin 후보 시작 / \(reason) / \(snapshot.source.rawValue) 정확도 \(Int(snapshot.horizontalAccuracy))m"
        return false
    }

    private func refreshLocalCoordinateDiagnostics() {
        guard let latestLocationSnapshot else {
            localCoordinateDiagnostics = "현재 위치가 없어 local ENU 좌표를 계산할 수 없습니다."
            return
        }

        guard let spot = localCoordinateTargetSpot(from: latestLocationSnapshot) else {
            localCoordinateDiagnostics = "현재 위치 기준으로 비교할 POI 후보가 없습니다."
            return
        }

        let poiENU = LocalENUProjector.project(spot.center, from: latestLocationSnapshot)
        var message = "\(spot.name) local ENU / origin \(latestLocationSnapshot.source.rawValue) \(latestLocationSnapshot.latitude.formatted(.number.precision(.fractionLength(6)))), \(latestLocationSnapshot.longitude.formatted(.number.precision(.fractionLength(6)))) / POI east \(Int(poiENU.eastMeters))m north \(Int(poiENU.northMeters))m / 거리 \(Int(poiENU.groundDistanceMeters))m / 방향각 \(Int(poiENU.bearingDegrees))도"

        if let polygon = buildingPolygonsBySpotID[spot.id],
           let centroid = polygon.centroid {
            let centroidENU = LocalENUProjector.project(centroid, from: latestLocationSnapshot)
            message += " / Polygon centroid east \(Int(centroidENU.eastMeters))m north \(Int(centroidENU.northMeters))m"

            let vertexENUs = polygon.rings.flatMap { $0 }.map {
                LocalENUProjector.project($0, from: latestLocationSnapshot)
            }
            if let eastRange = vertexENUs.map(\.eastMeters).metersRangeDescription,
               let northRange = vertexENUs.map(\.northMeters).metersRangeDescription {
                message += " / 외곽 east \(eastRange) north \(northRange)"
            }
        } else {
            message += " / Polygon ENU는 브이월드 Polygon 확보 후 표시됩니다."
        }

        localCoordinateDiagnostics = message
    }

    private func localCoordinateTargetSpot(from latestLocationSnapshot: LocationSnapshot) -> TourismSpot? {
        if let cameraDirectionSpotID,
           let spot = spots.first(where: { $0.id == cameraDirectionSpotID }) {
            return spot
        }

        if let selectedSpot,
           spots.contains(where: { $0.id == selectedSpot.id }) {
            return selectedSpot
        }

        return spots.min {
            latestLocationSnapshot.coordinate.distance(to: $0.center) < latestLocationSnapshot.coordinate.distance(to: $1.center)
        }
    }

    private func refreshBuildingFacadeAnchorDiagnostics() {
        guard let latestLocationSnapshot else {
            buildingFacadeAnchorDiagnostics = "현재 위치가 없어 3D 외벽 후보점을 계산할 수 없습니다."
            return
        }

        guard let spot = localCoordinateTargetSpot(from: latestLocationSnapshot) else {
            buildingFacadeAnchorDiagnostics = "3D 외벽 후보점을 계산할 POI 후보가 없습니다."
            return
        }

        guard let polygon = buildingPolygonsBySpotID[spot.id] else {
            buildingFacadeAnchorDiagnostics = "\(spot.name) Polygon이 아직 없어 3D 외벽 후보점을 계산할 수 없습니다."
            return
        }

        guard let facadeCandidate = cameraFacingFacadeCandidate(
            spot: spot,
            polygon: polygon,
            from: latestLocationSnapshot,
            headingDegrees: cameraHeadingDegrees
        ) else {
            buildingFacadeAnchorDiagnostics = "\(spot.name) Polygon 외곽 선분이 없어 3D 외벽 후보점을 계산할 수 없습니다."
            return
        }

        let anchorBearing = facadeCandidate.anchorENU.bearingDegrees
        let startText = "시작 east \(Int(facadeCandidate.startENU.eastMeters))m north \(Int(facadeCandidate.startENU.northMeters))m"
        let endText = "끝 east \(Int(facadeCandidate.endENU.eastMeters))m north \(Int(facadeCandidate.endENU.northMeters))m"
        let anchorText = "\(facadeCandidate.selectionReason) east \(Int(facadeCandidate.anchorENU.eastMeters))m north \(Int(facadeCandidate.anchorENU.northMeters))m"
        let closestText = "내 위치와 외벽 최단거리 \(Int(facadeCandidate.distanceFromUserMeters))m"
        let lengthText = "외벽 길이 \(Int(facadeCandidate.lengthMeters))m"
        let bearingText = "앵커 방향각 \(Int(anchorBearing))도"
        let stabilityText = facadeCandidate.stabilizationNote.map { "안정화 \($0)" } ?? "안정화 정보 없음"

        buildingFacadeAnchorDiagnostics = "\(spot.name) 3D 외벽 후보 / \(startText) / \(endText) / \(anchorText) / \(closestText) / \(lengthText) / \(bearingText) / \(stabilityText)"
    }

    private func refreshBuildingLabelHeightDiagnostics() {
        guard let latestLocationSnapshot else {
            buildingLabelHeightDiagnostics = "현재 위치가 없어 3D 라벨 높이 기준값을 계산할 수 없습니다."
            return
        }

        guard let stableOrigin = stableGeospatial3DOrigin,
              stableOriginReadyFor3DAnchors else {
            buildingLabelHeightDiagnostics = "3D stable origin이 현재 사용 가능하지 않아 라벨 높이 기준값을 확정하지 않았습니다. / \(stableOriginDiagnostics)"
            geospatialWGS84CandidateDiagnostics = "WGS84 Anchor 후보 대기 / \(stableOriginDiagnostics)"
            return
        }

        guard let spot = localCoordinateTargetSpot(from: stableOrigin) else {
            buildingLabelHeightDiagnostics = "3D 라벨 높이를 계산할 POI 후보가 없습니다."
            return
        }

        guard let polygon = buildingPolygonsBySpotID[spot.id] else {
            buildingLabelHeightDiagnostics = "\(spot.name) Polygon이 아직 없어 3D 라벨 높이 기준값을 계산할 수 없습니다."
            return
        }

        let resolvedHeight = resolvedBuildingHeightsBySpotID[spot.id] ?? buildingHeightResolver.resolve(polygon: polygon)
        resolvedBuildingHeightsBySpotID[spot.id] = resolvedHeight

        let facadeDistanceMeters = nearestFacadeCandidate(
            spot: spot,
            polygon: polygon,
            from: stableOrigin
        )?.distanceFromUserMeters
        let distanceMeters = facadeDistanceMeters
            ?? stableOrigin.coordinate.distance(to: spot.center)
        let distanceSource = facadeDistanceMeters == nil ? "POI 중심 거리" : "기본 외벽점 거리"
        let labelHeight = labelHeightDecision(
            for: resolvedHeight,
            distanceMeters: distanceMeters
        )
        let sourcePropertiesText = sourceHeightPropertiesText(for: polygon)
        buildingLabelHeightDiagnostics = "\(spot.name) 3D 라벨 높이 기준 / \(distanceSource) \(Int(distanceMeters))m / \(labelHeight.rangeLabel) / 건물 높이 \(resolvedHeight.displayText) / 라벨 후보 높이 \(String(format: "%.1f", labelHeight.valueMeters))m / \(labelHeight.reason) / \(resolvedHeight.explanation)\(sourcePropertiesText)"

        refreshGeospatial3DAnchorRequestsIfPossible()
    }

    private func refreshGeospatial3DAnchorRequestsIfPossible(force: Bool = false) {
        guard let stableGeospatial3DOrigin,
              stableOriginReadyFor3DAnchors else {
            geospatialWGS84CandidateDiagnostics = "WGS84 Anchor 후보 대기 / \(stableOriginDiagnostics)"
            return
        }

        let now = Date()
        if !force,
           let lastGeospatial3DAnchorRefreshAt,
           now.timeIntervalSince(lastGeospatial3DAnchorRefreshAt) < geospatial3DAnchorRefreshInterval {
            return
        }

        lastGeospatial3DAnchorRefreshAt = now
        refreshGeospatial3DAnchorRequests(origin: stableGeospatial3DOrigin)
    }

    private func shouldKeepGeospatial3DAnchor(
        spotID: TourismSpot.ID,
        distanceMeters: CLLocationDistance
    ) -> Bool {
        if activeGeospatial3DSpotIDs.contains(spotID) {
            return distanceMeters <= geospatial3DDeleteRadiusMeters
        }

        return distanceMeters <= geospatial3DCreateRadiusMeters
    }

    private func refreshGeospatial3DAnchorRequests(origin: LocationSnapshot) {
        let previousActiveSpotIDs = activeGeospatial3DSpotIDs
        guard isNavigationModeEnabled else {
            refreshBrowsingGeospatial3DAnchorRequests(
                origin: origin,
                previousActiveSpotIDs: previousActiveSpotIDs
            )
            return
        }

        guard let destination = navigationDestinationSpot else {
            if !previousActiveSpotIDs.isEmpty || !lastRequestedTerrainAnchorSpotIDs.isEmpty {
                geospatialSessionManager.clearAllGeospatialDebugAnchors(reason: "길찾기 목적지 없음 / 3D 목적지 마커 숨김")
            }
            activeGeospatial3DSpotIDs = []
            fixedNearestFacadeCandidatesBySpotID = [:]
            markerPlacementDiagnosticsBySpotID = [:]
            lastRequestedTerrainAnchorSpotIDs = []
            geospatialWGS84CandidateDiagnostics = "3D 목적지 마커 대기 / 길찾기 목적지를 선택하세요."
            return
        }

        guard let route = tmapArrivalRoutesBySpotID[destination.id] else {
            for spotID in previousActiveSpotIDs {
                geospatialSessionManager.clearGeospatialDebugAnchor(
                    for: spotID,
                    reason: "TMAP 도착 좌표 없음 / 기존 3D 목적지 마커 제거"
                )
            }
            activeGeospatial3DSpotIDs = []
            fixedNearestFacadeCandidatesBySpotID = [:]
            markerPlacementDiagnosticsBySpotID = [:]
            lastRequestedTerrainAnchorSpotIDs = []
            geospatialWGS84CandidateDiagnostics = "\(destination.name) 3D 목적지 마커 대기 / TMAP 보행자 경로 마지막 도착 좌표가 아직 없습니다."
            return
        }

        let facadeCandidate = tmapArrivalCandidate(
            spot: destination,
            route: route,
            from: origin
        )
        let distanceMeters = facadeCandidate.distanceFromUserMeters
        let labelHeight = arrivalLabelHeightDecision(distanceMeters: distanceMeters)
        let requestedSpotIDs: Set<TourismSpot.ID> = [destination.id]

        for spotID in previousActiveSpotIDs where !requestedSpotIDs.contains(spotID) {
            geospatialSessionManager.clearGeospatialDebugAnchor(
                for: spotID,
                reason: "선택 목적지 변경 / 길찾기 목적지 1개만 3D 마커로 유지"
            )
            fixedNearestFacadeCandidatesBySpotID[spotID] = nil
        }

        let summary = requestGeospatialTerrainAnchorIfPossible(
            spot: destination,
            facadeCandidate: facadeCandidate,
            labelHeightMeters: labelHeight.valueMeters,
            origin: origin
        )

        activeGeospatial3DSpotIDs = requestedSpotIDs
        fixedNearestFacadeCandidatesBySpotID = [:]
        markerPlacementDiagnosticsBySpotID = markerPlacementDiagnosticsBySpotID.filter {
            requestedSpotIDs.contains($0.key)
        }
        lastRequestedTerrainAnchorSpotIDs = requestedSpotIDs
        let markerDiagnostics = requestedSpotIDs
            .compactMap { markerPlacementDiagnosticsBySpotID[$0] }
            .sorted()
        let markerText = markerDiagnostics.isEmpty
            ? ""
            : " / 마커 좌표 판단: " + markerDiagnostics.joined(separator: " | ")
        geospatialWGS84CandidateDiagnostics = "3D 목적지 마커 1개 / TMAP 마지막 도착 좌표 고정 / \(summary) / 목적지 POI \(destination.center.shortText) / TMAP 도착 \(route.arrivalCoordinate.shortText)\(markerText)"
        refreshRouteArrowPath()
    }

    private func refreshBrowsingGeospatial3DAnchorRequests(
        origin: LocationSnapshot,
        previousActiveSpotIDs: Set<TourismSpot.ID>
    ) {
        let preparedRequests = spots.compactMap { spot -> (spot: TourismSpot, labelHeight: BuildingLabelHeightDecision, facadeCandidate: BuildingFacadeCandidate, distanceMeters: CLLocationDistance, route: TMAPPedestrianRoute)? in
            guard let route = tmapArrivalRoutesBySpotID[spot.id] else {
                return nil
            }

            let facadeCandidate = tmapArrivalCandidate(
                spot: spot,
                route: route,
                from: origin
            )
            let distanceMeters = facadeCandidate.distanceFromUserMeters

            guard shouldKeepGeospatial3DAnchor(
                spotID: spot.id,
                distanceMeters: distanceMeters
            ) else {
                return nil
            }

            return (
                spot: spot,
                labelHeight: arrivalLabelHeightDecision(distanceMeters: distanceMeters),
                facadeCandidate: facadeCandidate,
                distanceMeters: distanceMeters,
                route: route
            )
        }
        .sorted { lhs, rhs in
            lhs.distanceMeters < rhs.distanceMeters
        }

        let limitedRequests = Array(preparedRequests.prefix(maxActiveGeospatial3DAnchorCount))
        let requestedSpotIDs = Set(limitedRequests.map(\.spot.id))

        for spotID in previousActiveSpotIDs where !requestedSpotIDs.contains(spotID) {
            geospatialSessionManager.clearGeospatialDebugAnchor(
                for: spotID,
                reason: "둘러보기 TMAP 도착 좌표 후보 밖 / 3D 마커 제거"
            )
            fixedNearestFacadeCandidatesBySpotID[spotID] = nil
        }

        guard !limitedRequests.isEmpty else {
            if !previousActiveSpotIDs.isEmpty || !lastRequestedTerrainAnchorSpotIDs.isEmpty {
                geospatialSessionManager.clearAllGeospatialDebugAnchors(reason: "둘러보기 3D 후보 없음 / TMAP 도착 좌표가 있는 근처 POI가 없습니다.")
            }
            activeGeospatial3DSpotIDs = []
            fixedNearestFacadeCandidatesBySpotID = [:]
            markerPlacementDiagnosticsBySpotID = [:]
            lastRequestedTerrainAnchorSpotIDs = []
            geospatialWGS84CandidateDiagnostics = "둘러보기 3D 마커 대기 / TMAP 마지막 도착 좌표가 있는 근처 POI가 없습니다."
            return
        }

        let summaries = limitedRequests.map { request in
            requestGeospatialTerrainAnchorIfPossible(
                spot: request.spot,
                facadeCandidate: request.facadeCandidate,
                labelHeightMeters: request.labelHeight.valueMeters,
                origin: origin
            )
        }

        activeGeospatial3DSpotIDs = requestedSpotIDs
        fixedNearestFacadeCandidatesBySpotID = [:]
        markerPlacementDiagnosticsBySpotID = markerPlacementDiagnosticsBySpotID.filter {
            requestedSpotIDs.contains($0.key)
        }
        lastRequestedTerrainAnchorSpotIDs = requestedSpotIDs

        let markerDiagnostics = requestedSpotIDs
            .compactMap { markerPlacementDiagnosticsBySpotID[$0] }
            .sorted()
        let markerText = markerDiagnostics.isEmpty
            ? ""
            : " / 마커 좌표 판단: " + markerDiagnostics.joined(separator: " | ")
        geospatialWGS84CandidateDiagnostics = "둘러보기 3D 마커 \(requestedSpotIDs.count)개 / 모두 TMAP 마지막 도착 좌표 고정 / " + summaries.joined(separator: " | ") + markerText
    }

    private func requestGeospatialTerrainAnchorIfPossible(
        spot: TourismSpot,
        facadeCandidate: BuildingFacadeCandidate,
        labelHeightMeters: Double,
        origin: LocationSnapshot
    ) -> String {
        let candidates = terrainAnchorCandidates(
            from: facadeCandidate,
            labelHeightMeters: labelHeightMeters,
            origin: origin
        )
        let wgs84Fallback = wgs84AnchorFallbackCandidate(
            spot: spot,
            from: facadeCandidate,
            labelHeightMeters: labelHeightMeters,
            origin: origin
        )
        let fallbackSummary = wgs84Fallback.map {
            "\($0.label) / 좌표 \($0.coordinate.shortText) / 절대고도 \(String(format: "%.1f", $0.altitude))m"
        } ?? "절대고도 계산 불가"

        geospatialSessionManager.createTerrainAnchorIfPossible(
            for: GeospatialTerrainAnchorRequest(
                spotID: spot.id,
                spotName: spot.name,
                candidates: candidates,
                wgs84Fallback: wgs84Fallback
            )
        )
        return "\(spot.name) / \(facadeCandidate.selectionReason) / \(fallbackSummary)"
    }

    private func terrainAnchorCandidates(
        from facadeCandidate: BuildingFacadeCandidate,
        labelHeightMeters: Double,
        origin: LocationSnapshot
    ) -> [GeospatialTerrainAnchorCandidate] {
        var candidates = [
            GeospatialTerrainAnchorCandidate(
                label: facadeCandidate.selectionReason,
                coordinate: facadeCandidate.anchorCoordinate,
                altitudeAboveTerrain: labelHeightMeters
            )
        ]

        let anchorEast = facadeCandidate.anchorENU.eastMeters
        let anchorNorth = facadeCandidate.anchorENU.northMeters
        let anchorDistance = max(hypot(anchorEast, anchorNorth), 0.001)
        let unitEastTowardUser = -anchorEast / anchorDistance
        let unitNorthTowardUser = -anchorNorth / anchorDistance

        for offsetMeters in [2.0, 5.0] {
            let east = anchorEast + unitEastTowardUser * offsetMeters
            let north = anchorNorth + unitNorthTowardUser * offsetMeters
            let coordinate = LocalENUProjector.coordinate(
                eastMeters: east,
                northMeters: north,
                from: origin
            )
            candidates.append(
                GeospatialTerrainAnchorCandidate(
                    label: "사용자 방향 \(Int(offsetMeters))m 지면 후보",
                    coordinate: coordinate,
                    altitudeAboveTerrain: labelHeightMeters
                )
            )
        }

        candidates.append(
            GeospatialTerrainAnchorCandidate(
                label: "현재 위치 지면 지원 확인",
                coordinate: origin.coordinate,
                altitudeAboveTerrain: min(labelHeightMeters, 1.5)
            )
        )

        return candidates
    }

    private func wgs84AnchorFallbackCandidate(
        spot: TourismSpot,
        from facadeCandidate: BuildingFacadeCandidate,
        labelHeightMeters: Double,
        origin: LocationSnapshot
    ) -> GeospatialWGS84AnchorCandidate? {
        let deviceHeightAssumptionMeters = 1.5
        let relativeLabelHeightFromCameraGround = labelHeightMeters - deviceHeightAssumptionMeters
        let displayAnchorCoordinate: CLLocationCoordinate2D

        if isTMAPArrivalCandidate(facadeCandidate) {
            displayAnchorCoordinate = facadeCandidate.anchorCoordinate
        } else {
            guard let polygon = buildingPolygonsBySpotID[spot.id] else {
                geospatialWGS84CandidateDiagnostics = "\(spot.name) WGS84 후보 폐기 / Polygon이 없어 boundary 검증을 할 수 없습니다."
                return nil
            }

            displayAnchorCoordinate = closeRangeDisplayAnchorCoordinate(
                spot: spot,
                polygon: polygon,
                facadeCandidate: facadeCandidate,
                origin: origin
            )
            let coordinateAllowed = isManualMarkerCandidate(facadeCandidate)
                ? polygonAllowsMarkerCoordinate(displayAnchorCoordinate, polygon: polygon)
                : polygonAllowsDisplayCoordinate(displayAnchorCoordinate, polygon: polygon)
            guard coordinateAllowed else {
                geospatialWGS84CandidateDiagnostics = "\(spot.name) WGS84 후보 폐기 / 최종 좌표가 허용된 Polygon/대표 마커 범위 밖입니다."
                return nil
            }
        }

        let displayAnchorLabel = displayAnchorCoordinate.isApproximatelyEqual(to: facadeCandidate.anchorCoordinate)
            ? "\(facadeCandidate.selectionReason) WGS84 기준점"
            : "\(facadeCandidate.selectionReason) WGS84 기준점 / 근거리 외벽 안쪽 보정"

        if let geospatialAltitude = latestGeospatialLocationSnapshot?.altitude {
            return GeospatialWGS84AnchorCandidate(
                label: displayAnchorLabel,
                coordinate: displayAnchorCoordinate,
                altitude: geospatialAltitude + relativeLabelHeightFromCameraGround,
                altitudeSource: "ARCore Geospatial altitude \(String(format: "%.1f", geospatialAltitude))m + 라벨높이 \(String(format: "%.1f", labelHeightMeters))m - 기기높이 \(String(format: "%.1f", deviceHeightAssumptionMeters))m"
            )
        }

        guard let coreLocationAltitude = origin.altitude else {
            return nil
        }

        return GeospatialWGS84AnchorCandidate(
            label: displayAnchorLabel,
            coordinate: displayAnchorCoordinate,
            altitude: coreLocationAltitude + relativeLabelHeightFromCameraGround,
            altitudeSource: "CoreLocation altitude \(String(format: "%.1f", coreLocationAltitude))m + 라벨높이 \(String(format: "%.1f", labelHeightMeters))m - 기기높이 \(String(format: "%.1f", deviceHeightAssumptionMeters))m"
        )
    }

    private func closeRangeDisplayAnchorCoordinate(
        spot: TourismSpot,
        polygon: BuildingPolygon,
        facadeCandidate: BuildingFacadeCandidate,
        origin: LocationSnapshot
    ) -> CLLocationCoordinate2D {
        guard !isManualMarkerCandidate(facadeCandidate) else {
            return facadeCandidate.anchorCoordinate
        }

        guard facadeCandidate.distanceFromUserMeters < 5 else {
            return facadeCandidate.anchorCoordinate
        }

        let anchorENU = facadeCandidate.anchorENU
        let interiorTargetENU = LocalENUProjector.project(spot.center, from: origin)
        let directionEast = interiorTargetENU.eastMeters - anchorENU.eastMeters
        let directionNorth = interiorTargetENU.northMeters - anchorENU.northMeters
        let directionLength = hypot(directionEast, directionNorth)
        guard directionLength > 0.001 else {
            return facadeCandidate.anchorCoordinate
        }

        let inwardOffsetMeters = min(0.45, facadeCandidate.distanceFromUserMeters * 0.18)
        let adjustedCoordinate = LocalENUProjector.coordinate(
            eastMeters: anchorENU.eastMeters + (directionEast / directionLength) * inwardOffsetMeters,
            northMeters: anchorENU.northMeters + (directionNorth / directionLength) * inwardOffsetMeters,
            from: origin
        )
        guard polygonAllowsDisplayCoordinate(adjustedCoordinate, polygon: polygon) else {
            return facadeCandidate.anchorCoordinate
        }

        return adjustedCoordinate
    }

    private func isManualMarkerCandidate(_ candidate: BuildingFacadeCandidate) -> Bool {
        candidate.selectionReason.contains("수동 대표")
            || candidate.selectionReason.contains("수동 입구")
            || candidate.selectionReason.contains("TMAP 도착 좌표")
    }

    private func isTMAPArrivalCandidate(_ candidate: BuildingFacadeCandidate) -> Bool {
        candidate.selectionReason.contains("TMAP 도착 좌표")
    }

    private func tmapArrivalCandidate(
        spot: TourismSpot,
        route: TMAPPedestrianRoute,
        from origin: LocationSnapshot
    ) -> BuildingFacadeCandidate {
        let coordinate = route.arrivalCoordinate
        let enu = LocalENUProjector.project(coordinate, from: origin)
        let distanceMeters = enu.groundDistanceMeters
        markerPlacementDiagnosticsBySpotID[spot.id] = "\(spot.name): TMAP 도착 좌표 사용 / \(coordinate.shortText)"

        return BuildingFacadeCandidate(
            segmentKey: "\(spot.id)-tmap-arrival",
            startCoordinate: coordinate,
            endCoordinate: coordinate,
            midpointCoordinate: coordinate,
            anchorCoordinate: coordinate,
            startENU: enu,
            endENU: enu,
            midpointENU: enu,
            anchorENU: enu,
            lengthMeters: 0,
            distanceFromUserMeters: distanceMeters,
            rayDistanceMeters: 0,
            rayForwardDistanceMeters: distanceMeters,
            selectionReason: "TMAP 도착 좌표",
            stabilizationNote: "TMAP 보행자 경로 마지막 도착점: 사용자 heading으로 재계산하지 않음"
        )
    }

    private func labelHeightDecision(
        for resolvedHeight: ResolvedBuildingHeight,
        distanceMeters: CLLocationDistance
    ) -> BuildingLabelHeightDecision {
        let baseHeight: Double
        let rangeLabel: String

        switch distanceMeters {
        case ..<5:
            baseHeight = 1.7
            rangeLabel = "근거리 0~5m"
        case ..<30:
            let progress = ((distanceMeters - 5) / 25).clamped(to: 0...1)
            baseHeight = 3.0 + progress * 1.0
            rangeLabel = "중거리 5~30m"
        case ..<120:
            baseHeight = 5.0
            rangeLabel = "장거리 시야 30~120m"
        default:
            baseHeight = 5.0
            rangeLabel = "원거리 120m~1km"
        }

        let buildingHeightLimit = max(resolvedHeight.valueMeters * 0.6, 1.7)
        let resolvedHeightValue = min(baseHeight, buildingHeightLimit)
        let reason = "거리 기반 \(String(format: "%.1f", baseHeight))m, 건물 높이 60% 상한 \(String(format: "%.1f", buildingHeightLimit))m 적용"
        return BuildingLabelHeightDecision(
            valueMeters: resolvedHeightValue,
            rangeLabel: rangeLabel,
            reason: reason
        )
    }

    private func arrivalLabelHeightDecision(distanceMeters: CLLocationDistance) -> BuildingLabelHeightDecision {
        let rangeLabel: String

        switch distanceMeters {
        case ..<5:
            rangeLabel = "도착점 근거리 0~5m"
        case ..<30:
            rangeLabel = "도착점 중거리 5~30m"
        case ..<120:
            rangeLabel = "도착점 장거리 30~120m"
        default:
            rangeLabel = "도착점 원거리 120m~1km"
        }

        return BuildingLabelHeightDecision(
            valueMeters: 1.7,
            rangeLabel: rangeLabel,
            reason: "TMAP 도착 좌표는 현장 검증 전까지 지면 기준 눈높이 1.7m로 고정합니다."
        )
    }

    private func sourceHeightPropertiesText(for polygon: BuildingPolygon) -> String {
        let keys = ["HEIGHT", "height", "bld_height", "buld_hg", "gro_flo_co"]
        let values = keys.compactMap { key -> String? in
            guard let value = polygon.sourceProperties[key], !value.isEmpty else {
                return nil
            }
            return "\(key)=\(value)"
        }

        guard !values.isEmpty else {
            return " / 원본 높이 속성 없음"
        }
        return " / 원본 속성 \(values.joined(separator: ", "))"
    }

    private func cameraFacingFacadeCandidate(
        spot: TourismSpot,
        polygon: BuildingPolygon,
        from origin: LocationSnapshot,
        headingDegrees: Double?
    ) -> BuildingFacadeCandidate? {
        let segments = polygon.rings.flatMap { facadeSegments(for: $0, from: origin) }
        guard !segments.isEmpty else {
            return nil
        }

        guard let headingDegrees else {
            return segments.min { $0.distanceFromUserMeters < $1.distanceFromUserMeters }
        }

        let headingRadians = headingDegrees.degreesToRadians
        let rayDirectionEast = sin(headingRadians)
        let rayDirectionNorth = cos(headingRadians)

        let candidates = segments.map {
            facadeCandidateByCameraRay(
                $0,
                rayDirectionEast: rayDirectionEast,
                rayDirectionNorth: rayDirectionNorth,
                origin: origin
            )
        }

        let rawBest = candidates
            .filter { $0.rayForwardDistanceMeters >= 0 }
            .min {
                if $0.rayDistanceMeters == $1.rayDistanceMeters {
                    return $0.rayForwardDistanceMeters < $1.rayForwardDistanceMeters
                }
                return $0.rayDistanceMeters < $1.rayDistanceMeters
            }
            ?? candidates.min {
                if $0.rayDistanceMeters == $1.rayDistanceMeters {
                    return $0.distanceFromUserMeters < $1.distanceFromUserMeters
                }
                return $0.rayDistanceMeters < $1.rayDistanceMeters
            }

        guard let rawBest else {
            return nil
        }

        return stabilizedFacadeCandidate(
            rawBest: rawBest,
            candidates: candidates,
            spotID: spot.id
        )
    }

    private func nearestFacadeCandidate(
        spot: TourismSpot,
        polygon: BuildingPolygon,
        from origin: LocationSnapshot
    ) -> BuildingFacadeCandidate? {
        let segments = polygon.rings.flatMap { facadeSegments(for: $0, from: origin) }

        if let manualCandidate = manualMarkerCandidate(
            spot: spot,
            polygon: polygon,
            segments: segments,
            from: origin
        ) {
            fixedNearestFacadeCandidatesBySpotID[spot.id] = manualCandidate
            return manualCandidate
        }

        if spot.preferredMarkerCoordinate == nil, spot.entranceCoordinate == nil {
            markerPlacementDiagnosticsBySpotID[spot.id] = "\(spot.name): 수동 좌표 없음 -> 기존 외벽 fallback"
        }

        if activeGeospatial3DSpotIDs.contains(spot.id),
           let fixedCandidate = fixedNearestFacadeCandidatesBySpotID[spot.id],
           let currentSegment = segments.first(where: { $0.segmentKey == fixedCandidate.segmentKey }),
           polygonAllowsDisplayCoordinate(fixedCandidate.anchorCoordinate, polygon: polygon) {
            let anchorENU = LocalENUProjector.project(fixedCandidate.anchorCoordinate, from: origin)
            return currentSegment
                .withAnchor(
                    coordinate: fixedCandidate.anchorCoordinate,
                    enu: anchorENU,
                    rayDistanceMeters: anchorENU.groundDistanceMeters,
                    rayForwardDistanceMeters: anchorENU.groundDistanceMeters,
                    selectionReason: "고정된 최초 안정 외벽점"
                )
                .withStabilizationNote("기존 3D anchor 유지: 내 위치 이동만으로 외벽점 갱신 안 함")
        }

        guard let nearestSegment = segments.min(by: { $0.distanceFromUserMeters < $1.distanceFromUserMeters }) else {
            return nil
        }

        let closestPoint = closestPointOnSegmentToOrigin(
            startENU: nearestSegment.startENU,
            endENU: nearestSegment.endENU
        )
        let anchorCoordinate = interpolateCoordinate(
            from: nearestSegment.startCoordinate,
            to: nearestSegment.endCoordinate,
            ratio: closestPoint.segmentRatio
        )

        let candidate = nearestSegment
            .withAnchor(
                coordinate: anchorCoordinate,
                enu: closestPoint.anchorENU,
                rayDistanceMeters: closestPoint.distanceMeters,
                rayForwardDistanceMeters: closestPoint.anchorENU.groundDistanceMeters,
                selectionReason: "내 위치 기준 가장 가까운 외벽점"
            )
            .withStabilizationNote("카메라 방향과 무관한 선생성 기본점")
        fixedNearestFacadeCandidatesBySpotID[spot.id] = candidate
        return candidate
    }

    private func manualMarkerCandidate(
        spot: TourismSpot,
        polygon: BuildingPolygon,
        segments: [BuildingFacadeCandidate],
        from origin: LocationSnapshot
    ) -> BuildingFacadeCandidate? {
        let coordinate: CLLocationCoordinate2D
        let reason: String
        if let preferred = spot.preferredMarkerCoordinate {
            coordinate = preferred
            reason = "수동 대표 마커 좌표"
        } else if let entrance = spot.entranceCoordinate {
            coordinate = entrance
            reason = "수동 입구 마커 좌표"
        } else {
            return nil
        }

        guard polygonAllowsMarkerCoordinate(coordinate, polygon: polygon) else {
            let distance = polygon.rings
                .map { distanceFromCoordinate(coordinate, toRingBoundary: $0) }
                .min() ?? .greatestFiniteMagnitude
            markerPlacementDiagnosticsBySpotID[spot.id] = "\(spot.name): \(reason) 거부 / Polygon 외곽 거리 \(String(format: "%.1f", distance))m > \(Int(markerPlacementToleranceMeters))m"
            return nil
        }

        let markerENU = LocalENUProjector.project(coordinate, from: origin)
        let baseSegment = segments.min {
            distanceFromCoordinate(coordinate, toSegmentStart: $0.startCoordinate, end: $0.endCoordinate)
                < distanceFromCoordinate(coordinate, toSegmentStart: $1.startCoordinate, end: $1.endCoordinate)
        }

        guard let baseSegment else {
            markerPlacementDiagnosticsBySpotID[spot.id] = "\(spot.name): \(reason) 거부 / Polygon 외벽 선분 없음"
            return nil
        }

        markerPlacementDiagnosticsBySpotID[spot.id] = "\(spot.name): \(reason) 사용 / \(coordinate.shortText)"
        return baseSegment
            .withAnchor(
                coordinate: coordinate,
                enu: markerENU,
                rayDistanceMeters: markerENU.groundDistanceMeters,
                rayForwardDistanceMeters: markerENU.groundDistanceMeters,
                selectionReason: reason
            )
            .withStabilizationNote("수동 좌표 우선: 사용자 위치/heading으로 재계산하지 않음")
    }

    private func stabilizedFacadeCandidate(
        rawBest: BuildingFacadeCandidate,
        candidates: [BuildingFacadeCandidate],
        spotID: TourismSpot.ID
    ) -> BuildingFacadeCandidate {
        let now = Date()
        guard let previous = stableFacadeSelectionsBySpotID[spotID],
              let previousCandidate = candidates.first(where: { $0.segmentKey == previous.segmentKey }) else {
            stableFacadeSelectionsBySpotID[spotID] = StableBuildingFacadeSelection(
                segmentKey: rawBest.segmentKey,
                candidate: rawBest,
                pendingSegmentKey: nil,
                pendingFirstSeenAt: nil,
                switchedAt: now,
                decisionNote: "초기 외벽 선택"
            )
            return rawBest.withStabilizationNote("초기 외벽 선택")
        }

        if rawBest.segmentKey == previous.segmentKey {
            stableFacadeSelectionsBySpotID[spotID] = StableBuildingFacadeSelection(
                segmentKey: rawBest.segmentKey,
                candidate: rawBest,
                pendingSegmentKey: nil,
                pendingFirstSeenAt: nil,
                switchedAt: previous.switchedAt,
                decisionNote: "같은 외벽 유지"
            )
            return rawBest.withStabilizationNote("같은 외벽 유지")
        }

        let rayDistanceImprovement = previousCandidate.rayDistanceMeters - rawBest.rayDistanceMeters
        let directlyIntersects = rawBest.rayDistanceMeters == 0
        let previousDirectlyIntersects = previousCandidate.rayDistanceMeters == 0
        let previousIsBehindCamera = previousCandidate.rayForwardDistanceMeters < 0
        let isClearlyBetter = rayDistanceImprovement >= facadeSwitchRayDistanceImprovementMeters
            || (directlyIntersects && !previousDirectlyIntersects)
            || previousIsBehindCamera

        let pendingFirstSeenAt: Date
        if previous.pendingSegmentKey == rawBest.segmentKey,
           let firstSeen = previous.pendingFirstSeenAt {
            pendingFirstSeenAt = firstSeen
        } else {
            pendingFirstSeenAt = now
        }

        let pendingDuration = now.timeIntervalSince(pendingFirstSeenAt)
        let isConfirmed = pendingDuration >= facadeSwitchConfirmationInterval

        if isClearlyBetter && isConfirmed {
            let note = "외벽 전환: 개선 \(String(format: "%.1f", rayDistanceImprovement))m / 대기 \(String(format: "%.1f", pendingDuration))초"
            stableFacadeSelectionsBySpotID[spotID] = StableBuildingFacadeSelection(
                segmentKey: rawBest.segmentKey,
                candidate: rawBest,
                pendingSegmentKey: nil,
                pendingFirstSeenAt: nil,
                switchedAt: now,
                decisionNote: note
            )
            return rawBest.withStabilizationNote(note)
        }

        let note: String
        if isClearlyBetter {
            note = "이전 외벽 유지: 새 후보 확인 중 \(String(format: "%.1f", pendingDuration))초"
        } else {
            note = "이전 외벽 유지: 개선폭 \(String(format: "%.1f", rayDistanceImprovement))m 부족"
        }
        stableFacadeSelectionsBySpotID[spotID] = StableBuildingFacadeSelection(
            segmentKey: previous.segmentKey,
            candidate: previousCandidate,
            pendingSegmentKey: rawBest.segmentKey,
            pendingFirstSeenAt: pendingFirstSeenAt,
            switchedAt: previous.switchedAt,
            decisionNote: note
        )
        return previousCandidate.withStabilizationNote(note)
    }

    private func facadeSegments(
        for ring: [CLLocationCoordinate2D],
        from origin: LocationSnapshot
    ) -> [BuildingFacadeCandidate] {
        guard ring.count >= 2 else {
            return []
        }

        let ringIsClosed = ring.first?.isApproximatelyEqual(to: ring.last) == true
        let segmentCount = ringIsClosed ? ring.count - 1 : ring.count

        return (0..<segmentCount).compactMap { index in
            let startCoordinate = ring[index]
            let endCoordinate = ring[(index + 1) % ring.count]
            let startENU = LocalENUProjector.project(startCoordinate, from: origin)
            let endENU = LocalENUProjector.project(endCoordinate, from: origin)
            let deltaEast = endENU.eastMeters - startENU.eastMeters
            let deltaNorth = endENU.northMeters - startENU.northMeters
            let lengthMeters = hypot(deltaEast, deltaNorth)
            guard lengthMeters > 0.5 else {
                return nil
            }

            let midpointCoordinate = interpolateCoordinate(
                from: startCoordinate,
                to: endCoordinate,
                ratio: 0.5
            )
            let midpointENU = LocalENUProjector.project(midpointCoordinate, from: origin)
            let distanceFromUser = distanceFromOriginToSegment(
                startENU: startENU,
                endENU: endENU
            )

            return BuildingFacadeCandidate(
                segmentKey: facadeSegmentKey(startCoordinate: startCoordinate, endCoordinate: endCoordinate),
                startCoordinate: startCoordinate,
                endCoordinate: endCoordinate,
                midpointCoordinate: midpointCoordinate,
                anchorCoordinate: midpointCoordinate,
                startENU: startENU,
                endENU: endENU,
                midpointENU: midpointENU,
                anchorENU: midpointENU,
                lengthMeters: lengthMeters,
                distanceFromUserMeters: distanceFromUser,
                rayDistanceMeters: distanceFromUser,
                rayForwardDistanceMeters: midpointENU.groundDistanceMeters,
                selectionReason: "외벽 중점",
                stabilizationNote: nil
            )
        }
    }

    private func facadeSegmentKey(
        startCoordinate: CLLocationCoordinate2D,
        endCoordinate: CLLocationCoordinate2D
    ) -> String {
        let startKey = coordinateKey(startCoordinate)
        let endKey = coordinateKey(endCoordinate)
        return [startKey, endKey].sorted().joined(separator: "|")
    }

    private func coordinateKey(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(Int((coordinate.latitude * 1_000_000).rounded())):\(Int((coordinate.longitude * 1_000_000).rounded()))"
    }

    private func facadeCandidateByCameraRay(
        _ candidate: BuildingFacadeCandidate,
        rayDirectionEast: Double,
        rayDirectionNorth: Double,
        origin: LocationSnapshot
    ) -> BuildingFacadeCandidate {
        let segmentEast = candidate.endENU.eastMeters - candidate.startENU.eastMeters
        let segmentNorth = candidate.endENU.northMeters - candidate.startENU.northMeters
        let denominator = cross2D(
            eastA: rayDirectionEast,
            northA: rayDirectionNorth,
            eastB: segmentEast,
            northB: segmentNorth
        )

        if abs(denominator) > 0.000001 {
            let t = cross2D(
                eastA: candidate.startENU.eastMeters,
                northA: candidate.startENU.northMeters,
                eastB: segmentEast,
                northB: segmentNorth
            ) / denominator
            let u = cross2D(
                eastA: candidate.startENU.eastMeters,
                northA: candidate.startENU.northMeters,
                eastB: rayDirectionEast,
                northB: rayDirectionNorth
            ) / denominator

            if t >= 0, u >= 0, u <= 1 {
                let anchorENU = LocalENUCoordinate(
                    eastMeters: rayDirectionEast * t,
                    northMeters: rayDirectionNorth * t,
                    upMeters: 0
                )
                let anchorCoordinate = LocalENUProjector.coordinate(
                    eastMeters: anchorENU.eastMeters,
                    northMeters: anchorENU.northMeters,
                    from: origin
                )
                return candidate.withAnchor(
                    coordinate: anchorCoordinate,
                    enu: anchorENU,
                    rayDistanceMeters: 0,
                    rayForwardDistanceMeters: t,
                    selectionReason: "카메라 ray 교차점"
                )
            }
        }

        let projected = closestPointOnSegmentToRay(
            startENU: candidate.startENU,
            endENU: candidate.endENU,
            rayDirectionEast: rayDirectionEast,
            rayDirectionNorth: rayDirectionNorth
        )
        let anchorCoordinate = interpolateCoordinate(
            from: candidate.startCoordinate,
            to: candidate.endCoordinate,
            ratio: projected.segmentRatio
        )
        return candidate.withAnchor(
            coordinate: anchorCoordinate,
            enu: projected.anchorENU,
            rayDistanceMeters: projected.rayDistanceMeters,
            rayForwardDistanceMeters: projected.rayForwardDistanceMeters,
            selectionReason: "카메라 ray 최단 외벽점"
        )
    }

    private func closestPointOnSegmentToRay(
        startENU: LocalENUCoordinate,
        endENU: LocalENUCoordinate,
        rayDirectionEast: Double,
        rayDirectionNorth: Double
    ) -> (anchorENU: LocalENUCoordinate, segmentRatio: Double, rayDistanceMeters: Double, rayForwardDistanceMeters: Double) {
        let segmentEast = endENU.eastMeters - startENU.eastMeters
        let segmentNorth = endENU.northMeters - startENU.northMeters
        let segmentLengthSquared = max(segmentEast * segmentEast + segmentNorth * segmentNorth, 0.001)
        let midpoint = LocalENUCoordinate(
            eastMeters: (startENU.eastMeters + endENU.eastMeters) / 2,
            northMeters: (startENU.northMeters + endENU.northMeters) / 2,
            upMeters: 0
        )
        let midpointForward = max((midpoint.eastMeters * rayDirectionEast) + (midpoint.northMeters * rayDirectionNorth), 0)
        let rayPointEast = rayDirectionEast * midpointForward
        let rayPointNorth = rayDirectionNorth * midpointForward
        let startToRayEast = rayPointEast - startENU.eastMeters
        let startToRayNorth = rayPointNorth - startENU.northMeters
        let segmentRatio = ((startToRayEast * segmentEast) + (startToRayNorth * segmentNorth)) / segmentLengthSquared
        let clampedRatio = segmentRatio.clamped(to: 0...1)
        let anchorENU = LocalENUCoordinate(
            eastMeters: startENU.eastMeters + segmentEast * clampedRatio,
            northMeters: startENU.northMeters + segmentNorth * clampedRatio,
            upMeters: 0
        )
        let forward = (anchorENU.eastMeters * rayDirectionEast) + (anchorENU.northMeters * rayDirectionNorth)
        let perpendicular = abs(cross2D(
            eastA: rayDirectionEast,
            northA: rayDirectionNorth,
            eastB: anchorENU.eastMeters,
            northB: anchorENU.northMeters
        ))
        return (
            anchorENU: anchorENU,
            segmentRatio: clampedRatio,
            rayDistanceMeters: perpendicular,
            rayForwardDistanceMeters: forward
        )
    }

    private func closestPointOnSegmentToOrigin(
        startENU: LocalENUCoordinate,
        endENU: LocalENUCoordinate
    ) -> (anchorENU: LocalENUCoordinate, segmentRatio: Double, distanceMeters: Double) {
        let segmentEast = endENU.eastMeters - startENU.eastMeters
        let segmentNorth = endENU.northMeters - startENU.northMeters
        let segmentLengthSquared = segmentEast * segmentEast + segmentNorth * segmentNorth
        guard segmentLengthSquared > 0 else {
            return (
                anchorENU: startENU,
                segmentRatio: 0,
                distanceMeters: startENU.groundDistanceMeters
            )
        }

        let originToStartEast = -startENU.eastMeters
        let originToStartNorth = -startENU.northMeters
        let projectedRatio = ((originToStartEast * segmentEast) + (originToStartNorth * segmentNorth)) / segmentLengthSquared
        let clampedRatio = projectedRatio.clamped(to: 0...1)
        let anchorENU = LocalENUCoordinate(
            eastMeters: startENU.eastMeters + clampedRatio * segmentEast,
            northMeters: startENU.northMeters + clampedRatio * segmentNorth,
            upMeters: 0
        )

        return (
            anchorENU: anchorENU,
            segmentRatio: clampedRatio,
            distanceMeters: anchorENU.groundDistanceMeters
        )
    }

    private func interpolateCoordinate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        ratio: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * ratio,
            longitude: start.longitude + (end.longitude - start.longitude) * ratio
        )
    }

    private func cross2D(eastA: Double, northA: Double, eastB: Double, northB: Double) -> Double {
        eastA * northB - northA * eastB
    }

    private func distanceFromOriginToSegment(
        startENU: LocalENUCoordinate,
        endENU: LocalENUCoordinate
    ) -> Double {
        let segmentEast = endENU.eastMeters - startENU.eastMeters
        let segmentNorth = endENU.northMeters - startENU.northMeters
        let segmentLengthSquared = segmentEast * segmentEast + segmentNorth * segmentNorth
        guard segmentLengthSquared > 0 else {
            return startENU.groundDistanceMeters
        }

        let originToStartEast = -startENU.eastMeters
        let originToStartNorth = -startENU.northMeters
        let projectedRatio = ((originToStartEast * segmentEast) + (originToStartNorth * segmentNorth)) / segmentLengthSquared
        let clampedRatio = projectedRatio.clamped(to: 0...1)
        let closestEast = startENU.eastMeters + clampedRatio * segmentEast
        let closestNorth = startENU.northMeters + clampedRatio * segmentNorth
        return hypot(closestEast, closestNorth)
    }

    private func polygonAllowsDisplayCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        polygon: BuildingPolygon
    ) -> Bool {
        if polygonContains(coordinate, polygon: polygon) {
            return true
        }

        return polygon.rings
            .map { distanceFromCoordinate(coordinate, toRingBoundary: $0) }
            .min() ?? .greatestFiniteMagnitude <= polygonBoundaryToleranceMeters
    }

    private func polygonAllowsMarkerCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        polygon: BuildingPolygon
    ) -> Bool {
        if polygonContains(coordinate, polygon: polygon) {
            return true
        }

        return polygon.rings
            .map { distanceFromCoordinate(coordinate, toRingBoundary: $0) }
            .min() ?? .greatestFiniteMagnitude <= markerPlacementToleranceMeters
    }

    private func polygonContains(
        _ coordinate: CLLocationCoordinate2D,
        polygon: BuildingPolygon
    ) -> Bool {
        polygon.rings.contains { ring in
            ringContains(coordinate, ring: ring)
        }
    }

    private func ringContains(
        _ coordinate: CLLocationCoordinate2D,
        ring: [CLLocationCoordinate2D]
    ) -> Bool {
        guard ring.count >= 3 else {
            return false
        }

        let pointX = coordinate.longitude
        let pointY = coordinate.latitude
        var isInside = false
        var previousIndex = ring.count - 1

        for currentIndex in ring.indices {
            let current = ring[currentIndex]
            let previous = ring[previousIndex]

            if coordinateIsOnSegment(
                coordinate,
                start: previous,
                end: current
            ) {
                return true
            }

            let intersects = (current.latitude > pointY) != (previous.latitude > pointY)
                && pointX < (previous.longitude - current.longitude) * (pointY - current.latitude) / (previous.latitude - current.latitude) + current.longitude
            if intersects {
                isInside.toggle()
            }

            previousIndex = currentIndex
        }

        return isInside
    }

    private func distanceFromCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        toRingBoundary ring: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        guard ring.count >= 2 else {
            return .greatestFiniteMagnitude
        }

        var minimumDistance = CLLocationDistance.greatestFiniteMagnitude
        for index in 1..<ring.count {
            minimumDistance = min(
                minimumDistance,
                distanceFromCoordinate(
                    coordinate,
                    toSegmentStart: ring[index - 1],
                    end: ring[index]
                )
            )
        }
        return minimumDistance
    }

    private func distanceFromCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        toSegmentStart start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let metersPerLatitudeDegree = 111_320.0
        let metersPerLongitudeDegree = cos(coordinate.latitude * .pi / 180) * metersPerLatitudeDegree

        let pointX = coordinate.longitude * metersPerLongitudeDegree
        let pointY = coordinate.latitude * metersPerLatitudeDegree
        let startX = start.longitude * metersPerLongitudeDegree
        let startY = start.latitude * metersPerLatitudeDegree
        let endX = end.longitude * metersPerLongitudeDegree
        let endY = end.latitude * metersPerLatitudeDegree

        let segmentX = endX - startX
        let segmentY = endY - startY
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY
        guard segmentLengthSquared > 0 else {
            return hypot(pointX - startX, pointY - startY)
        }

        let rawProjection = ((pointX - startX) * segmentX + (pointY - startY) * segmentY) / segmentLengthSquared
        let projection = min(1, max(0, rawProjection))
        let projectedX = startX + projection * segmentX
        let projectedY = startY + projection * segmentY
        return hypot(pointX - projectedX, pointY - projectedY)
    }

    private func coordinateIsOnSegment(
        _ coordinate: CLLocationCoordinate2D,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> Bool {
        let epsilon = 0.000000001
        let crossProduct = (coordinate.latitude - start.latitude) * (end.longitude - start.longitude)
            - (coordinate.longitude - start.longitude) * (end.latitude - start.latitude)
        guard abs(crossProduct) <= epsilon else {
            return false
        }

        let minLongitude = min(start.longitude, end.longitude) - epsilon
        let maxLongitude = max(start.longitude, end.longitude) + epsilon
        let minLatitude = min(start.latitude, end.latitude) - epsilon
        let maxLatitude = max(start.latitude, end.latitude) + epsilon
        return coordinate.longitude >= minLongitude
            && coordinate.longitude <= maxLongitude
            && coordinate.latitude >= minLatitude
            && coordinate.latitude <= maxLatitude
    }

    private func updateSpatialAlignmentDiagnostics(for candidate: CameraDirectionCandidate) {
        guard let heading = cameraHeadingDegrees else {
            spatialAlignmentDiagnostics = "카메라 heading이 없어 방향각 차이를 계산할 수 없습니다."
            return
        }

        var message = "\(candidate.spot.name) 방향각 \(Int(candidate.bearingDegrees))도 / heading \(Int(heading))도 / 차이 \(Int(candidate.headingDifferenceDegrees))도 / 거리 \(Int(candidate.distanceMeters))m"
        if let polygon = buildingPolygonsBySpotID[candidate.spot.id],
           let centroidDiagnostics = polygonCentroidDiagnostics(for: polygon) {
            message += " / \(centroidDiagnostics)"
        }
        spatialAlignmentDiagnostics = message
    }

    private func updateSpatialAlignmentDiagnostics(for spot: TourismSpot, polygon: BuildingPolygon) {
        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees,
              let centroid = polygon.centroid else {
            spatialAlignmentDiagnostics = "\(spot.name) Polygon 확보. 위치/heading/centroid 중 일부가 없어 정렬 차이는 계산하지 못했습니다."
            return
        }

        let bearing = latestLocationSnapshot.coordinate.bearing(to: centroid)
        let difference = heading.angularDifference(to: bearing)
        let distance = latestLocationSnapshot.coordinate.distance(to: centroid)
        spatialAlignmentDiagnostics = "\(spot.name) Polygon centroid 방향각 \(Int(bearing))도 / heading \(Int(heading))도 / 차이 \(Int(difference))도 / centroid 거리 \(Int(distance))m"
        updatePolygonProjectionDiagnostics(for: spot, polygon: polygon)
    }

    private func polygonCentroidDiagnostics(for polygon: BuildingPolygon) -> String? {
        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees,
              let centroid = polygon.centroid else {
            return nil
        }

        let bearing = latestLocationSnapshot.coordinate.bearing(to: centroid)
        let difference = heading.angularDifference(to: bearing)
        return "Polygon centroid 방향각 \(Int(bearing))도 / 차이 \(Int(difference))도"
    }

    private func updatePolygonProjectionDiagnostics(for spot: TourismSpot, polygon: BuildingPolygon) {
        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees,
              let pose = cameraPoseSnapshot else {
            polygonProjectionDiagnostics = "\(spot.name) Polygon 확보. 위치/heading/pose 중 일부가 없어 화면 투영은 계산하지 못했습니다."
            return
        }

        let vertices = polygon.rings.flatMap { $0 }
        guard !vertices.isEmpty else {
            polygonProjectionDiagnostics = "\(spot.name) Polygon 외곽 좌표가 없어 화면 투영을 계산하지 못했습니다."
            return
        }

        let projectedPoints = vertices.map {
            projectCoordinate(
                $0,
                from: latestLocationSnapshot.coordinate,
                headingDegrees: heading,
                pitchDegrees: pose.pitchDegrees
            )
        }
        let insideCount = projectedPoints.filter(\.isInsideView).count
        let intersectsView = polygonIntersectsView(projectedPoints)
        let horizontalRange = projectedPoints.map(\.horizontalDeltaDegrees).rangeDescription
        let verticalRange = projectedPoints.map(\.verticalDeltaDegrees).rangeDescription
        let visibleText = intersectsView ? "시야 교차" : "시야 밖"

        var message = "\(spot.name) 화면 투영: \(visibleText) / 화면 안 외곽점 \(insideCount)/\(projectedPoints.count)개 / 수평각 \(horizontalRange) / 수직각 \(verticalRange) / FOV \(Int(projectionHorizontalFOVDegrees))x\(Int(projectionVerticalFOVDegrees))도"
        if let evidence = sceneSemanticsEvidenceBySpotID[spot.id] {
            message += " / \(evidence.diagnosticText)"
        }
        polygonProjectionDiagnostics = message
        refreshMatrixProjectionComparisonDiagnostics(for: spot, polygon: polygon, fovProjectedPoints: projectedPoints)
    }

    private func refreshMatrixProjectionComparisonDiagnostics() {
        guard let latestLocationSnapshot else {
            matrixProjectionComparisonDiagnostics = "현재 위치가 없어 projection matrix 비교를 계산할 수 없습니다."
            matrixProjectionDebugOverlay = nil
            return
        }

        guard let heading = cameraHeadingDegrees,
              let pose = cameraPoseSnapshot else {
            matrixProjectionComparisonDiagnostics = "heading/pose 중 일부가 없어 projection matrix 비교를 계산할 수 없습니다."
            matrixProjectionDebugOverlay = nil
            return
        }

        guard let cameraProjectionSnapshot else {
            matrixProjectionComparisonDiagnostics = "ARFrame camera matrix 샘플이 없어 projection matrix 비교를 계산할 수 없습니다."
            matrixProjectionDebugOverlay = nil
            return
        }

        guard let spot = localCoordinateTargetSpot(from: latestLocationSnapshot) else {
            matrixProjectionComparisonDiagnostics = "projection matrix 비교 대상 후보가 없습니다."
            matrixProjectionDebugOverlay = nil
            return
        }

        let polygon = buildingPolygonsBySpotID[spot.id]
        let coordinates = polygon?.rings.flatMap { $0 } ?? [spot.center]
        let fovProjectedPoints = coordinates.map {
            projectCoordinate(
                $0,
                from: latestLocationSnapshot.coordinate,
                headingDegrees: heading,
                pitchDegrees: pose.pitchDegrees
            )
        }
        refreshMatrixProjectionComparisonDiagnostics(
            for: spot,
            polygon: polygon,
            fovProjectedPoints: fovProjectedPoints,
            cameraProjectionSnapshot: cameraProjectionSnapshot,
            latestLocationSnapshot: latestLocationSnapshot
        )
    }

    private func refreshMatrixProjectionComparisonDiagnostics(
        for spot: TourismSpot,
        polygon: BuildingPolygon?,
        fovProjectedPoints: [ProjectedPolygonPoint]
    ) {
        guard let cameraProjectionSnapshot,
              let latestLocationSnapshot else {
            matrixProjectionComparisonDiagnostics = "\(spot.name) projection matrix 비교 대기: matrix/위치 중 일부가 없습니다."
            matrixProjectionDebugOverlay = nil
            return
        }

        refreshMatrixProjectionComparisonDiagnostics(
            for: spot,
            polygon: polygon,
            fovProjectedPoints: fovProjectedPoints,
            cameraProjectionSnapshot: cameraProjectionSnapshot,
            latestLocationSnapshot: latestLocationSnapshot
        )
    }

    private func refreshMatrixProjectionComparisonDiagnostics(
        for spot: TourismSpot,
        polygon: BuildingPolygon?,
        fovProjectedPoints: [ProjectedPolygonPoint],
        cameraProjectionSnapshot: CameraProjectionSnapshot,
        latestLocationSnapshot: LocationSnapshot
    ) {
        let coordinates = polygon?.rings.flatMap { $0 } ?? [spot.center]
        guard !coordinates.isEmpty else {
            matrixProjectionComparisonDiagnostics = "\(spot.name) projection matrix 비교 실패: 투영할 좌표가 없습니다."
            matrixProjectionDebugOverlay = nil
            return
        }

        let matrixProjectedPoints = coordinates.compactMap {
            CameraMatrixProjector.project(
                $0,
                from: latestLocationSnapshot,
                using: cameraProjectionSnapshot
            )
        }
        guard !matrixProjectedPoints.isEmpty else {
            matrixProjectionComparisonDiagnostics = "\(spot.name) projection matrix 비교 실패: 유효한 matrix 투영 좌표가 없습니다."
            matrixProjectionDebugOverlay = nil
            return
        }

        let fovAnchor = overlayFallbackAnchor(for: fovProjectedPoints)
        let matrixAnchor = matrixFallbackAnchor(for: matrixProjectedPoints)
        let deltaX = Double(matrixAnchor.x - fovAnchor.x) * 100
        let deltaY = Double(matrixAnchor.y - fovAnchor.y) * 100
        let matrixInsideCount = matrixProjectedPoints.filter(\.isInsideView).count
        let targetText = polygon == nil ? "POI" : "Polygon"
        let fovText = "FOV x \(Int(fovAnchor.x * 100))% y \(Int(fovAnchor.y * 100))%"
        let matrixText = "matrix x \(Int(matrixAnchor.x * 100))% y \(Int(matrixAnchor.y * 100))%"
        let deltaText = "차이 x \(Int(deltaX))%p y \(Int(deltaY))%p"

        matrixProjectionComparisonDiagnostics = "\(spot.name) \(targetText) 투영 비교 / \(fovText) / \(matrixText) / \(deltaText) / matrix 화면 안 \(matrixInsideCount)/\(matrixProjectedPoints.count)개"
        matrixProjectionDebugOverlay = MatrixProjectionDebugOverlay(
            spotID: spot.id,
            title: "matrix",
            normalizedX: Double(matrixAnchor.x).clamped(to: 0.04...0.96),
            normalizedY: Double(matrixAnchor.y).clamped(to: 0.08...0.86),
            isInsideView: matrixInsideCount > 0,
            insidePointCount: matrixInsideCount,
            totalPointCount: matrixProjectedPoints.count
        )
    }

    private func refreshSceneSemanticsScoring() {
        guard let snapshot = latestSceneSemanticsSnapshot else {
            sceneSemanticsEvidenceBySpotID = [:]
            sceneSemanticsScoringDiagnostics = "Scene Semantics semantic image를 아직 받지 못했습니다."
            return
        }

        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees,
              let pose = cameraPoseSnapshot else {
            sceneSemanticsEvidenceBySpotID = [:]
            sceneSemanticsScoringDiagnostics = "위치/heading/pose 중 일부가 없어 Scene Semantics 라벨 보정을 계산하지 못했습니다."
            return
        }

        let visibleSpotIDs = Set(spots.map(\.id))
        let evidenceBySpotID = buildingPolygonsBySpotID.reduce(into: [TourismSpot.ID: SceneSemanticsSpotEvidence]()) { partialResult, item in
            let spotID = item.key
            let polygon = item.value
            guard visibleSpotIDs.contains(spotID) else {
                return
            }

            let projectedPolygon = polygon.rings
                .flatMap { $0 }
                .map {
                    projectCoordinate(
                        $0,
                        from: latestLocationSnapshot.coordinate,
                        headingDegrees: heading,
                        pitchDegrees: pose.pitchDegrees
                    )
                }
            guard polygonIntersectsView(projectedPolygon) else {
                return
            }

            let normalizedPoints = projectedPolygon.map {
                CGPoint(x: $0.screenX, y: $0.screenY)
            }
            if let evidence = snapshot.evidence(in: normalizedPoints) {
                partialResult[spotID] = evidence
            }
        }

        sceneSemanticsEvidenceBySpotID = evidenceBySpotID
        refreshARLabelOverlay()

        if evidenceBySpotID.isEmpty {
            sceneSemanticsScoringDiagnostics = "화면에 투영된 Polygon 중 Scene Semantics 라벨 보정 대상이 없습니다."
            return
        }

        let spotNamesByID = Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0.name) })
        sceneSemanticsScoringDiagnostics = evidenceBySpotID
            .sorted { $0.value.buildingCoverageRatio > $1.value.buildingCoverageRatio }
            .map { spotID, evidence in
                "\(spotNamesByID[spotID] ?? spotID): \(evidence.diagnosticText)"
            }
            .joined(separator: "\n")
    }

    private func refreshARLabelOverlay() {
        guard let spot = recognitionResult.labelSpot ?? selectedSpot else {
            arLabelOverlay = nil
            edgeMarkerOverlays = []
            onScreenCandidateMarkerOverlays = []
            arLabelOverlayDiagnostics = "인식/선택된 후보가 없어 AR 라벨을 숨깁니다."
            return
        }

        guard let latestLocationSnapshot,
              let heading = cameraHeadingDegrees,
              let pose = cameraPoseSnapshot else {
            arLabelOverlay = nil
            edgeMarkerOverlays = []
            onScreenCandidateMarkerOverlays = []
            arLabelOverlayDiagnostics = "\(spot.name) 라벨 계산 대기: 위치/heading/pose 중 일부가 없습니다."
            return
        }

        let polygon = buildingPolygonsBySpotID[spot.id]
        let projectedPoints: [ProjectedPolygonPoint]
        if let polygon {
            projectedPoints = polygon.rings
                .flatMap { $0 }
                .map {
                    projectCoordinate(
                        $0,
                        from: latestLocationSnapshot.coordinate,
                        headingDegrees: heading,
                        pitchDegrees: pose.pitchDegrees
                    )
                }
        } else {
            projectedPoints = [
                projectCoordinate(
                    spot.center,
                    from: latestLocationSnapshot.coordinate,
                    headingDegrees: heading,
                    pitchDegrees: pose.pitchDegrees
                )
            ]
        }

        let matrixProjectedPoints = matrixProjectedPoints(for: spot, polygon: polygon, from: latestLocationSnapshot)
        let matrixInsideCount = matrixProjectedPoints.filter(\.isInsideView).count
        let useMatrixProjection = matrixInsideCount > 0
        let fovIntersectsView = polygonIntersectsView(projectedPoints)
        let fallbackHeadingDelta = fovFallbackHeadingDelta(
            for: spot,
            polygon: polygon,
            from: latestLocationSnapshot,
            headingDegrees: heading
        )
        let fovFallbackAllowed = fovIntersectsView
            && fallbackHeadingDelta <= fovFallbackMaxHeadingDeltaDegrees

        guard useMatrixProjection || fovFallbackAllowed else {
            arLabelOverlay = nil
            refreshEdgeMarkerOverlays()
            if fovIntersectsView {
                arLabelOverlayDiagnostics = "\(spot.name) 라벨 숨김: matrix 화면 밖, FOV fallback 방향각 차이 \(Int(fallbackHeadingDelta))도가 허용값 \(Int(fovFallbackMaxHeadingDeltaDegrees))도를 초과했습니다."
            } else {
                arLabelOverlayDiagnostics = "\(spot.name) 라벨 숨김: matrix/FOV 투영 좌표가 모두 현재 화면 밖입니다."
            }
            return
        }

        let projectionAnchor: CGPoint
        let normalizedPolygon: [CGPoint]
        let projectionSource: String
        if useMatrixProjection {
            projectionAnchor = matrixFallbackAnchor(for: matrixProjectedPoints)
            normalizedPolygon = matrixProjectedPoints.map {
                CGPoint(x: $0.screenX.clamped(to: 0...1), y: $0.screenY.clamped(to: 0...1))
            }
            projectionSource = "projection matrix"
        } else {
            projectionAnchor = overlayFallbackAnchor(for: projectedPoints)
            normalizedPolygon = projectedPoints.map {
                CGPoint(x: $0.screenX.clamped(to: 0...1), y: $0.screenY.clamped(to: 0...1))
            }
            projectionSource = "FOV fallback 방향각 차이 \(Int(fallbackHeadingDelta))도"
        }

        let semanticAnchor = latestSceneSemanticsSnapshot?.buildingLabelAnchor(in: normalizedPolygon)
        let anchor = semanticAnchor ?? projectionAnchor
        let smoothedAnchor = smoothedLabelAnchor(for: spot.id, next: anchor)
        let confidence = recognitionResult.labelConfidence ?? .medium
        let distance = latestLocationSnapshot.coordinate.distance(to: spot.center)
        let evidenceText = sceneSemanticsEvidenceBySpotID[spot.id].map {
            " / building \(Int(($0.buildingCoverageRatio * 100).rounded()))%"
        } ?? ""
        let subtitle = "\(Int(distance))m / \(confidence.displayName)\(evidenceText)"

        arLabelOverlay = ARLabelOverlay(
            spotID: spot.id,
            title: spot.name,
            subtitle: subtitle,
            normalizedX: Double(smoothedAnchor.x).clamped(to: 0.08...0.92),
            normalizedY: Double(smoothedAnchor.y).clamped(to: 0.12...0.78),
            confidence: confidence,
            isSceneSemanticsAdjusted: semanticAnchor != nil
        )

        let anchorSource = semanticAnchor == nil ? projectionSource : "\(projectionSource) + Scene Semantics building 중심"
        arLabelOverlayDiagnostics = "\(spot.name) AR 라벨 표시 / \(anchorSource) / x \(Int(smoothedAnchor.x * 100))% y \(Int(smoothedAnchor.y * 100))% / matrix 화면 안 \(matrixInsideCount)/\(max(matrixProjectedPoints.count, 1))개"
        refreshEdgeMarkerOverlays()
        refreshOnScreenCandidateMarkerOverlays()
    }

    private func fovFallbackHeadingDelta(
        for spot: TourismSpot,
        polygon: BuildingPolygon?,
        from latestLocationSnapshot: LocationSnapshot,
        headingDegrees: Double
    ) -> Double {
        let targetCoordinate = polygon?.centroid ?? spot.center
        let bearing = latestLocationSnapshot.coordinate.bearing(to: targetCoordinate)
        return headingDegrees.angularDifference(to: bearing)
    }

    private func matrixProjectedPoints(
        for spot: TourismSpot,
        polygon: BuildingPolygon?,
        from latestLocationSnapshot: LocationSnapshot
    ) -> [CameraMatrixProjectedPoint] {
        guard let cameraProjectionSnapshot else {
            return []
        }

        let coordinates = polygon?.rings.flatMap { $0 } ?? [spot.center]
        return coordinates.compactMap {
            CameraMatrixProjector.project(
                $0,
                from: latestLocationSnapshot,
                using: cameraProjectionSnapshot
            )
        }
    }

    private func overlayFallbackAnchor(for projectedPoints: [ProjectedPolygonPoint]) -> CGPoint {
        let visiblePoints = projectedPoints.map {
            (x: $0.screenX.clamped(to: 0...1), y: $0.screenY.clamped(to: 0...1))
        }
        guard !visiblePoints.isEmpty else {
            return CGPoint(x: 0.5, y: 0.45)
        }

        let minX = visiblePoints.map(\.x).min() ?? 0.5
        let maxX = visiblePoints.map(\.x).max() ?? 0.5
        let minY = visiblePoints.map(\.y).min() ?? 0.45
        let maxY = visiblePoints.map(\.y).max() ?? minY
        let y = minY + max(0.03, (maxY - minY) * 0.25)
        return CGPoint(x: (minX + maxX) / 2, y: y)
    }

    private func matrixFallbackAnchor(for projectedPoints: [CameraMatrixProjectedPoint]) -> CGPoint {
        let visiblePoints = projectedPoints.map {
            (x: $0.screenX.clamped(to: 0...1), y: $0.screenY.clamped(to: 0...1))
        }
        guard !visiblePoints.isEmpty else {
            return CGPoint(x: 0.5, y: 0.45)
        }

        let minX = visiblePoints.map(\.x).min() ?? 0.5
        let maxX = visiblePoints.map(\.x).max() ?? 0.5
        let minY = visiblePoints.map(\.y).min() ?? 0.45
        let maxY = visiblePoints.map(\.y).max() ?? minY
        let y = minY + max(0.03, (maxY - minY) * 0.25)
        return CGPoint(x: (minX + maxX) / 2, y: y)
    }

    private func smoothedLabelAnchor(for spotID: TourismSpot.ID, next: CGPoint) -> CGPoint {
        guard let current = arLabelOverlay, current.spotID == spotID else {
            return next
        }

        let previousWeight = 0.72
        let nextWeight = 1 - previousWeight
        return CGPoint(
            x: current.normalizedX * previousWeight + Double(next.x) * nextWeight,
            y: current.normalizedY * previousWeight + Double(next.y) * nextWeight
        )
    }

    private func projectCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        from origin: CLLocationCoordinate2D,
        headingDegrees: Double,
        pitchDegrees: Double
    ) -> ProjectedPolygonPoint {
        let bearing = origin.bearing(to: coordinate)
        let horizontalDelta = headingDegrees.signedAngularDifference(to: bearing)
        let verticalDelta = -pitchDegrees
        let screenX = 0.5 + horizontalDelta / projectionHorizontalFOVDegrees
        let screenY = 0.5 - verticalDelta / projectionVerticalFOVDegrees
        let isInside = abs(horizontalDelta) <= projectionHorizontalFOVDegrees / 2
            && abs(verticalDelta) <= projectionVerticalFOVDegrees / 2

        return ProjectedPolygonPoint(
            horizontalDeltaDegrees: horizontalDelta,
            verticalDeltaDegrees: verticalDelta,
            screenX: screenX,
            screenY: screenY,
            isInsideView: isInside
        )
    }

    private func polygonIntersectsView(_ projectedPoints: [ProjectedPolygonPoint]) -> Bool {
        guard !projectedPoints.isEmpty else {
            return false
        }

        if projectedPoints.contains(where: \.isInsideView) {
            return true
        }

        let horizontalValues = projectedPoints.map(\.horizontalDeltaDegrees)
        let verticalValues = projectedPoints.map(\.verticalDeltaDegrees)
        guard let minHorizontal = horizontalValues.min(),
              let maxHorizontal = horizontalValues.max(),
              let minVertical = verticalValues.min(),
              let maxVertical = verticalValues.max() else {
            return false
        }

        let halfHorizontalFOV = projectionHorizontalFOVDegrees / 2
        let halfVerticalFOV = projectionVerticalFOVDegrees / 2
        let overlapsHorizontalFOV = minHorizontal <= halfHorizontalFOV && maxHorizontal >= -halfHorizontalFOV
        let overlapsVerticalFOV = minVertical <= halfVerticalFOV && maxVertical >= -halfVerticalFOV
        return overlapsHorizontalFOV && overlapsVerticalFOV
    }

    private static func locationConfidence(for horizontalAccuracy: CLLocationAccuracy) -> RecognitionConfidence {
        if horizontalAccuracy <= 10 {
            return .high
        }
        if horizontalAccuracy <= 25 {
            return .medium
        }
        return .low
    }
}

private struct ProjectedPolygonPoint {
    let horizontalDeltaDegrees: Double
    let verticalDeltaDegrees: Double
    let screenX: Double
    let screenY: Double
    let isInsideView: Bool
}

private struct BuildingFacadeCandidate {
    let segmentKey: String
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
    let midpointCoordinate: CLLocationCoordinate2D
    let anchorCoordinate: CLLocationCoordinate2D
    let startENU: LocalENUCoordinate
    let endENU: LocalENUCoordinate
    let midpointENU: LocalENUCoordinate
    let anchorENU: LocalENUCoordinate
    let lengthMeters: Double
    let distanceFromUserMeters: Double
    let rayDistanceMeters: Double
    let rayForwardDistanceMeters: Double
    let selectionReason: String
    let stabilizationNote: String?

    func withAnchor(
        coordinate: CLLocationCoordinate2D,
        enu: LocalENUCoordinate,
        rayDistanceMeters: Double,
        rayForwardDistanceMeters: Double,
        selectionReason: String
    ) -> BuildingFacadeCandidate {
        BuildingFacadeCandidate(
            segmentKey: segmentKey,
            startCoordinate: startCoordinate,
            endCoordinate: endCoordinate,
            midpointCoordinate: midpointCoordinate,
            anchorCoordinate: coordinate,
            startENU: startENU,
            endENU: endENU,
            midpointENU: midpointENU,
            anchorENU: enu,
            lengthMeters: lengthMeters,
            distanceFromUserMeters: distanceFromUserMeters,
            rayDistanceMeters: rayDistanceMeters,
            rayForwardDistanceMeters: rayForwardDistanceMeters,
            selectionReason: selectionReason,
            stabilizationNote: stabilizationNote
        )
    }

    func withStabilizationNote(_ note: String) -> BuildingFacadeCandidate {
        BuildingFacadeCandidate(
            segmentKey: segmentKey,
            startCoordinate: startCoordinate,
            endCoordinate: endCoordinate,
            midpointCoordinate: midpointCoordinate,
            anchorCoordinate: anchorCoordinate,
            startENU: startENU,
            endENU: endENU,
            midpointENU: midpointENU,
            anchorENU: anchorENU,
            lengthMeters: lengthMeters,
            distanceFromUserMeters: distanceFromUserMeters,
            rayDistanceMeters: rayDistanceMeters,
            rayForwardDistanceMeters: rayForwardDistanceMeters,
            selectionReason: selectionReason,
            stabilizationNote: note
        )
    }
}

private struct StableBuildingFacadeSelection {
    let segmentKey: String
    let candidate: BuildingFacadeCandidate
    let pendingSegmentKey: String?
    let pendingFirstSeenAt: Date?
    let switchedAt: Date
    let decisionNote: String
}

private struct BuildingLabelHeightDecision {
    let valueMeters: Double
    let rangeLabel: String
    let reason: String
}

private extension RecognitionResult {
    var labelSpot: TourismSpot? {
        switch self {
        case let .recognized(spot, _, _), let .nearby(spot, _):
            return spot
        case .ambiguous, .none:
            return nil
        }
    }

    var labelConfidence: RecognitionConfidence? {
        switch self {
        case let .recognized(_, confidence, _):
            return confidence
        case .nearby:
            return .medium
        case .ambiguous, .none:
            return nil
        }
    }
}

private extension [TourismSpot] {
    var isMockFallback: Bool {
        !isEmpty && allSatisfy { $0.source == .mock }
    }

    func deduplicatedByID() -> [TourismSpot] {
        var seenIDs: Set<TourismSpot.ID> = []
        return filter { spot in
            seenIDs.insert(spot.id).inserted
        }
    }
}

private extension TourismSpot {
    var edgeMarkerShortTitle: String {
        switch name {
        case "투썸플레이스":
            return "투썸"
        default:
            return name.replacingOccurrences(of: " ", with: "")
        }
    }
}

private extension Double {
    var degreesToRadians: Double {
        self * .pi / 180
    }

    var radiansToDegrees: Double {
        self * 180 / .pi
    }

    var normalizedDegrees: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    func angularDifference(to other: Double) -> Double {
        let difference = abs(normalizedDegrees - other.normalizedDegrees)
        return min(difference, 360 - difference)
    }

    func signedAngularDifference(to other: Double) -> Double {
        var difference = other.normalizedDegrees - normalizedDegrees
        if difference > 180 {
            difference -= 360
        }
        if difference < -180 {
            difference += 360
        }
        return difference
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension [Double] {
    var rangeDescription: String {
        guard let min = self.min(), let max = self.max() else {
            return "없음"
        }
        return "\(Int(min))...\(Int(max))도"
    }

    var metersRangeDescription: String? {
        guard let min = self.min(), let max = self.max() else {
            return nil
        }
        return "\(Int(min))...\(Int(max))m"
    }
}

private extension RecognitionConfidence {
    var downgraded: RecognitionConfidence {
        switch self {
        case .high:
            return .medium
        case .medium:
            return .low
        case .low:
            return .low
        }
    }
}

private extension String {
    var isRuntimeConfiguredAPIKey: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}

private extension CLLocationCoordinate2D {
    var shortText: String {
        "\(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))"
    }

    func isApproximatelyEqual(to other: CLLocationCoordinate2D?) -> Bool {
        guard let other else {
            return false
        }

        return abs(latitude - other.latitude) < 0.0000001
            && abs(longitude - other.longitude) < 0.0000001
    }

    func distance(to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }

    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let startLatitude = latitude.degreesToRadians
        let startLongitude = longitude.degreesToRadians
        let endLatitude = destination.latitude.degreesToRadians
        let endLongitude = destination.longitude.degreesToRadians
        let longitudeDelta = endLongitude - startLongitude

        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return atan2(y, x).radiansToDegrees.normalizedDegrees
    }
}
