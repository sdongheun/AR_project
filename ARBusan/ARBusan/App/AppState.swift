import CoreLocation
import Foundation

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
    @Published var geospatialStatus = "ARCore Geospatial 세션을 아직 시작하지 않았습니다."
    @Published var cameraHeadingDegrees: Double?
    @Published var cameraHeadingSampleCount = 0
    @Published var cameraHeadingLastUpdatedAt: Date?
    @Published var cameraHeadingDeltaDegrees: Double?
    @Published var cameraHeadingDiagnostics = "카메라 heading 샘플을 아직 받지 못했습니다."
    @Published var cameraDirectionSpotID: TourismSpot.ID?
    @Published var cameraDirectionStatus = "카메라 방향 후보를 아직 계산하지 않았습니다."
    @Published var polygonValidationStatus = "Polygon 자동 후보를 아직 계산하지 않았습니다."
    @Published var polygonLookupStartedAt: Date?
    @Published var polygonLookupFinishedAt: Date?
    @Published var polygonLookupLogs: [String] = []
    @Published var buildingPolygonsBySpotID: [TourismSpot.ID: BuildingPolygon] = [:]
    @Published var tourismDataStatus = "TourAPI는 비활성화되어 있고 김해 목업 건물 후보를 사용 중입니다."

    private let recognitionPipeline: RecognitionPipeline
    private let cameraDirectionCandidateProvider: CameraDirectionCandidateProvider
    private let tourAPIClient: any TourAPIClient
    private let vworldClient: any VWorldClient
    private let nearbySpotRadiusMeters: CLLocationDistance = 1_000
    private var loadedTourismSpots: [TourismSpot] = []
    private var polygonLookupTask: Task<Void, Never>?
    private var polygonLookupInFlightSpotID: TourismSpot.ID?
    private var polygonLookupNotFoundSpotIDs: Set<TourismSpot.ID> = []
    let geospatialSessionManager: GeospatialSessionManager

    init(
        spots: [TourismSpot] = MockTourismSpots.gimhae,
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
                self?.locationConfidence = snapshot.horizontalAccuracy <= 10 ? .high : .medium
                self?.applyNearbySpotFilter()
                self?.updateCameraDirectionCandidate()
            }
        }
        self.geospatialSessionManager.onStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.geospatialStatus = status
            }
        }

        applyMockSpots()
    }

    func loadTourAPISpots() async {
        tourismDataStatus = "TourAPI는 현재 비활성화되어 있습니다. 김해 목업 건물 후보를 유지합니다."
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

        updateCameraDirectionCandidate()
    }

    func runMockRecognition() {
        cameraTextInput = "투썸플레이스"
        locationConfidence = .high
        runRecognition()
    }

    func runRecognition() {
        recognitionResult = recognitionPipeline.recognize(
            candidates: spots,
            cameraText: cameraTextInput,
            locationConfidence: locationConfidence,
            cameraDirectionSpotIDs: Set([cameraDirectionSpotID].compactMap { $0 }),
            polygonValidatedSpotIDs: Set([polygonValidatedSpotID].compactMap { $0 })
        )

        if case let .recognized(spot, _, _) = recognitionResult {
            selectedSpot = spot
        }
    }

    func selectCandidate(_ spot: TourismSpot) {
        selectedSpot = spot
        recognitionResult = .recognized(
            spot: spot,
            confidence: .medium,
            reason: "사용자가 모호한 건물 후보 중 \(spot.name)을 선택했습니다."
        )
    }

    private func updateCameraDirectionCandidate() {
        guard let heading = cameraHeadingDegrees else {
            cameraDirectionSpotID = nil
            polygonValidatedSpotID = nil
            cameraDirectionStatus = "카메라 heading을 아직 받지 못했습니다."
            polygonValidationStatus = "카메라 heading이 없어 Polygon 자동 후보를 계산할 수 없습니다."
            polygonLookupTask?.cancel()
            polygonLookupInFlightSpotID = nil
            return
        }

        guard let latestLocationSnapshot else {
            cameraDirectionSpotID = nil
            polygonValidatedSpotID = nil
            cameraDirectionStatus = "현재 위치가 없어 카메라 방향 후보를 계산할 수 없습니다."
            polygonValidationStatus = "현재 위치가 없어 Polygon 자동 후보를 계산할 수 없습니다."
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
            polygonLookupTask?.cancel()
            polygonLookupInFlightSpotID = nil
            return
        }

        let previousCandidateID = cameraDirectionSpotID
        cameraDirectionSpotID = candidate.spot.id
        cameraDirectionStatus = "\(candidate.spot.name) 방향 후보 / 각도 차이 \(Int(candidate.headingDifferenceDegrees))도 / 거리 \(Int(candidate.distanceMeters))m"
        updateBuildingPolygon(for: candidate.spot)

        if previousCandidateID != candidate.spot.id {
            runRecognition()
        }
    }

    private func updateBuildingPolygon(for spot: TourismSpot) {
        if let polygon = buildingPolygonsBySpotID[spot.id] {
            polygonValidatedSpotID = spot.id
            polygonValidationStatus = "\(spot.name) 브이월드 Polygon 확보 / 외곽 좌표 \(polygon.vertexCount)개"
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
                        self.buildingPolygonsBySpotID[spot.id] = polygon
                        self.polygonLookupNotFoundSpotIDs.remove(spot.id)
                        self.polygonValidatedSpotID = spot.id
                        self.polygonLookupFinishedAt = Date()
                        self.polygonLookupInFlightSpotID = nil
                        self.polygonValidationStatus = "\(spot.name) 브이월드 Polygon 확보 / 외곽 좌표 \(polygon.vertexCount)개"
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
        loadedTourismSpots = MockTourismSpots.gimhae
        clearManualSpatialSelections()
        applyNearbySpotFilter(fallbackReason: reason)
        updateCameraDirectionCandidate()
        runRecognition()
    }

    private func applyMockSpots() {
        loadedTourismSpots = MockTourismSpots.gimhae
        spots = MockTourismSpots.gimhae
        clearManualSpatialSelections()
        tourismDataStatus = "TourAPI 김해/부산 후보는 비활성화되어 있고 김해 목업 건물 \(MockTourismSpots.gimhae.count)개를 사용 중입니다."
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
        cameraDirectionSpotID = nil
        selectedSpot = nil
        polygonLookupTask?.cancel()
    }

    private func applyNearbySpotFilter(fallbackReason: String? = nil) {
        guard let latestLocationSnapshot else {
            spots = []
            if let fallbackReason {
                tourismDataStatus = "TourAPI 대신 김해 목업 후보를 불러왔지만, 현재 위치를 기다리는 중입니다. 사유: \(fallbackReason)"
            } else if loadedTourismSpots.isEmpty {
                tourismDataStatus = "TourAPI 김해 중심 관광지 데이터를 아직 불러오지 않았습니다."
            } else if loadedTourismSpots.isMockFallback {
                tourismDataStatus = "TourAPI 대신 김해 목업 후보를 불러왔고, 현재 위치를 기다리는 중입니다."
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
            tourismDataStatus = "TourAPI 대신 김해 목업 후보를 사용 중입니다. 현재 위치 기준 \(radiusText) 이내 \(filteredSpots.count)/\(loadedTourismSpots.count)개 표시. 사유: \(fallbackReason)"
        } else if loadedTourismSpots.isMockFallback {
            tourismDataStatus = "TourAPI 대신 김해 목업 후보를 사용 중입니다. 현재 위치 기준 \(radiusText) 이내 \(filteredSpots.count)/\(loadedTourismSpots.count)개 표시."
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
}

private extension [TourismSpot] {
    var isMockFallback: Bool {
        !isEmpty && allSatisfy { $0.source == .mock }
    }
}

private extension Double {
    var normalizedDegrees: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    func angularDifference(to other: Double) -> Double {
        let difference = abs(normalizedDegrees - other.normalizedDegrees)
        return min(difference, 360 - difference)
    }
}
