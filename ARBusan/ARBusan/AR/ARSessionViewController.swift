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
    private var arrivalPinAnchor: AnchorEntity?
    private var latestArrivalPin: ArrivalPinSnapshot?
    private var arrivalPinNameLabel: Entity?
    private var currentPinSpotName: String?
    // 공간 고정 상태: 한 번 실제 거리에 박으면 위치를 재계산하지 않고 VIO가 잡게 둔다.
    private var pinWorldLocked = false
    private let arrivalPinHeightOffset: Float = -0.3
    private let pinBeaconDistanceMeters: Float = 10      // 비콘: 내 앞 고정 거리
    private let pinWorldLockMaxRenderMeters: Float = 30  // 공간 고정 배치 거리 상한
    // 회전 chevron: 주행 방향 앵커링(시선 비추종). 카메라 위치+높이 기준 전방에 배치.
    // 거리감을 위해 실제 회전 거리에 비례해 배치하되, 너무 멀거나 가까우면 보기 나쁘므로 클램프.
    private let routeArrowMinRenderDistanceMeters: Float = 2.5
    private let routeArrowMaxRenderDistanceMeters: Float = 12
    private let routeArrowHeightOffset: Float = -0.05
    // 카메라 영상 해상도 선호. 기본은 저해상도(발열 절감), 토글로 고해상도 전환 가능.
    private var prefersHighResolutionCamera = false
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
    var onTrackingStateChanged: ((Bool, String) -> Void)?
    private var lastTrackingLimited: Bool?
    private var lastTrackingReason = ""
    // 북 재보정(§4-C): AppState의 requestID가 바뀔 때만 세션을 재실행해 월드 북을 다시 고정한다.
    private var lastAppliedRecalibrationID = 0

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

    private func startSession(resetTracking: Bool = false) {
        guard ARWorldTrackingConfiguration.isSupported else {
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        // 평면 감지는 사용하지 않는다(화살표/리본/핀은 주행 방향 앵커 기반). 상시 평면 추정 비용 제거.
        configuration.planeDetection = []
        // 저해상도 영상 포맷으로 카메라 ISP/CPU 부하를 낮춘다(발열 절감). 토글 시 기본(고해상도)으로 복귀.
        if !prefersHighResolutionCamera,
           let lowResolutionFormat = Self.lowestResolutionVideoFormat() {
            configuration.videoFormat = lowResolutionFormat
        }

        // 북 재보정(§4-C): 트래킹/앵커를 리셋해 현재(더 정확한) 나침반 기준으로 월드 북을 다시 고정한다.
        let options: ARSession.RunOptions = resetTracking ? [.resetTracking, .removeExistingAnchors] : []
        arView.session.run(configuration, options: options)
    }

    /// 북 재보정(§4-C 수동): 세션을 리셋 재실행해 월드 북을 현재 나침반 기준으로 다시 고정한다.
    /// 직후 ARKit이 `.limited(.initializing)`이 되어 §4-B 경로로 3D 안내가 잠시 강등된다.
    func applyRecalibrationIfNeeded(requestID: Int) {
        guard requestID != lastAppliedRecalibrationID else {
            return
        }
        lastAppliedRecalibrationID = requestID
        guard requestID > 0, isViewLoaded else {
            return
        }
        startSession(resetTracking: true)
    }

    /// 지원 포맷 중 가장 낮은 해상도(동률이면 낮은 fps)를 고른다. 발열 절감용.
    private static func lowestResolutionVideoFormat() -> ARConfiguration.VideoFormat? {
        ARWorldTrackingConfiguration.supportedVideoFormats.min { lhs, rhs in
            let lhsPixels = lhs.imageResolution.width * lhs.imageResolution.height
            let rhsPixels = rhs.imageResolution.width * rhs.imageResolution.height
            if lhsPixels != rhsPixels {
                return lhsPixels < rhsPixels
            }
            return lhs.framesPerSecond < rhs.framesPerSecond
        }
    }

    func setPrefersHighResolutionCamera(_ prefersHighResolution: Bool) {
        guard prefersHighResolution != prefersHighResolutionCamera else {
            return
        }
        prefersHighResolutionCamera = prefersHighResolution
        // 영상 포맷은 세션 재구성으로만 바뀐다. 수동 토글이라 짧은 재추적은 허용.
        if isViewLoaded {
            startSession()
        }
    }

    func setShows3DGeospatialDebugMarker(_ isVisible: Bool) {
        shows3DGeospatialDebugMarker = isVisible
        geospatialDebugNodesByID.values.forEach {
            $0.anchorEntity.isEnabled = isVisible
        }
    }

    func setArrivalPin(_ pin: ArrivalPinSnapshot?) {
        guard let pin else {
            if let arrivalPinAnchor {
                arView.scene.removeAnchor(arrivalPinAnchor)
                self.arrivalPinAnchor = nil
            }
            latestArrivalPin = nil
            arrivalPinNameLabel = nil
            currentPinSpotName = nil
            pinWorldLocked = false
            return
        }

        // 앵커가 없거나 목적지가 바뀌면 핀(빨간 지도 핀 + 이름 라벨)을 새로 만든다.
        if arrivalPinAnchor == nil || pin.spotName != currentPinSpotName {
            if let arrivalPinAnchor {
                arView.scene.removeAnchor(arrivalPinAnchor)
            }
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(makeArrivalPinEntity(name: pin.spotName))
            arView.scene.addAnchor(anchor)
            arrivalPinAnchor = anchor
            currentPinSpotName = pin.spotName
            pinWorldLocked = false
        }
        latestArrivalPin = pin
    }

    // 빨간 지도 핀(둥근 머리 + 아래 막대) + 목적지 이름 큰 텍스트. 축대칭이라 yaw 불필요(중력 정렬).
    // iOS 17 호환을 위해 generateSphere/generateBox/generateText만 사용한다.
    private func makeArrivalPinEntity(name: String) -> Entity {
        let root = Entity()
        let pinColor = UIColor.systemRed
        let solid = SimpleMaterial(color: pinColor.withAlphaComponent(0.98), roughness: 0.15, isMetallic: false)
        let glow = SimpleMaterial(color: pinColor.withAlphaComponent(0.28), roughness: 0.1, isMetallic: false)

        let halo = ModelEntity(mesh: .generateSphere(radius: 0.55), materials: [glow])
        halo.position = SIMD3<Float>(0, 0.5, 0)
        root.addChild(halo)

        let head = ModelEntity(mesh: .generateSphere(radius: 0.36), materials: [solid])
        head.position = SIMD3<Float>(0, 0.5, 0)
        root.addChild(head)

        let dot = ModelEntity(
            mesh: .generateSphere(radius: 0.14),
            materials: [SimpleMaterial(color: .white, roughness: 0.2, isMetallic: false)]
        )
        dot.position = SIMD3<Float>(0, 0.5, 0.28)
        root.addChild(dot)

        // 꼬리: 머리 아래로 내려가는 막대(핀 끝).
        let stem = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.10, 0.6, 0.10)),
            materials: [solid]
        )
        stem.position = SIMD3<Float>(0, 0.02, 0)
        root.addChild(stem)

        // 목적지 이름 큰 텍스트(빌보드). 매 프레임 카메라를 바라보게 한다.
        let label = makePinNameLabel(text: name)
        label.position = SIMD3<Float>(0, 1.25, 0)
        root.addChild(label)
        arrivalPinNameLabel = label

        root.scale = SIMD3<Float>(repeating: 1.5)
        return root
    }

    private func makePinNameLabel(text: String) -> Entity {
        let root = Entity()
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.02,
            font: .boldSystemFont(ofSize: 0.5),
            containerFrame: CGRect(x: -2, y: -0.4, width: 4, height: 0.8),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let shadow = ModelEntity(
            mesh: textMesh,
            materials: [SimpleMaterial(color: UIColor.black.withAlphaComponent(0.8), roughness: 0.2, isMetallic: false)]
        )
        shadow.position = SIMD3<Float>(0.03, -0.03, -0.02)
        let label = ModelEntity(mesh: textMesh, materials: [SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)])
        root.addChild(shadow)
        root.addChild(label)
        return root
    }

    // 적응형 배치: 비콘(매 프레임 내 앞 고정 거리) ↔ 공간 고정(가까우면 실제 거리에 한 번 박고 VIO가 잡음).
    private func updateArrivalPinPlacement(from frame: ARFrame) {
        guard let latestArrivalPin, let arrivalPinAnchor else {
            return
        }

        // 카메라 transform에서 위치(높이 포함)만 사용한다(시선 비추종).
        let cameraColumn = frame.camera.transform.columns.3
        let cameraWorldPosition = SIMD3<Float>(cameraColumn.x, cameraColumn.y, cameraColumn.z)

        if latestArrivalPin.isWorldLocked {
            // 공간 고정: 처음 진입 시 실제 거리에 한 번 박고 이후엔 건드리지 않는다(VIO가 공간에 잡음).
            if !pinWorldLocked {
                let distance = max(min(Float(latestArrivalPin.distanceMeters), pinWorldLockMaxRenderMeters), 1)
                arrivalPinAnchor.transform.translation = TravelDirectionAnchor.worldPosition(
                    cameraWorldPosition: cameraWorldPosition,
                    bearingDegrees: latestArrivalPin.bearingDegrees,
                    distanceMeters: distance,
                    heightOffsetMeters: arrivalPinHeightOffset
                )
                arrivalPinAnchor.transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                pinWorldLocked = true
            }
        } else {
            // 비콘: 매 프레임 목적지 방위로 내 앞 고정 거리에 둔다(위치 오차 영향 최소).
            pinWorldLocked = false
            arrivalPinAnchor.transform.translation = TravelDirectionAnchor.worldPosition(
                cameraWorldPosition: cameraWorldPosition,
                bearingDegrees: latestArrivalPin.bearingDegrees,
                distanceMeters: pinBeaconDistanceMeters,
                heightOffsetMeters: arrivalPinHeightOffset
            )
            arrivalPinAnchor.transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }

        // 이름 라벨은 항상 카메라를 바라보게(빌보드).
        if let arrivalPinNameLabel {
            let labelWorld = arrivalPinNameLabel.position(relativeTo: nil)
            arrivalPinNameLabel.look(at: cameraWorldPosition, from: labelWorld, relativeTo: nil)
            arrivalPinNameLabel.orientation *= simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
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
            onRouteArrowRenderStatusUpdated?("\(path.spotName) RealityKit 회전 화살표 유지 / \(path.arrows.count)개 / 주행 방향 앵커(기기 높이)")
            return
        }

        if let routeArrowNode {
            arView.scene.removeAnchor(routeArrowNode.anchorEntity)
        }

        // 월드 앵커. 위치/방향은 매 프레임 updateRouteArrowPlacement에서 카메라 위치 + 주행 방위로 갱신한다(시선 비추종).
        let anchor = AnchorEntity(world: .zero)
        let arrows = path.arrows.map { snapshot -> Entity in
            let arrow = makeRouteArrowEntity(turnDirection: snapshot.turnDirection)
            arrow.position = .zero
            anchor.addChild(arrow)
            return arrow
        }
        routeArrowNode = RouteArrowRenderNode(
            anchorEntity: anchor,
            arrowEntities: arrows,
            turnDirections: path.arrows.map(\.turnDirection)
        )
        arView.scene.addAnchor(anchor)
        onRouteArrowRenderStatusUpdated?("\(path.spotName) RealityKit 회전 화살표 생성 / \(arrows.count)개 / 주행 방향 앵커(기기 높이)")
    }

    private func updateRouteArrowPlacement(from frame: ARFrame) {
        guard let routeArrowNode,
              let arrow = latestRouteArrowPath?.arrows.first else {
            return
        }

        let bearing = arrow.bearingDegrees
        // 실제 회전 거리에 비례해 배치(가까워지면 화살표도 가까워짐). 보기 위해 2.5~12m로 클램프.
        let renderDistance = min(
            max(Float(arrow.distanceFromOriginMeters), routeArrowMinRenderDistanceMeters),
            routeArrowMaxRenderDistanceMeters
        )
        let cameraColumn = frame.camera.transform.columns.3
        let cameraWorldPosition = SIMD3<Float>(cameraColumn.x, cameraColumn.y, cameraColumn.z)
        routeArrowNode.anchorEntity.transform.translation = TravelDirectionAnchor.worldPosition(
            cameraWorldPosition: cameraWorldPosition,
            bearingDegrees: bearing,
            distanceMeters: renderDistance,
            heightOffsetMeters: routeArrowHeightOffset
        )
        // 패널 콘텐츠면(+Z)이 사용자를 향하도록 회전. orientation(bearing)은 -Z를 주행 방위로,
        // 즉 +Z(=chevron/텍스트 면)를 사용자 쪽으로 돌려 좌/우 chevron이 읽히게 한다.
        routeArrowNode.anchorEntity.transform.rotation = TravelDirectionAnchor.orientation(bearingDegrees: bearing)
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
        // 화면(카메라) 기준 보정 없음: 월드 앵커가 매 프레임 사용자를 향하도록 회전시킨다.
        root.scale = SIMD3<Float>(repeating: scale)
        return root
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
        publishTrackingStateIfChanged(from: frame)
        updateGeospatialDebugVisualsForCamera()
        updateRouteArrowPlacement(from: frame)
        updateArrivalPinPlacement(from: frame)
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

    private func publishTrackingStateIfChanged(from frame: ARFrame) {
        let (limited, reason) = trackingStability(frame.camera.trackingState)
        // 상태가 바뀔 때만 올린다(매 프레임 호출 방지).
        guard limited != lastTrackingLimited || reason != lastTrackingReason else {
            return
        }
        lastTrackingLimited = limited
        lastTrackingReason = reason
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingStateChanged?(limited, reason)
        }
    }

    /// 트래킹 상태를 (3D 안내를 숨겨야 하는가, 사용자 안내 사유)로 변환한다.
    private func trackingStability(_ trackingState: ARCamera.TrackingState) -> (limited: Bool, reason: String) {
        switch trackingState {
        case .normal:
            return (false, "정상")
        case .notAvailable:
            return (true, "AR 추적을 사용할 수 없습니다")
        case let .limited(reason):
            switch reason {
            case .initializing:
                return (true, "AR 초기화 중입니다")
            case .relocalizing:
                return (true, "위치 재인식 중입니다")
            case .excessiveMotion:
                return (true, "기기를 천천히 움직여 주세요")
            case .insufficientFeatures:
                return (true, "주변을 천천히 비춰 주세요")
            @unknown default:
                return (true, "AR 추적이 불안정합니다")
            }
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
