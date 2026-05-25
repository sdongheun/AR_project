import ARKit
import RealityKit
import UIKit

final class ARSessionViewController: UIViewController {
    private var arView: ARView!
    private let geospatialSessionManager: GeospatialSessionManager
    private let ocrRecognizer = OCRRecognizer()
    private var lastOCRTimestamp: TimeInterval = 0
    private var isRecognizingText = false
    private let ocrInterval: TimeInterval = 2.0
    private var lastHeadingTimestamp: TimeInterval = 0
    private let headingInterval: TimeInterval = 0.25
    private var lastProjectionTimestamp: TimeInterval = 0
    private let projectionInterval: TimeInterval = 0.5

    var onRecognizedCameraText: ((String) -> Void)?
    var onCameraHeadingUpdated: ((Double) -> Void)?
    var onCameraPoseUpdated: ((CameraPoseSnapshot) -> Void)?
    var onCameraProjectionUpdated: ((CameraProjectionSnapshot) -> Void)?

    init(geospatialSessionManager: GeospatialSessionManager) {
        self.geospatialSessionManager = geospatialSessionManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        arView = ARView(frame: .zero)
        arView.session.delegate = self
        view = arView
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        geospatialSessionManager.requestLocationPermission()
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }

    private func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        arView.session.run(configuration)
    }
}

extension ARSessionViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        geospatialSessionManager.update(with: frame)
        publishCameraHeadingIfNeeded(from: frame)
        publishCameraProjectionIfNeeded(from: frame)
        recognizeTextIfNeeded(in: frame)
    }

    private func publishCameraHeadingIfNeeded(from frame: ARFrame) {
        guard frame.timestamp - lastHeadingTimestamp >= headingInterval else {
            return
        }

        lastHeadingTimestamp = frame.timestamp
        let pose = CameraHeadingCalculator.poseSnapshot(
            from: frame.camera.transform,
            eulerAngles: frame.camera.eulerAngles,
            timestamp: frame.timestamp
        )

        DispatchQueue.main.async { [weak self] in
            self?.onCameraPoseUpdated?(pose)
            self?.onCameraHeadingUpdated?(pose.headingDegrees)
        }
    }

    private func publishCameraProjectionIfNeeded(from frame: ARFrame) {
        guard frame.timestamp - lastProjectionTimestamp >= projectionInterval else {
            return
        }

        let viewportSize = arView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        lastProjectionTimestamp = frame.timestamp
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        let viewMatrix = frame.camera.viewMatrix(for: orientation)
        let projectionMatrix = frame.camera.projectionMatrix(
            for: orientation,
            viewportSize: viewportSize,
            zNear: 0.001,
            zFar: 1_000
        )
        let snapshot = CameraProjectionSnapshot.make(
            timestamp: frame.timestamp,
            cameraTransform: frame.camera.transform,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            viewportSize: viewportSize,
            interfaceOrientation: orientation,
            trackingStateDescription: trackingStateDescription(frame.camera.trackingState)
        )

        DispatchQueue.main.async { [weak self] in
            self?.onCameraProjectionUpdated?(snapshot)
        }
    }

    private func trackingStateDescription(_ trackingState: ARCamera.TrackingState) -> String {
        switch trackingState {
        case .normal:
            return "normal"
        case .notAvailable:
            return "notAvailable"
        case let .limited(reason):
            return "limited(\(limitedTrackingReasonDescription(reason)))"
        }
    }

    private func limitedTrackingReasonDescription(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing:
            return "initializing"
        case .excessiveMotion:
            return "excessiveMotion"
        case .insufficientFeatures:
            return "insufficientFeatures"
        case .relocalizing:
            return "relocalizing"
        @unknown default:
            return "unknown"
        }
    }

    private func recognizeTextIfNeeded(in frame: ARFrame) {
        guard !isRecognizingText else {
            return
        }

        guard frame.timestamp - lastOCRTimestamp >= ocrInterval else {
            return
        }

        lastOCRTimestamp = frame.timestamp
        isRecognizingText = true
        let pixelBuffer = frame.capturedImage

        Task { [weak self, ocrRecognizer] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isRecognizingText = false
                }
            }

            let strings = (try? await ocrRecognizer.recognizeText(in: pixelBuffer)) ?? []
            let recognizedText = strings.joined(separator: " ")

            guard !recognizedText.isEmpty else {
                return
            }

            await MainActor.run {
                self?.onRecognizedCameraText?(recognizedText)
            }
        }
    }
}
