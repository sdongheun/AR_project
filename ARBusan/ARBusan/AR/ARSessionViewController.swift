import ARKit
import RealityKit
import UIKit

final class ARSessionViewController: UIViewController {
    private struct GeospatialDebugRenderNode {
        let anchorEntity: AnchorEntity
        let contentEntity: Entity
        let markerEntity: ModelEntity
        let labelEntity: Entity
    }

    private var arView: ARView!
    private let geospatialSessionManager: GeospatialSessionManager
    private var geospatialDebugNodesByID: [UUID: GeospatialDebugRenderNode] = [:]
    private var selectedGeospatialDebugAnchorID: UUID?
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
        geospatialSessionManager.onDebugAnchorsUpdated = { [weak self] snapshots in
            self?.updateGeospatialDebugAnchors(snapshots)
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
        geospatialDebugNodesByID.values.forEach {
            $0.anchorEntity.isEnabled = isVisible
        }
    }

    private func updateGeospatialDebugAnchors(_ snapshots: [GeospatialDebugAnchorSnapshot]) {
        guard shows3DGeospatialDebugMarker else {
            return
        }

        let incomingIDs = Set(snapshots.map(\.id))
        for (id, node) in geospatialDebugNodesByID where !incomingIDs.contains(id) {
            arView.scene.removeAnchor(node.anchorEntity)
            geospatialDebugNodesByID[id] = nil
            if selectedGeospatialDebugAnchorID == id {
                selectedGeospatialDebugAnchorID = nil
            }
        }

        guard !snapshots.isEmpty else {
            selectedGeospatialDebugAnchorID = nil
            return
        }

        for snapshot in snapshots {
            if let node = geospatialDebugNodesByID[snapshot.id] {
                node.anchorEntity.transform.matrix = smoothedTransform(
                    current: node.anchorEntity.transform.matrix,
                    target: snapshot.transform
                )
                node.contentEntity.position = smoothedContentOffset(
                    current: node.contentEntity.position,
                    target: snapshot.contentOffset,
                    anchorTransform: node.anchorEntity.transform.matrix
                )
                node.anchorEntity.isEnabled = true
                continue
            }

            let anchorEntity = AnchorEntity(world: snapshot.transform)
            let contentEntity = Entity()
            contentEntity.position = snapshot.contentOffset
            let marker = makeGeospatialDebugMarker(kind: snapshot.kind)
            let label = makeGeospatialDebugLabel(text: snapshot.label)
            contentEntity.addChild(marker)
            contentEntity.addChild(label)
            anchorEntity.addChild(contentEntity)
            geospatialDebugNodesByID[snapshot.id] = GeospatialDebugRenderNode(
                anchorEntity: anchorEntity,
                contentEntity: contentEntity,
                markerEntity: marker,
                labelEntity: label
            )
            arView.scene.addAnchor(anchorEntity)
        }

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
              let anchorID = geospatialDebugAnchorID(containing: tappedEntity) else {
            selectedGeospatialDebugAnchorID = nil
            updateGeospatialDebugVisualsForCamera()
            return
        }

        selectedGeospatialDebugAnchorID = selectedGeospatialDebugAnchorID == anchorID ? nil : anchorID
        updateGeospatialDebugVisualsForCamera()
    }

    private func geospatialDebugAnchorID(containing entity: Entity) -> UUID? {
        var currentEntity: Entity? = entity
        while let entityToCheck = currentEntity {
            for (id, node) in geospatialDebugNodesByID {
                if entityToCheck === node.markerEntity ||
                    entityToCheck === node.labelEntity ||
                    entityToCheck === node.contentEntity {
                    return id
                }
            }
            currentEntity = entityToCheck.parent
        }
        return nil
    }

    private func updateGeospatialDebugVisualsForCamera() {
        guard let cameraTransform = arView.session.currentFrame?.camera.transform else {
            return
        }

        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        for (id, node) in geospatialDebugNodesByID {
            let contentPosition = node.contentEntity.position(relativeTo: nil)
            let distance = simd_distance(cameraPosition, contentPosition)
            let isSelected = selectedGeospatialDebugAnchorID == id
            node.markerEntity.scale = SIMD3<Float>(
                repeating: markerVisualScale(forDistance: distance, isSelected: isSelected)
            )
            node.labelEntity.scale = SIMD3<Float>(
                repeating: labelVisualScale(forDistance: distance, isSelected: isSelected)
            )
            node.labelEntity.look(at: cameraPosition, from: node.labelEntity.position(relativeTo: nil), relativeTo: nil)
            node.labelEntity.orientation *= simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    private func smoothedContentOffset(
        current: SIMD3<Float>,
        target: SIMD3<Float>,
        anchorTransform: simd_float4x4
    ) -> SIMD3<Float> {
        let targetDelta = simd_distance(current, target)
        let targetWorldPosition = worldPosition(anchorTransform: anchorTransform, localOffset: target)
        let cameraDistance = distanceFromCamera(to: targetWorldPosition)
        let alpha = transformSmoothingAlpha(cameraDistance: cameraDistance, targetDelta: targetDelta)
        return simd_mix(current, target, SIMD3<Float>(repeating: alpha))
    }

    private func worldPosition(anchorTransform: simd_float4x4, localOffset: SIMD3<Float>) -> SIMD3<Float> {
        let local = SIMD4<Float>(localOffset.x, localOffset.y, localOffset.z, 1)
        let world = anchorTransform * local
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    private func smoothedTransform(current: simd_float4x4, target: simd_float4x4) -> simd_float4x4 {
        let currentPosition = translation(from: current)
        let targetPosition = translation(from: target)
        let distance = simd_distance(currentPosition, targetPosition)
        let cameraDistance = distanceFromCamera(to: targetPosition)
        let alpha = transformSmoothingAlpha(cameraDistance: cameraDistance, targetDelta: distance)
        let smoothedPosition = simd_mix(currentPosition, targetPosition, SIMD3<Float>(repeating: alpha))

        var result = target
        result.columns.3.x = smoothedPosition.x
        result.columns.3.y = smoothedPosition.y
        result.columns.3.z = smoothedPosition.z
        return result
    }

    private func translation(from transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    private func distanceFromCamera(to position: SIMD3<Float>) -> Float {
        guard let frame = arView.session.currentFrame else {
            return simd_length(position)
        }

        let cameraPosition = translation(from: frame.camera.transform)
        return simd_distance(cameraPosition, position)
    }

    private func transformSmoothingAlpha(cameraDistance: Float, targetDelta: Float) -> Float {
        if targetDelta >= 12 {
            return 0.55
        }

        switch cameraDistance {
        case ..<5:
            return 0.2
        case ..<30:
            return 0.3
        case ..<120:
            return 0.15
        default:
            return 0.25
        }
    }

    private func markerVisualScale(forDistance distance: Float, isSelected: Bool) -> Float {
        let baseScale: Float = switch distance {
        case ..<5:
            0.42
        case ..<15:
            0.85
        case ..<30:
            1.35
        default:
            1.6
        }
        let selectedScale: Float = isSelected ? 1.2 : 1.0
        return min(baseScale * selectedScale, 2.0)
    }

    private func labelVisualScale(forDistance distance: Float, isSelected: Bool) -> Float {
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
        let selectedScale: Float = isSelected ? 1.45 : 1.0
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
