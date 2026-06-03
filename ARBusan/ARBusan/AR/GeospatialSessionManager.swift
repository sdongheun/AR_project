import ARKit
import CoreLocation
import Foundation
import simd
@_implementationOnly import ARCore
@_implementationOnly import ARCoreGARSession
@_implementationOnly import ARCoreGeospatial
@_implementationOnly import ARCoreSemantics

struct GeospatialTerrainAnchorRequest {
    let spotID: TourismSpot.ID
    let spotName: String
    let candidates: [GeospatialTerrainAnchorCandidate]
    let wgs84Fallback: GeospatialWGS84AnchorCandidate?
}

struct GeospatialTerrainAnchorCandidate {
    let label: String
    let coordinate: CLLocationCoordinate2D
    let altitudeAboveTerrain: CLLocationDistance
}

struct GeospatialWGS84AnchorCandidate {
    let label: String
    let coordinate: CLLocationCoordinate2D
    let altitude: CLLocationDistance
    let altitudeSource: String
}

struct GeospatialDebugAnchorSnapshot {
    let id: UUID
    let label: String
    let kind: String
    let transform: simd_float4x4
    let trackingState: String
}

final class GeospatialSessionManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let apiKeysProvider: () -> APIKeys
    private var garSession: GARSession?
    private var terrainAnchor: GARAnchor?
    private var wgs84Anchor: GARAnchor?
    private var terrainAnchorKey: String?
    private var terrainAnchorFuture: GARCreateAnchorOnTerrainFuture?
    private var terrainAnchorRequest: GeospatialTerrainAnchorRequest?
    private var terrainAnchorCandidateIndex = 0
    private var activeDebugAnchorID: UUID?
    private var activeDebugAnchorLabel: String?
    private var activeDebugAnchorKind: String?
    private var latestTerrainAnchorStatusMessage = "WGS84 Anchor 후보를 아직 생성하지 않았습니다."
    private var latestEarthIsTracking = false
    private var isConfigured = false
    private var isSceneSemanticsEnabled = false
    private let shouldEnableSceneSemantics = false
    private var lastSceneSemanticsTimestamp: TimeInterval = 0
    private let sceneSemanticsInterval: TimeInterval = 0.25

    private(set) var latestSnapshot: LocationSnapshot?
    private(set) var latestStatusMessage = "ARCore Geospatial 세션을 아직 시작하지 않았습니다."

    var onSnapshotUpdated: ((LocationSnapshot) -> Void)?
    var onStatusChanged: ((String) -> Void)?
    var onSceneSemanticsUpdated: ((SceneSemanticsSnapshot) -> Void)?
    var onSceneSemanticsStatusChanged: ((String) -> Void)?
    var onTerrainAnchorStatusChanged: ((String) -> Void)?
    var onDebugAnchorUpdated: ((GeospatialDebugAnchorSnapshot?) -> Void)?

    init(apiKeysProvider: @escaping () -> APIKeys = { APIKeyProvider.load() }) {
        self.apiKeysProvider = apiKeysProvider
        super.init()
        locationManager.delegate = self
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startLocationUpdates() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }

    func configureIfPossible() {
        guard !isConfigured else {
            return
        }

        let apiKey = apiKeysProvider().googleARCore
        guard apiKey.isConfiguredForRuntime else {
            updateStatus("GOOGLE_ARCORE_API_KEY가 비어 있어 VPS 세션을 시작하지 않았습니다.")
            return
        }

        let session: GARSession
        do {
            session = try GARSession(apiKey: apiKey, bundleIdentifier: Bundle.main.bundleIdentifier)
        } catch {
            updateStatus("GARSession 생성 실패: \(error.localizedDescription)")
            return
        }

        let configuration = GARSessionConfiguration()
        configuration.geospatialMode = .enabled
        configuration.streetscapeGeometryMode = .disabled
        if shouldEnableSceneSemantics, session.isSemanticModeSupported(.enabled) {
            configuration.semanticMode = .enabled
            isSceneSemanticsEnabled = true
        } else {
            isSceneSemanticsEnabled = false
            updateSceneSemanticsStatus("Scene Semantics는 발열 절감을 위해 비활성화했습니다.")
        }

        var configurationError: NSError?
        session.setConfiguration(configuration, error: &configurationError)

        if let configurationError {
            updateStatus("Geospatial 설정 실패: \(configurationError.localizedDescription)")
            return
        }

        garSession = session
        isConfigured = true
        updateStatus("ARCore Geospatial 세션이 구성되었습니다.")
        if isSceneSemanticsEnabled {
            updateSceneSemanticsStatus("Scene Semantics 활성화됨. semantic image 수신 대기 중입니다.")
        }
    }

    func update(with frame: ARFrame) {
        configureIfPossible()

        guard let garSession else {
            return
        }

        let garFrame: GARFrame
        do {
            garFrame = try garSession.update(frame)
        } catch {
            updateStatus("GARFrame 업데이트 실패: \(error.localizedDescription)")
            return
        }

        publishSceneSemanticsIfNeeded(from: garFrame)
        publishDebugAnchorIfNeeded(from: garFrame)

        guard let earth = garFrame.earth else {
            latestEarthIsTracking = false
            return
        }

        latestEarthIsTracking = earth.trackingState == GARTrackingState.tracking
        guard latestEarthIsTracking,
              let transform = earth.cameraGeospatialTransform else {
            return
        }

        let snapshot = LocationSnapshot(
            latitude: transform.coordinate.latitude,
            longitude: transform.coordinate.longitude,
            altitude: transform.altitude,
            horizontalAccuracy: transform.horizontalAccuracy,
            verticalAccuracy: transform.verticalAccuracy,
            heading: nil,
            headingAccuracy: transform.orientationYawAccuracy,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        publish(snapshot)
        updateStatus("VPS 위치 추정 중: 정확도 약 \(Int(transform.horizontalAccuracy))m")
    }

    func createTerrainAnchorIfPossible(for request: GeospatialTerrainAnchorRequest) {
        configureIfPossible()

        guard let wgs84Candidate = request.wgs84Fallback else {
            updateTerrainAnchorStatus("\(request.spotName) WGS84 Anchor 대기: 절대고도 기준값이 아직 없습니다.")
            return
        }

        guard let garSession else {
            updateTerrainAnchorStatus("\(request.spotName) WGS84 Anchor 대기: ARCore Geospatial 세션이 아직 없습니다.")
            return
        }

        guard latestEarthIsTracking else {
            updateTerrainAnchorStatus("\(request.spotName) WGS84 Anchor 대기: Earth tracking이 아직 tracking 상태가 아닙니다.")
            return
        }

        let nextKey = terrainAnchorKey(for: request)
        if terrainAnchorKey == nextKey {
            if let activeAnchor = wgs84Anchor ?? terrainAnchor {
                updateTerrainAnchorStatus("\(latestTerrainAnchorStatusMessage) / anchor tracking \(activeAnchor.trackingState.displayText)")
            } else {
                updateTerrainAnchorStatus(latestTerrainAnchorStatusMessage)
            }
            return
        }

        removeCurrentGeospatialAnchors(from: garSession)
        terrainAnchor = nil
        wgs84Anchor = nil
        terrainAnchorKey = nextKey
        terrainAnchorRequest = request
        terrainAnchorCandidateIndex = 0
        terrainAnchorFuture?.cancel()
        terrainAnchorFuture = nil

        createWGS84Anchor(wgs84Candidate, spotName: request.spotName)
    }

    private func requestTerrainAnchorCandidate(_ index: Int, for request: GeospatialTerrainAnchorRequest) {
        guard let garSession,
              request.candidates.indices.contains(index) else {
            return
        }

        let candidate = request.candidates[index]

        do {
            let future = try garSession.createAnchorOnTerrain(
                coordinate: candidate.coordinate,
                altitudeAboveTerrain: candidate.altitudeAboveTerrain,
                eastUpSouthQAnchor: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            ) { [weak self] anchor, terrainState in
                DispatchQueue.main.async {
                    self?.terrainAnchorFuture = nil
                    if let anchor {
                        self?.terrainAnchor = anchor
                        self?.setActiveDebugAnchor(anchor, label: request.spotName, kind: "Terrain")
                        self?.updateTerrainAnchorStatus("\(request.spotName) Terrain Anchor 생성 완료 / 후보 \(index + 1)/\(request.candidates.count) \(candidate.label) / terrain \(terrainState.displayText) / tracking \(anchor.trackingState.displayText) / 좌표 \(candidate.coordinate.shortText) / 높이 \(String(format: "%.1f", candidate.altitudeAboveTerrain))m")
                    } else {
                        self?.terrainAnchor = nil
                        let failureMessage = "\(request.spotName) Terrain Anchor 생성 실패 / 후보 \(index + 1)/\(request.candidates.count) \(candidate.label) / terrain \(terrainState.displayText) / 좌표 \(candidate.coordinate.shortText) / 높이 \(String(format: "%.1f", candidate.altitudeAboveTerrain))m"
                        if let self,
                           terrainState.shouldTryNextTerrainCandidate,
                           request.candidates.indices.contains(index + 1) {
                            self.updateTerrainAnchorStatus("\(failureMessage) / 다음 후보 테스트 중")
                            self.terrainAnchorCandidateIndex = index + 1
                            self.requestTerrainAnchorCandidate(index + 1, for: request)
                        } else if let self,
                                  let fallback = request.wgs84Fallback,
                                  terrainState == GARTerrainAnchorState.errorUnsupportedLocation {
                            self.updateTerrainAnchorStatus("\(failureMessage) / WGS84 fallback 생성 시도")
                            self.createWGS84Anchor(fallback, spotName: request.spotName)
                        } else {
                            self?.updateTerrainAnchorStatus(failureMessage)
                        }
                    }
                }
            }
            terrainAnchorFuture = future
            updateTerrainAnchorStatus("\(request.spotName) Terrain Anchor 생성 요청 / 후보 \(index + 1)/\(request.candidates.count) \(candidate.label) / 좌표 \(candidate.coordinate.shortText) / 지면 위 높이 \(String(format: "%.1f", candidate.altitudeAboveTerrain))m")
        } catch {
            terrainAnchorKey = nil
            terrainAnchorRequest = nil
            updateTerrainAnchorStatus("\(request.spotName) Terrain Anchor 요청 실패: \(error.localizedDescription)")
        }
    }

    private func createWGS84Anchor(_ candidate: GeospatialWGS84AnchorCandidate, spotName: String) {
        guard let garSession else {
            updateTerrainAnchorStatus("\(spotName) WGS84 Anchor 대기: ARCore Geospatial 세션이 아직 없습니다.")
            return
        }

        do {
            updateTerrainAnchorStatus("\(spotName) WGS84 Anchor 생성 요청 / \(candidate.label) / 좌표 \(candidate.coordinate.shortText) / 절대고도 \(String(format: "%.1f", candidate.altitude))m / 기준 \(candidate.altitudeSource) / Terrain Anchor는 현재 보류")
            let anchor = try garSession.createAnchor(
                coordinate: candidate.coordinate,
                altitude: candidate.altitude,
                eastUpSouthQAnchor: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            )
            wgs84Anchor = anchor
            setActiveDebugAnchor(anchor, label: spotName, kind: "WGS84")
            updateTerrainAnchorStatus("\(spotName) WGS84 Anchor 생성 완료 / \(candidate.label) / tracking \(anchor.trackingState.displayText) / 좌표 \(candidate.coordinate.shortText) / 절대고도 \(String(format: "%.1f", candidate.altitude))m / 기준 \(candidate.altitudeSource)")
        } catch {
            wgs84Anchor = nil
            updateTerrainAnchorStatus("\(spotName) WGS84 Anchor 생성 실패 / \(candidate.label) / 좌표 \(candidate.coordinate.shortText) / 절대고도 \(String(format: "%.1f", candidate.altitude))m / \(error.localizedDescription)")
        }
    }

    private func removeCurrentGeospatialAnchors(from garSession: GARSession) {
        if let terrainAnchor {
            garSession.remove(terrainAnchor)
        }
        if let wgs84Anchor {
            garSession.remove(wgs84Anchor)
        }
        activeDebugAnchorID = nil
        activeDebugAnchorLabel = nil
        activeDebugAnchorKind = nil
        onDebugAnchorUpdated?(nil)
    }

    private func setActiveDebugAnchor(_ anchor: GARAnchor, label: String, kind: String) {
        activeDebugAnchorID = anchor.identifier
        activeDebugAnchorLabel = label
        activeDebugAnchorKind = kind
        publishDebugAnchor(anchor)
    }

    private func publishDebugAnchorIfNeeded(from frame: GARFrame) {
        guard let activeDebugAnchorID else {
            return
        }

        guard let anchor = frame.anchors.first(where: { $0.identifier == activeDebugAnchorID }) else {
            return
        }
        publishDebugAnchor(anchor)
    }

    private func publishDebugAnchor(_ anchor: GARAnchor) {
        guard anchor.hasValidTransform else {
            DispatchQueue.main.async { [onDebugAnchorUpdated] in
                onDebugAnchorUpdated?(nil)
            }
            return
        }

        let snapshot = GeospatialDebugAnchorSnapshot(
            id: anchor.identifier,
            label: activeDebugAnchorLabel ?? "Geospatial Debug Anchor",
            kind: activeDebugAnchorKind ?? "Geospatial",
            transform: anchor.transform,
            trackingState: anchor.trackingState.displayText
        )
        DispatchQueue.main.async { [onDebugAnchorUpdated] in
            onDebugAnchorUpdated?(snapshot)
        }
    }

    private func publishSceneSemanticsIfNeeded(from garFrame: GARFrame) {
        guard isSceneSemanticsEnabled else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSceneSemanticsTimestamp >= sceneSemanticsInterval else {
            return
        }
        lastSceneSemanticsTimestamp = now

        guard let semanticImage = garFrame.semanticImage else {
            updateSceneSemanticsStatus("Scene Semantics semantic image 수신 대기 중입니다.")
            return
        }

        guard let snapshot = SceneSemanticsOverlayRenderer.render(from: semanticImage) else {
            updateSceneSemanticsStatus("Scene Semantics overlay 생성 실패")
            return
        }

        DispatchQueue.main.async { [onSceneSemanticsUpdated, onSceneSemanticsStatusChanged] in
            onSceneSemanticsUpdated?(snapshot)
            onSceneSemanticsStatusChanged?(snapshot.diagnosticText)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        let snapshot = LocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            heading: location.course >= 0 ? location.course : nil,
            headingAccuracy: location.courseAccuracy >= 0 ? location.courseAccuracy : nil,
            source: .coreLocation,
            capturedAt: location.timestamp
        )
        publish(snapshot)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startLocationUpdates()
            configureIfPossible()
        }
    }

    private func publish(_ snapshot: LocationSnapshot) {
        latestSnapshot = snapshot
        DispatchQueue.main.async { [onSnapshotUpdated] in
            onSnapshotUpdated?(snapshot)
        }
    }

    private func updateStatus(_ message: String) {
        latestStatusMessage = message
        DispatchQueue.main.async { [onStatusChanged] in
            onStatusChanged?(message)
        }
    }

    private func updateSceneSemanticsStatus(_ message: String) {
        DispatchQueue.main.async { [onSceneSemanticsStatusChanged] in
            onSceneSemanticsStatusChanged?(message)
        }
    }

    private func updateTerrainAnchorStatus(_ message: String) {
        latestTerrainAnchorStatusMessage = message
        DispatchQueue.main.async { [onTerrainAnchorStatusChanged] in
            onTerrainAnchorStatusChanged?(message)
        }
    }

    private func terrainAnchorKey(for request: GeospatialTerrainAnchorRequest) -> String {
        let candidateKey = request.candidates
            .map { candidate -> String in
                let latitude = (candidate.coordinate.latitude * 1_000_000).rounded()
                let longitude = (candidate.coordinate.longitude * 1_000_000).rounded()
                let height = (candidate.altitudeAboveTerrain * 10).rounded()
                return "\(latitude)-\(longitude)-\(height)"
            }
            .joined(separator: "|")
        let fallbackKey: String
        if let fallback = request.wgs84Fallback {
            let latitude = (fallback.coordinate.latitude * 1_000_000).rounded()
            let longitude = (fallback.coordinate.longitude * 1_000_000).rounded()
            let altitude = (fallback.altitude * 10).rounded()
            fallbackKey = "\(latitude)-\(longitude)-\(altitude)"
        } else {
            fallbackKey = "none"
        }
        return "\(request.spotID)-\(candidateKey)-wgs84-\(fallbackKey)"
    }
}

private extension GARTrackingState {
    var displayText: String {
        switch self {
        case GARTrackingState.tracking:
            return "tracking"
        case GARTrackingState.paused:
            return "paused"
        case GARTrackingState.stopped:
            return "stopped"
        @unknown default:
            return "unknown"
        }
    }
}

private extension GARTerrainAnchorState {
    var displayText: String {
        switch self {
        case GARTerrainAnchorState.success:
            return "success"
        case GARTerrainAnchorState.taskInProgress:
            return "taskInProgress"
        case GARTerrainAnchorState.errorInternal:
            return "errorInternal"
        case GARTerrainAnchorState.errorNotAuthorized:
            return "errorNotAuthorized"
        case GARTerrainAnchorState.errorUnsupportedLocation:
            return "errorUnsupportedLocation"
        case GARTerrainAnchorState.none:
            return "none"
        @unknown default:
            return "unknown"
        }
    }

    var shouldTryNextTerrainCandidate: Bool {
        switch self {
        case GARTerrainAnchorState.errorUnsupportedLocation,
            GARTerrainAnchorState.errorInternal,
            GARTerrainAnchorState.none:
            return true
        case GARTerrainAnchorState.success,
            GARTerrainAnchorState.taskInProgress,
            GARTerrainAnchorState.errorNotAuthorized:
            return false
        @unknown default:
            return false
        }
    }
}

private extension CLLocationCoordinate2D {
    var shortText: String {
        "\(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))"
    }
}

private extension String {
    var isConfiguredForRuntime: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}
