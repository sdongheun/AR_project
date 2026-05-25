import ARKit
import CoreLocation
import Foundation
@_implementationOnly import ARCore
@_implementationOnly import ARCoreGARSession
@_implementationOnly import ARCoreGeospatial
@_implementationOnly import ARCoreSemantics

final class GeospatialSessionManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let apiKeysProvider: () -> APIKeys
    private var garSession: GARSession?
    private var isConfigured = false
    private var isSceneSemanticsEnabled = false
    private var lastSceneSemanticsTimestamp: TimeInterval = 0
    private let sceneSemanticsInterval: TimeInterval = 0.25

    private(set) var latestSnapshot: LocationSnapshot?
    private(set) var latestStatusMessage = "ARCore Geospatial 세션을 아직 시작하지 않았습니다."

    var onSnapshotUpdated: ((LocationSnapshot) -> Void)?
    var onStatusChanged: ((String) -> Void)?
    var onSceneSemanticsUpdated: ((SceneSemanticsSnapshot) -> Void)?
    var onSceneSemanticsStatusChanged: ((String) -> Void)?

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
        if session.isSemanticModeSupported(.enabled) {
            configuration.semanticMode = .enabled
            isSceneSemanticsEnabled = true
        } else {
            isSceneSemanticsEnabled = false
            updateSceneSemanticsStatus("Scene Semantics 미지원 기기입니다.")
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

        guard
            let earth = garFrame.earth,
            earth.trackingState == GARTrackingState.tracking,
            let transform = earth.cameraGeospatialTransform
        else {
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
}

private extension String {
    var isConfiguredForRuntime: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}
