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
    @Published var showsMatrixDebugMarker = true
    @Published var showsOnScreenCandidateDebugMarkers = true
    @Published var shows3DGeospatialDebugMarker = true
    @Published var showsFullDebugLogs = false
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
    @Published var spatialAlignmentDiagnostics = "선택 Polygon과 카메라 heading 정렬을 아직 계산하지 않았습니다."
    @Published var localCoordinateDiagnostics = "local ENU 좌표 변환을 아직 계산하지 않았습니다."
    @Published var polygonProjectionDiagnostics = "선택 Polygon 화면 투영을 아직 계산하지 않았습니다."
    @Published var matrixProjectionComparisonDiagnostics = "projection matrix 비교 좌표를 아직 계산하지 않았습니다."
    @Published var buildingFacadeAnchorDiagnostics = "3D 외벽 후보점을 아직 계산하지 않았습니다."
    @Published var buildingLabelHeightDiagnostics = "3D 라벨 높이 기준값을 아직 계산하지 않았습니다."
    @Published var geospatialTerrainAnchorDiagnostics = "Geospatial Terrain Anchor 후보를 아직 생성하지 않았습니다."
    @Published var cameraDirectionSpotID: TourismSpot.ID?
    @Published var cameraDirectionStatus = "카메라 방향 후보를 아직 계산하지 않았습니다."
    @Published var polygonValidationStatus = "Polygon 자동 후보를 아직 계산하지 않았습니다."
    @Published var polygonLookupStartedAt: Date?
    @Published var polygonLookupFinishedAt: Date?
    @Published var polygonLookupLogs: [String] = []
    @Published var buildingPolygonsBySpotID: [TourismSpot.ID: BuildingPolygon] = [:]
    @Published var resolvedBuildingHeightsBySpotID: [TourismSpot.ID: ResolvedBuildingHeight] = [:]
    @Published var tourismDataStatus = "TourAPI는 비활성화되어 있고 테스트 목업 건물 후보를 사용 중입니다."

    private let recognitionPipeline: RecognitionPipeline
    private let cameraDirectionCandidateProvider: CameraDirectionCandidateProvider
    private let tourAPIClient: any TourAPIClient
    private let vworldClient: any VWorldClient
    private let nearbySpotRadiusMeters: CLLocationDistance = 1_000
    private let headingInstabilityThresholdDegrees: Double = 12
    private let projectionHorizontalFOVDegrees: Double = 60
    private let projectionVerticalFOVDegrees: Double = 45
    private let fovFallbackMaxHeadingDeltaDegrees: Double = 75
    private let maxEdgeMarkerCount = 3
    private let distantMarkerThresholdMeters: CLLocationDistance = 1_000
    private let distantMarkerScale = 0.78
    private let buildingHeightResolver = BuildingHeightResolver()
    private var loadedTourismSpots: [TourismSpot] = []
    private var polygonLookupTask: Task<Void, Never>?
    private var polygonLookupInFlightSpotID: TourismSpot.ID?
    private var polygonLookupNotFoundSpotIDs: Set<TourismSpot.ID> = []
    private var latestSceneSemanticsSnapshot: SceneSemanticsSnapshot?
    private var sceneSemanticsEvidenceBySpotID: [TourismSpot.ID: SceneSemanticsSpotEvidence] = [:]
    private var lastRequestedTerrainAnchorSpotID: TourismSpot.ID?
    private var stableFacadeSelectionsBySpotID: [TourismSpot.ID: StableBuildingFacadeSelection] = [:]
    private let facadeSwitchRayDistanceImprovementMeters: Double = 1.5
    private let facadeSwitchConfirmationInterval: TimeInterval = 0.5
    let geospatialSessionManager: GeospatialSessionManager

    init(
        spots: [TourismSpot] = MockTourismSpots.testBuildings,
        recognitionPipeline: RecognitionPipeline = RecognitionPipeline(),
        cameraDirectionCandidateProvider: CameraDirectionCandidateProvider = CameraDirectionCandidateProvider(),
        apiKeys: APIKeys = APIKeyProvider.load(),
        tourAPIClient: (any TourAPIClient)? = nil,
        vworldClient: (any VWorldClient)? = nil
    ) {
        self.spots = spots
        self.recognitionPipeline = recognitionPipeline
        self.cameraDirectionCandidateProvider = cameraDirectionCandidateProvider
        self.apiKeys = apiKeys
        self.tourAPIClient = tourAPIClient ?? MockTourAPIClient()
        self.vworldClient = vworldClient ?? VWorldDataAPIClient(apiKey: apiKeys.vworld)
        self.loadedTourismSpots = spots
        self.geospatialSessionManager = GeospatialSessionManager(apiKeysProvider: { apiKeys })
        self.cameraTextInput = ""
        self.polygonValidatedSpotID = nil
        self.geospatialSessionManager.onSnapshotUpdated = { [weak self] snapshot in
            Task { @MainActor in
                self?.latestLocationSnapshot = snapshot
                switch snapshot.source {
                case .coreLocation:
                    self?.latestCoreLocationSnapshot = snapshot
                case .arCoreGeospatial:
                    self?.latestGeospatialLocationSnapshot = snapshot
                }
                self?.locationConfidence = Self.locationConfidence(for: snapshot.horizontalAccuracy)
                self?.refreshSpatialTrackingConfidence()
                self?.applyNearbySpotFilter()
                self?.updateCameraDirectionCandidate()
                self?.refreshLocalCoordinateDiagnostics()
                self?.refreshBuildingFacadeAnchorDiagnostics()
                self?.refreshBuildingLabelHeightDiagnostics()
                self?.refreshMatrixProjectionComparisonDiagnostics()
                self?.refreshEdgeMarkerOverlays()
                self?.refreshOnScreenCandidateMarkerOverlays()
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
                self?.geospatialTerrainAnchorDiagnostics = status
            }
        }

        applyMockSpots()
    }

    func loadTourAPISpots() async {
        tourismDataStatus = "TourAPI는 현재 비활성화되어 있습니다. 테스트 목업 건물 후보를 유지합니다."
        applyMockSpots()
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

    func updateCameraTextFromLiveOCR(_ text: String) {
        cameraTextInput = text
        runRecognition()
    }

    func updateCameraHeading(_ headingDegrees: Double) {
        let previousHeading = cameraHeadingDegrees
        cameraHeadingDegrees = headingDegrees
        cameraHeadingSampleCount += 1
        cameraHeadingLastUpdatedAt = Date()

        if let previousHeading {
            cameraHeadingDeltaDegrees = previousHeading.angularDifference(to: headingDegrees)
            cameraHeadingDiagnostics = "실시간 heading 수신 중 / 샘플 \(cameraHeadingSampleCount)개 / 변화량 \(Int(cameraHeadingDeltaDegrees ?? 0))도"
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
    }

    func runMockRecognition() {
        cameraTextInput = "투썸플레이스"
        locationConfidence = .high
        refreshSpatialTrackingConfidence()
        runRecognition()
    }

    func runRecognition() {
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
    }

    private func updateCameraDirectionCandidate() {
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
        polygonLookupNotFoundSpotIDs = []
        resolvedBuildingHeightsBySpotID = [:]
        sceneSemanticsEvidenceBySpotID = [:]
        sceneSemanticsScoringDiagnostics = "후보 초기화로 Scene Semantics 라벨 보정도 초기화했습니다."
        lastRequestedTerrainAnchorSpotID = nil
        stableFacadeSelectionsBySpotID = [:]
        arLabelOverlay = nil
        arLabelOverlayDiagnostics = "후보 초기화로 AR 라벨도 초기화했습니다."
        matrixProjectionDebugOverlay = nil
        edgeMarkerOverlays = []
        onScreenCandidateMarkerOverlays = []
        localCoordinateDiagnostics = "후보 초기화로 local ENU 좌표 변환도 초기화했습니다."
        buildingFacadeAnchorDiagnostics = "후보 초기화로 3D 외벽 후보점도 초기화했습니다."
        buildingLabelHeightDiagnostics = "후보 초기화로 3D 라벨 높이 기준값도 초기화했습니다."
        geospatialTerrainAnchorDiagnostics = "후보 초기화로 Geospatial Terrain Anchor 후보도 초기화했습니다."
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
        edgeMarkerOverlays.removeAll { !visibleSpotIDs.contains($0.id) }
        onScreenCandidateMarkerOverlays.removeAll { !visibleSpotIDs.contains($0.id) }
    }

    private func refreshEdgeMarkerOverlays() {
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
        if polygonLookupLogs.count > 40 {
            polygonLookupLogs = Array(polygonLookupLogs.suffix(40))
        }
    }

    private func refreshSpatialTrackingConfidence() {
        let headingIsStable = (cameraHeadingDeltaDegrees ?? 0) <= headingInstabilityThresholdDegrees
        effectiveSpatialConfidence = headingIsStable ? locationConfidence : locationConfidence.downgraded

        let headingText = headingIsStable
            ? "heading 안정"
            : "heading 불안정: 변화량 \(Int(cameraHeadingDeltaDegrees ?? 0))도"
        spatialTrackingDiagnostics = "공간 신뢰도 \(effectiveSpatialConfidence.displayName) / 위치 \(locationConfidence.displayName) / \(headingText)"
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

        guard let spot = localCoordinateTargetSpot(from: latestLocationSnapshot) else {
            buildingLabelHeightDiagnostics = "3D 라벨 높이를 계산할 POI 후보가 없습니다."
            return
        }

        guard let polygon = buildingPolygonsBySpotID[spot.id] else {
            buildingLabelHeightDiagnostics = "\(spot.name) Polygon이 아직 없어 3D 라벨 높이 기준값을 계산할 수 없습니다."
            return
        }

        let resolvedHeight = resolvedBuildingHeightsBySpotID[spot.id] ?? buildingHeightResolver.resolve(polygon: polygon)
        resolvedBuildingHeightsBySpotID[spot.id] = resolvedHeight

        let facadeDistanceMeters = cameraFacingFacadeCandidate(
            spot: spot,
            polygon: polygon,
            from: latestLocationSnapshot,
            headingDegrees: cameraHeadingDegrees
        )?.distanceFromUserMeters
        let distanceMeters = facadeDistanceMeters
            ?? latestLocationSnapshot.coordinate.distance(to: spot.center)
        let distanceSource = facadeDistanceMeters == nil ? "POI 중심 거리" : "가장 가까운 외벽 거리"
        let labelHeight = labelHeightDecision(
            for: resolvedHeight,
            distanceMeters: distanceMeters
        )
        let sourcePropertiesText = sourceHeightPropertiesText(for: polygon)
        buildingLabelHeightDiagnostics = "\(spot.name) 3D 라벨 높이 기준 / \(distanceSource) \(Int(distanceMeters))m / \(labelHeight.rangeLabel) / 건물 높이 \(resolvedHeight.displayText) / 라벨 후보 높이 \(String(format: "%.1f", labelHeight.valueMeters))m / \(labelHeight.reason) / \(resolvedHeight.explanation)\(sourcePropertiesText)"
        requestGeospatialTerrainAnchorIfPossible(
            spot: spot,
            polygon: polygon,
            labelHeightMeters: labelHeight.valueMeters,
            origin: latestLocationSnapshot
        )
    }

    private func requestGeospatialTerrainAnchorIfPossible(
        spot: TourismSpot,
        polygon: BuildingPolygon,
        labelHeightMeters: Double,
        origin: LocationSnapshot
    ) {
        guard let facadeCandidate = cameraFacingFacadeCandidate(
            spot: spot,
            polygon: polygon,
            from: origin,
            headingDegrees: cameraHeadingDegrees
        ) else {
            geospatialTerrainAnchorDiagnostics = "\(spot.name) Terrain Anchor 대기: 외벽 후보점이 없습니다."
            return
        }

        if lastRequestedTerrainAnchorSpotID == spot.id {
            return
        }
        lastRequestedTerrainAnchorSpotID = spot.id

        let candidates = terrainAnchorCandidates(
            from: facadeCandidate,
            labelHeightMeters: labelHeightMeters,
            origin: origin
        )
        let wgs84Fallback = wgs84AnchorFallbackCandidate(
            from: facadeCandidate,
            labelHeightMeters: labelHeightMeters,
            origin: origin
        )
        let candidateSummary = candidates
            .map { "\($0.label) \($0.coordinate.shortText)" }
            .joined(separator: " / ")
        let fallbackSummary = wgs84Fallback.map {
            " / WGS84 fallback \($0.coordinate.shortText), 절대고도 \(String(format: "%.1f", $0.altitude))m"
        } ?? ""

        geospatialTerrainAnchorDiagnostics = "\(spot.name) Terrain Anchor 순차 테스트 후보 / \(candidateSummary)\(fallbackSummary) / ARCore Earth tracking 대기 또는 요청 중"
        geospatialSessionManager.createTerrainAnchorIfPossible(
            for: GeospatialTerrainAnchorRequest(
                spotID: spot.id,
                spotName: spot.name,
                candidates: candidates,
                wgs84Fallback: wgs84Fallback
            )
        )
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
        from facadeCandidate: BuildingFacadeCandidate,
        labelHeightMeters: Double,
        origin: LocationSnapshot
    ) -> GeospatialWGS84AnchorCandidate? {
        let deviceHeightAssumptionMeters = 1.5
        let relativeLabelHeightFromCameraGround = labelHeightMeters - deviceHeightAssumptionMeters

        if let geospatialAltitude = latestGeospatialLocationSnapshot?.altitude {
            return GeospatialWGS84AnchorCandidate(
                label: "외벽 중점 WGS84 fallback",
                coordinate: facadeCandidate.anchorCoordinate,
                altitude: geospatialAltitude + relativeLabelHeightFromCameraGround,
                altitudeSource: "ARCore Geospatial altitude \(String(format: "%.1f", geospatialAltitude))m + 라벨높이 \(String(format: "%.1f", labelHeightMeters))m - 기기높이 \(String(format: "%.1f", deviceHeightAssumptionMeters))m"
            )
        }

        guard let coreLocationAltitude = origin.altitude else {
            return nil
        }

        return GeospatialWGS84AnchorCandidate(
            label: "외벽 중점 WGS84 fallback",
            coordinate: facadeCandidate.anchorCoordinate,
            altitude: coreLocationAltitude + relativeLabelHeightFromCameraGround,
            altitudeSource: "CoreLocation altitude \(String(format: "%.1f", coreLocationAltitude))m + 라벨높이 \(String(format: "%.1f", labelHeightMeters))m - 기기높이 \(String(format: "%.1f", deviceHeightAssumptionMeters))m"
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
            baseHeight = 3.0 + progress * 2.0
            rangeLabel = "중거리 5~30m"
        default:
            baseHeight = 5.0
            rangeLabel = "원거리 30m 이상"
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
