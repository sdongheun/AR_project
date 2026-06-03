import ARKit
import RealityKit
import UIKit

final class ARSessionViewController: UIViewController {
    private var arView: ARView!
    private let geospatialSessionManager: GeospatialSessionManager
    private var geospatialDebugAnchorEntity: AnchorEntity?
    private var geospatialDebugMarkerEntity: ModelEntity?
    private var geospatialDebugLabelEntity: Entity?
    private var currentGeospatialDebugAnchorID: UUID?
    private var isGeospatialDebugMarkerSelected = false
    private var shows3DGeospatialDebugMarker = true
    private let ocrRecognizer = OCRRecognizer()
    private var lastOCRTimestamp: TimeInterval = 0
    private var isRecognizingText = false
    private let shouldRunLiveOCR = false
    private let ocrInterval: TimeInterval = 3.5
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
        geospatialSessionManager.onDebugAnchorUpdated = { [weak self] snapshot in
            self?.updateGeospatialDebugAnchor(snapshot)
        }
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleARViewTap(_:)))
        arView.addGestureRecognizer(tapGesture)
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

        arView.session.run(configuration)
    }

    func setShows3DGeospatialDebugMarker(_ isVisible: Bool) {
        shows3DGeospatialDebugMarker = isVisible
        geospatialDebugAnchorEntity?.isEnabled = isVisible
    }

    private func updateGeospatialDebugAnchor(_ snapshot: GeospatialDebugAnchorSnapshot?) {
        guard shows3DGeospatialDebugMarker else {
            return
        }

        guard let snapshot else {
            if let geospatialDebugAnchorEntity {
                arView.scene.removeAnchor(geospatialDebugAnchorEntity)
            }
            geospatialDebugAnchorEntity = nil
            geospatialDebugMarkerEntity = nil
            geospatialDebugLabelEntity = nil
            currentGeospatialDebugAnchorID = nil
            isGeospatialDebugMarkerSelected = false
            return
        }

        if let geospatialDebugAnchorEntity {
            if currentGeospatialDebugAnchorID != snapshot.id {
                currentGeospatialDebugAnchorID = snapshot.id
                isGeospatialDebugMarkerSelected = false
            }
            geospatialDebugAnchorEntity.transform.matrix = snapshot.transform
            geospatialDebugAnchorEntity.isEnabled = true
            updateGeospatialDebugVisualsForCamera()
            return
        }

        let anchorEntity = AnchorEntity(world: snapshot.transform)
        let marker = makeGeospatialDebugMarker(kind: snapshot.kind)
        let label = makeGeospatialDebugLabel(text: snapshot.label)
        anchorEntity.addChild(marker)
        anchorEntity.addChild(label)
        geospatialDebugAnchorEntity = anchorEntity
        geospatialDebugMarkerEntity = marker
        geospatialDebugLabelEntity = label
        currentGeospatialDebugAnchorID = snapshot.id
        isGeospatialDebugMarkerSelected = false
        arView.scene.addAnchor(anchorEntity)
        updateGeospatialDebugVisualsForCamera()
    }

    private func makeGeospatialDebugMarker(kind: String) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.55)
        let color: UIColor = kind == "Terrain" ? .systemGreen : .systemPink
        let material = SimpleMaterial(color: color, roughness: 0.1, isMetallic: false)
        let marker = ModelEntity(mesh: mesh, materials: [material])
        marker.generateCollisionShapes(recursive: false)
        return marker
    }

    private func makeGeospatialDebugLabel(text: String) -> Entity {
        let root = Entity()
        root.position = SIMD3<Float>(-1.15, 1.1, 0)

        let backgroundMesh = MeshResource.generatePlane(width: 2.9, height: 0.92)
        let backgroundMaterial = SimpleMaterial(
            color: UIColor.black.withAlphaComponent(0.78),
            roughness: 0.2,
            isMetallic: false
        )
        let background = ModelEntity(mesh: backgroundMesh, materials: [backgroundMaterial])
        background.position = SIMD3<Float>(1.03, 0.28, -0.02)
        background.generateCollisionShapes(recursive: false)

        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.018,
            font: .boldSystemFont(ofSize: 0.48),
            containerFrame: CGRect(x: 0, y: 0, width: 2.65, height: 0.68),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let textMaterial = SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position = SIMD3<Float>(0, 0, 0.02)
        textEntity.generateCollisionShapes(recursive: false)

        root.addChild(background)
        root.addChild(textEntity)
        return root
    }

    @objc private func handleARViewTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: arView)
        guard let tappedEntity = arView.entity(at: location),
              isPartOfGeospatialDebugMarker(tappedEntity) else {
            isGeospatialDebugMarkerSelected = false
            updateGeospatialDebugVisualsForCamera()
            return
        }

        isGeospatialDebugMarkerSelected.toggle()
        updateGeospatialDebugVisualsForCamera()
    }

    private func isPartOfGeospatialDebugMarker(_ entity: Entity) -> Bool {
        var currentEntity: Entity? = entity
        while let entityToCheck = currentEntity {
            if let markerEntity = geospatialDebugMarkerEntity,
               entityToCheck === markerEntity {
                return true
            }
            if let labelEntity = geospatialDebugLabelEntity,
               entityToCheck === labelEntity {
                return true
            }
            currentEntity = entityToCheck.parent
        }
        return false
    }

    private func updateGeospatialDebugVisualsForCamera() {
        guard let geospatialDebugAnchorEntity,
              let geospatialDebugLabelEntity,
              let cameraTransform = arView.session.currentFrame?.camera.transform else {
            return
        }

        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        let anchorPosition = geospatialDebugAnchorEntity.position(relativeTo: nil)
        let distance = simd_distance(cameraPosition, anchorPosition)
        geospatialDebugMarkerEntity?.scale = SIMD3<Float>(
            repeating: markerVisualScale(forDistance: distance)
        )
        geospatialDebugLabelEntity.scale = SIMD3<Float>(
            repeating: labelVisualScale(forDistance: distance)
        )
        geospatialDebugLabelEntity.look(at: cameraPosition, from: geospatialDebugLabelEntity.position(relativeTo: nil), relativeTo: nil)
        geospatialDebugLabelEntity.orientation *= simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
    }

    private func markerVisualScale(forDistance distance: Float) -> Float {
        let baseScale: Float = switch distance {
        case ..<5:
            0.65
        case ..<15:
            1.0
        case ..<30:
            1.35
        default:
            1.6
        }
        let selectedScale: Float = isGeospatialDebugMarkerSelected ? 1.2 : 1.0
        return min(baseScale * selectedScale, 2.0)
    }

    private func labelVisualScale(forDistance distance: Float) -> Float {
        let baseScale: Float = switch distance {
        case ..<5:
            0.9
        case ..<15:
            1.1
        case ..<30:
            1.5
        default:
            1.85
        }
        let selectedScale: Float = isGeospatialDebugMarkerSelected ? 1.45 : 1.0
        return min(baseScale * selectedScale, 2.6)
    }
}

extension ARSessionViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        geospatialSessionManager.update(with: frame)
        updateGeospatialDebugVisualsForCamera()
        publishCameraHeadingIfNeeded(from: frame)
        publishCameraProjectionIfNeeded(from: frame)
        if shouldRunLiveOCR {
            recognizeTextIfNeeded(in: frame)
        }
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
