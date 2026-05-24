import ARKit
import CoreLocation
import Foundation
@_implementationOnly import ARCore
@_implementationOnly import ARCoreGARSession
@_implementationOnly import ARCoreGeospatial

final class GeospatialSessionManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let apiKeysProvider: () -> APIKeys
    private var garSession: GARSession?
    private var isConfigured = false

    private(set) var latestSnapshot: LocationSnapshot?
    private(set) var latestStatusMessage = "ARCore Geospatial 세션을 아직 시작하지 않았습니다."

    var onSnapshotUpdated: ((LocationSnapshot) -> Void)?
    var onStatusChanged: ((String) -> Void)?

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

        var configurationError: NSError?
        session.setConfiguration(configuration, error: &configurationError)

        if let configurationError {
            updateStatus("Geospatial 설정 실패: \(configurationError.localizedDescription)")
            return
        }

        garSession = session
        isConfigured = true
        updateStatus("ARCore Geospatial 세션이 구성되었습니다.")
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
}

private extension String {
    var isConfiguredForRuntime: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}
