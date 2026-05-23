import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var spots: [TourismSpot]
    @Published var recognitionResult: RecognitionResult = .none(reason: "아직 인식을 시작하지 않았습니다.")
    @Published var selectedSpot: TourismSpot?
    @Published var cameraTextInput = ""
    @Published var locationConfidence: RecognitionConfidence = .high
    @Published var vpsNearbySpotID: TourismSpot.ID?
    @Published var polygonValidatedSpotID: TourismSpot.ID?
    @Published var apiKeys: APIKeys
    @Published var latestLocationSnapshot: LocationSnapshot?
    @Published var geospatialStatus = "ARCore Geospatial 세션을 아직 시작하지 않았습니다."

    private let recognitionPipeline: RecognitionPipeline
    let geospatialSessionManager: GeospatialSessionManager

    init(
        spots: [TourismSpot] = MockTourismSpots.gimhae,
        recognitionPipeline: RecognitionPipeline = RecognitionPipeline(),
        apiKeys: APIKeys = APIKeyProvider.load()
    ) {
        self.spots = spots
        self.recognitionPipeline = recognitionPipeline
        self.apiKeys = apiKeys
        self.geospatialSessionManager = GeospatialSessionManager(apiKeysProvider: { apiKeys })
        self.cameraTextInput = spots.first?.name ?? ""
        self.vpsNearbySpotID = spots.first?.id
        self.polygonValidatedSpotID = spots.first?.id
        self.geospatialSessionManager.onSnapshotUpdated = { [weak self] snapshot in
            Task { @MainActor in
                self?.latestLocationSnapshot = snapshot
                self?.locationConfidence = snapshot.horizontalAccuracy <= 10 ? .high : .medium
            }
        }
        self.geospatialSessionManager.onStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.geospatialStatus = status
            }
        }
    }

    func updateCameraTextFromLiveOCR(_ text: String) {
        cameraTextInput = text
        runRecognition()
    }

    func runMockRecognition() {
        cameraTextInput = "투썸플레이스"
        locationConfidence = .high
        vpsNearbySpotID = "mock-gimhae-twosome-inje-192"
        polygonValidatedSpotID = "mock-gimhae-twosome-inje-192"
        runRecognition()
    }

    func runRecognition() {
        recognitionResult = recognitionPipeline.recognize(
            candidates: spots,
            cameraText: cameraTextInput,
            locationConfidence: locationConfidence,
            vpsNearbySpotIDs: Set([vpsNearbySpotID].compactMap { $0 }),
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
}
