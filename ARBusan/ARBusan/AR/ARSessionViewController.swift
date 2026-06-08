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

    private struct RouteArrowRenderNode {
        let anchorEntity: AnchorEntity
        let arrowEntities: [Entity]
        let turnDirections: [RouteTurnDirection]
    }

    private var arView: ARView!
    private let geospatialSessionManager: GeospatialSessionManager
    private var geospatialDebugNodesByID: [UUID: GeospatialDebugRenderNode] = [:]
    private var routeArrowNode: RouteArrowRenderNode?
    private var latestRouteArrowPath: RouteArrowPathSnapshot?
    private var detectedGroundY: Float?
    private var lastGroundRaycastTimestamp: TimeInterval = 0
    private let groundRaycastInterval: TimeInterval = 1.0
    private let markerScreenScalePerMeter: Float = 0.085
    private let labelScreenScalePerMeter: Float = 0.075
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
    var onRouteArrowRenderStatusUpdated: ((String) -> Void)?

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
        configuration.planeDetection = [.horizontal]

        arView.session.run(configuration)
    }

    func setShows3DGeospatialDebugMarker(_ isVisible: Bool) {
        shows3DGeospatialDebugMarker = isVisible
        geospatialDebugNodesByID.values.forEach {
            $0.anchorEntity.isEnabled = isVisible
        }
    }

    func setRouteArrowPath(_ path: RouteArrowPathSnapshot?) {
        latestRouteArrowPath = path
        applyRouteArrowPath(path)
    }

    private func applyRouteArrowPath(_ path: RouteArrowPathSnapshot?) {
        guard let path, !path.arrows.isEmpty else {
            if let routeArrowNode {
                arView.scene.removeAnchor(routeArrowNode.anchorEntity)
                self.routeArrowNode = nil
                onRouteArrowRenderStatusUpdated?("RealityKit 화살표 제거 / routeArrowPath nil 또는 0개")
            } else {
                onRouteArrowRenderStatusUpdated?("RealityKit 화살표 없음 / routeArrowPath nil 또는 0개")
            }
            return
        }

        if let routeArrowNode,
           routeArrowNode.arrowEntities.count == path.arrows.count,
           routeArrowNode.turnDirections == path.arrows.map(\.turnDirection) {
            let heightText = routeArrowHeightText()
            onRouteArrowRenderStatusUpdated?("\(path.spotName) RealityKit 회전 화살표 유지 / \(path.arrows.count)개 / \(heightText)")
            return
        }

        if let routeArrowNode {
            arView.scene.removeAnchor(routeArrowNode.anchorEntity)
        }

        guard let cameraTransform = arView.session.currentFrame?.camera.transform else {
            routeArrowNode = nil
            onRouteArrowRenderStatusUpdated?("\(path.spotName) RealityKit 회전 화살표 생성 대기 / ARFrame camera transform 없음")
            return
        }

        let anchor = AnchorEntity(world: cameraTransform)
        let arrows = path.arrows.map { snapshot in
            let arrow = makeRouteArrowEntity(turnDirection: snapshot.turnDirection)
            arrow.position = routeArrowPosition(from: snapshot)
            anchor.addChild(arrow)
            return arrow
        }
        routeArrowNode = RouteArrowRenderNode(
            anchorEntity: anchor,
            arrowEntities: arrows,
            turnDirections: path.arrows.map(\.turnDirection)
        )
        arView.scene.addAnchor(anchor)
        let heightText = routeArrowHeightText()
        onRouteArrowRenderStatusUpdated?("\(path.spotName) RealityKit 회전 화살표 생성 / \(arrows.count)개 / \(heightText)")
    }

    private func routeArrowHeightText() -> String {
        "world-space anchor / 생성 순간 카메라 전방 기준"
    }

    private func routeArrowPosition(from snapshot: RouteArrowSnapshot) -> SIMD3<Float> {
        snapshot.position
    }

    private func makeRouteArrowEntity(turnDirection: RouteTurnDirection) -> Entity {
        let root = Entity()
        let isRightTurn = turnDirection == .right
        let material = SimpleMaterial(color: .systemBlue.withAlphaComponent(0.98), roughness: 0.12, isMetallic: false)
        let glowMaterial = SimpleMaterial(color: .cyan.withAlphaComponent(0.28), roughness: 0.1, isMetallic: false)
        let scale: Float = 1.85

        let backing = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(2.9, 1.18, 0.045)),
            materials: [glowMaterial]
        )
        backing.position = SIMD3<Float>(0, 0, -0.08)
        root.addChild(backing)

        let spacing: Float = 0.72
        for index in 0..<3 {
            let chevron = makeRouteChevronEntity(isRightTurn: isRightTurn, material: material)
            chevron.position = SIMD3<Float>((Float(index) - 1) * spacing, 0, 0)
            root.addChild(chevron)
        }

        let label = makeRouteArrowTextEntity(text: isRightTurn ? ">>>" : "<<<")
        label.position = SIMD3<Float>(0, -0.62, 0.03)
        root.addChild(label)
        root.orientation = routeArrowScreenOrientationCorrection()
        root.scale = SIMD3<Float>(repeating: scale)
        return root
    }

    private func routeArrowScreenOrientationCorrection() -> simd_quatf {
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        let angle: Float
        switch orientation {
        case .portrait:
            angle = .pi / 2
        case .portraitUpsideDown:
            angle = -.pi / 2
        case .landscapeLeft, .landscapeRight:
            angle = 0
        default:
            angle = .pi / 2
        }
        return simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
    }

    private func makeRouteChevronEntity(isRightTurn: Bool, material: SimpleMaterial) -> Entity {
        ModelEntity(mesh: makeRouteChevronMesh(isRightTurn: isRightTurn), materials: [material])
    }

    private func makeRouteChevronMesh(isRightTurn: Bool) -> MeshResource {
        var descriptor = MeshDescriptor()
        let tipX: Float = isRightTurn ? 0.34 : -0.34
        let tailX: Float = isRightTurn ? -0.34 : 0.34
        let vertices: [SIMD3<Float>] = [
            SIMD3<Float>(tipX, 0, 0.06),
            SIMD3<Float>(tailX, 0.45, 0.06),
            SIMD3<Float>(tailX, -0.45, 0.06),
            SIMD3<Float>(tipX, 0, -0.06),
            SIMD3<Float>(tailX, 0.45, -0.06),
            SIMD3<Float>(tailX, -0.45, -0.06)
        ]
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles([
            0, 1, 2,
            3, 5, 4,
            0, 3, 4,
            0, 4, 1,
            1, 4, 5,
            1, 5, 2,
            2, 5, 3,
            2, 3, 0
        ])
        return try! MeshResource.generate(from: [descriptor])
    }

    private func makeRouteArrowTextEntity(text: String) -> Entity {
        let root = Entity()
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.018,
            font: .systemFont(ofSize: 0.3, weight: .black),
            containerFrame: CGRect(x: -0.7, y: -0.16, width: 1.4, height: 0.32),
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let shadow = ModelEntity(
            mesh: textMesh,
            materials: [SimpleMaterial(color: UIColor.black.withAlphaComponent(0.76), roughness: 0.18, isMetallic: false)]
        )
        shadow.position = SIMD3<Float>(0.018, -0.014, -0.018)
        let label = ModelEntity(
            mesh: textMesh,
            materials: [SimpleMaterial(color: UIColor.white, roughness: 0.1, isMetallic: false)]
        )
        root.addChild(shadow)
        root.addChild(label)
        return root
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
        let color: UIColor = kind == "Terrain" ? .systemGreen : .systemPink
        let material = SimpleMaterial(color: color, roughness: 0.1, isMetallic: false)
        let marker = ModelEntity(mesh: .generateSphere(radius: 0.34), materials: [material])
        marker.position = SIMD3<Float>(0, 0.28, 0)

        let stem = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.13, 0.52, 0.13)),
            materials: [material]
        )
        stem.position = SIMD3<Float>(0, -0.28, 0)
        marker.addChild(stem)

        let tip = ModelEntity(mesh: .generateSphere(radius: 0.13), materials: [material])
        tip.position = SIMD3<Float>(0, -0.58, 0)
        marker.addChild(tip)
        marker.generateCollisionShapes(recursive: false)
        return marker
    }

    private func makeGeospatialDebugLabel(text: String) -> Entity {
        let root = Entity()
        root.position = SIMD3<Float>(-1.45, 1.18, 0)

        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.022,
            font: .boldSystemFont(ofSize: 0.68),
            containerFrame: CGRect(x: 0, y: 0, width: 3.4, height: 0.86),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let shadowMaterial = SimpleMaterial(color: UIColor.black.withAlphaComponent(0.84), roughness: 0.18, isMetallic: false)
        let shadowEntity = ModelEntity(mesh: textMesh, materials: [shadowMaterial])
        shadowEntity.position = SIMD3<Float>(0.045, -0.045, 0)
        shadowEntity.generateCollisionShapes(recursive: false)

        let textMaterial = SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position = SIMD3<Float>(0, 0, 0.02)
        textEntity.generateCollisionShapes(recursive: false)

        root.addChild(shadowEntity)
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
            let markerScale = markerVisualScale(forDistance: distance, isSelected: isSelected)
            let labelScale = labelVisualScale(forDistance: distance, isSelected: isSelected)
            node.markerEntity.scale = SIMD3<Float>(repeating: markerScale)
            node.labelEntity.scale = SIMD3<Float>(repeating: labelScale)
            node.labelEntity.position = labelPosition(forScale: labelScale)
            node.labelEntity.look(at: cameraPosition, from: node.labelEntity.position(relativeTo: nil), relativeTo: nil)
            node.labelEntity.orientation *= simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    private func updateRouteArrowGroundYIfNeeded(from frame: ARFrame) {
        // Route arrows are camera-anchored in this MVP, so ground raycast is not used.
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
        let baseScale = distance * markerScreenScalePerMeter
        let selectedScale: Float = isSelected ? 1.25 : 1.0
        return (baseScale * selectedScale).clamped(to: 0.42...8.0)
    }

    private func labelVisualScale(forDistance distance: Float, isSelected: Bool) -> Float {
        let baseScale = distance * labelScreenScalePerMeter
        let selectedScale: Float = isSelected ? 1.35 : 1.0
        return (baseScale * selectedScale).clamped(to: 0.5...7.5)
    }

    private func labelPosition(forScale scale: Float) -> SIMD3<Float> {
        SIMD3<Float>(-1.45 * scale, 1.18 * scale, 0)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension ARSessionViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        geospatialSessionManager.update(with: frame)
        updateGeospatialDebugVisualsForCamera()
        updateRouteArrowGroundYIfNeeded(from: frame)
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
