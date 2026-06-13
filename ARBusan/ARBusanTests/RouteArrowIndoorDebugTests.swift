import CoreLocation
import XCTest
@testable import ARBusan

@MainActor
final class RouteArrowIndoorDebugTests: XCTestCase {
    func testDestinationPinIsBeaconWhenFar() throws {
        // 목적지가 멀면(>30m) 핀은 비콘(방향만). 회전 화살표·배너는 폐기되어 항상 nil.
        let fixture = makeStraightNorthRouteFixture(originDistanceMeters: 45)
        fixture.appState.updateCameraHeading(0)

        let pin = try XCTUnwrap(fixture.appState.arrivalPin)
        XCTAssertFalse(pin.isWorldLocked)
        XCTAssertNil(fixture.appState.routeArrowPath)
        XCTAssertNil(fixture.appState.navigationTurnBanner)
    }

    func testDestinationPinIsWorldLockedWhenNear() throws {
        // 목적지가 가까우면(≤30m, 도착 반경 밖)엔 핀이 공간 고정으로 전환된다.
        let fixture = makeStraightNorthRouteFixture(originDistanceMeters: 25)
        fixture.appState.updateCameraHeading(0)

        let pin = try XCTUnwrap(fixture.appState.arrivalPin)
        XCTAssertTrue(pin.isWorldLocked)
    }

    func testArrivalPinAppearsWithinCompletionRadiusAndHidesEdgeMarkers() throws {
        let destination = CLLocationCoordinate2D(latitude: 35.245700, longitude: 128.904000)
        let spot = TourismSpot(
            id: "arrival-target",
            name: "도착 테스트 목적지",
            address: "실내 디버그",
            districtName: "테스트",
            category: "길찾기",
            source: .mock,
            geometryKind: .point,
            center: destination,
            recognitionHints: ["도착 테스트 목적지"],
            notes: "도착 판정/핀 테스트"
        )
        // 현재 위치를 도착 좌표와 동일하게 둬 도착 반경(10m) 안으로 만든다.
        let origin = LocationSnapshot(
            latitude: destination.latitude,
            longitude: destination.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let route = TMAPPedestrianRoute(
            destinationName: spot.name,
            requestedStart: destination,
            requestedDestination: destination,
            arrivalCoordinate: destination,
            routeCoordinates: [destination],
            totalDistanceMeters: nil,
            totalTimeSeconds: nil
        )
        let appState = AppState(spots: [spot])
        appState.spots = [spot]
        appState.selectedSpot = spot
        appState.navigationDestinationSpotID = spot.id
        appState.isNavigationModeEnabled = true
        appState.isIndoorDebugModeEnabled = true
        appState.latestLocationSnapshot = origin
        appState.latestGeospatialLocationSnapshot = origin
        appState.locationConfidence = .high
        appState.effectiveSpatialConfidence = .high
        appState.tmapArrivalRoutesBySpotID[spot.id] = route

        appState.updateCameraHeading(0)

        let pin = try XCTUnwrap(appState.arrivalPin)
        XCTAssertEqual(pin.spotID, spot.id)
        XCTAssertLessThanOrEqual(pin.distanceMeters, 10)
        XCTAssertNil(appState.routeArrowPath)
        XCTAssertTrue(appState.edgeMarkerOverlays.isEmpty)
        XCTAssertTrue(appState.navigationGuidanceIsArrivalNearby)
    }

    func testTrackingLimitedHidesArrowAndBanner() {
        // AR 트래킹이 불안정하면 3D 안내를 모두 끄고 보수 텍스트로 강등한다(§4-B).
        let fixture = makeRightTurnFixture(originNorthOffsetMeters: -5)
        fixture.appState.arTrackingLimited = true

        fixture.appState.updateCameraHeading(0)

        XCTAssertNil(fixture.appState.routeArrowPath)
        XCTAssertNil(fixture.appState.navigationTurnBanner)
        XCTAssertTrue(fixture.appState.navigationGuidanceIsConservative)
    }

    func testManualRefreshOnRouteDoesNotReroute() {
        // 온-루트인데 수동 버튼을 누르면 위치/heading 보정만 하고 경로 재탐색(API)은 하지 않는다(§4-A 스마트).
        let fixture = makeRightTurnFixture(originNorthOffsetMeters: -5)
        fixture.appState.updateCameraHeading(0)

        fixture.appState.requestReroute(manual: true)

        XCTAssertFalse(fixture.appState.isRerouting)
        XCTAssertNotNil(fixture.appState.navigationManualNotice)
    }

    func testManualNorthRecalibrationBumpsRequestAndEntersRecalibrating() {
        // 수동 "방향 보정" → 세션 재고정 트리거(requestID 증가) + 재보정 중 진입 + 의심 플래그 해제(§4-C).
        let fixture = makeRightTurnFixture(originNorthOffsetMeters: -5)
        fixture.appState.updateCameraHeading(0)
        fixture.appState.headingMiscalibrated = true
        let beforeID = fixture.appState.northRecalibrationRequestID

        fixture.appState.requestNorthRecalibration()

        XCTAssertEqual(fixture.appState.northRecalibrationRequestID, beforeID + 1)
        XCTAssertTrue(fixture.appState.isRecalibratingNorth)
        XCTAssertFalse(fixture.appState.headingMiscalibrated)
        XCTAssertNotNil(fixture.appState.navigationManualNotice)

        // 재보정 중엔 중복 트리거가 무시된다(세션 reset 연타 방지).
        fixture.appState.requestNorthRecalibration()
        XCTAssertEqual(fixture.appState.northRecalibrationRequestID, beforeID + 1)

        // 트래킹이 normal로 돌아오면 재보정 완료 처리.
        fixture.appState.updateARTrackingState(limited: false, reason: "정상")
        XCTAssertFalse(fixture.appState.isRecalibratingNorth)
    }

    /// 북쪽으로 곧게 뻗는 경로(목적지=기준점)에서 origin을 지정 거리만큼 남쪽 on-route에 둔다.
    /// 적응형 핀의 비콘↔공간 고정 전환을 거리로 검증하기 위함.
    private func makeStraightNorthRouteFixture(
        originDistanceMeters: Double
    ) -> (appState: AppState, spot: TourismSpot) {
        let destination = CLLocationCoordinate2D(latitude: 35.245700, longitude: 128.904000)
        let destOrigin = LocationSnapshot(
            latitude: destination.latitude,
            longitude: destination.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let routeStart = LocalENUProjector.coordinate(eastMeters: 0, northMeters: -60, from: destOrigin)
        let originCoordinate = LocalENUProjector.coordinate(eastMeters: 0, northMeters: -originDistanceMeters, from: destOrigin)
        let spot = TourismSpot(
            id: "straight-route-target",
            name: "직진 경로 목적지",
            address: "실내 디버그",
            districtName: "테스트",
            category: "길찾기",
            source: .mock,
            geometryKind: .point,
            center: destination,
            recognitionHints: ["직진 경로 목적지"],
            notes: "적응형 목적지 핀 테스트"
        )
        let origin = LocationSnapshot(
            latitude: originCoordinate.latitude,
            longitude: originCoordinate.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let route = TMAPPedestrianRoute(
            destinationName: spot.name,
            requestedStart: originCoordinate,
            requestedDestination: destination,
            arrivalCoordinate: destination,
            routeCoordinates: [routeStart, destination],
            totalDistanceMeters: nil,
            totalTimeSeconds: nil
        )
        let appState = AppState(spots: [spot])
        appState.spots = [spot]
        appState.selectedSpot = spot
        appState.navigationDestinationSpotID = spot.id
        appState.isNavigationModeEnabled = true
        appState.isIndoorDebugModeEnabled = true
        appState.latestLocationSnapshot = origin
        appState.latestGeospatialLocationSnapshot = origin
        appState.locationConfidence = .high
        appState.effectiveSpatialConfidence = .high
        appState.tmapArrivalRoutesBySpotID[spot.id] = route
        return (appState, spot)
    }

    private func makeSmallAngleRightTurnFixture(
        includeManeuver: Bool,
        turnType: Int = 13
    ) -> (appState: AppState, spot: TourismSpot) {
        let turnCoordinate = CLLocationCoordinate2D(latitude: 35.245700, longitude: 128.904000)
        let turnOrigin = LocationSnapshot(
            latitude: turnCoordinate.latitude,
            longitude: turnCoordinate.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        // 진입: 남쪽에서 북쪽으로. 진출: 북에서 동쪽으로 30도만 꺾임(작은 각도).
        let incoming = LocalENUProjector.coordinate(eastMeters: 0, northMeters: -10, from: turnOrigin)
        let outgoing = LocalENUProjector.coordinate(eastMeters: 4, northMeters: 6.9, from: turnOrigin)
        let originCoordinate = LocalENUProjector.coordinate(eastMeters: 0, northMeters: -5, from: turnOrigin)
        let routeCoordinates = [incoming, turnCoordinate, outgoing]

        let spot = TourismSpot(
            id: "maneuver-small-angle-target",
            name: "갈림길 테스트 목적지",
            address: "실내 디버그",
            districtName: "테스트",
            category: "길찾기",
            source: .mock,
            geometryKind: .point,
            center: outgoing,
            recognitionHints: ["갈림길 테스트 목적지"],
            notes: "작은 각도 + TMAP 안내점 회전 테스트"
        )
        let origin = LocationSnapshot(
            latitude: originCoordinate.latitude,
            longitude: originCoordinate.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let maneuvers: [TMAPRouteManeuver] = includeManeuver
            ? [TMAPRouteManeuver(coordinate: turnCoordinate, turnType: turnType, kind: .from(turnType: turnType), description: "회전")]
            : []
        let route = TMAPPedestrianRoute(
            destinationName: spot.name,
            requestedStart: originCoordinate,
            requestedDestination: spot.center,
            arrivalCoordinate: outgoing,
            routeCoordinates: routeCoordinates,
            totalDistanceMeters: nil,
            totalTimeSeconds: nil,
            maneuvers: maneuvers
        )
        let appState = AppState(spots: [spot])
        appState.spots = [spot]
        appState.selectedSpot = spot
        appState.navigationDestinationSpotID = spot.id
        appState.isNavigationModeEnabled = true
        appState.isIndoorDebugModeEnabled = true
        appState.latestLocationSnapshot = origin
        appState.latestGeospatialLocationSnapshot = origin
        appState.locationConfidence = .high
        appState.effectiveSpatialConfidence = .high
        appState.tmapArrivalRoutesBySpotID[spot.id] = route
        return (appState, spot)
    }

    private func makeRightTurnFixture(
        originNorthOffsetMeters: Double
    ) -> (appState: AppState, spot: TourismSpot) {
        let turnCoordinate = CLLocationCoordinate2D(latitude: 35.245700, longitude: 128.904000)
        let turnOrigin = LocationSnapshot(
            latitude: turnCoordinate.latitude,
            longitude: turnCoordinate.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let routeStart = LocalENUProjector.coordinate(
            eastMeters: 0,
            northMeters: -20,
            from: turnOrigin
        )
        let routeEnd = LocalENUProjector.coordinate(
            eastMeters: 20,
            northMeters: 0,
            from: turnOrigin
        )
        let originCoordinate = LocalENUProjector.coordinate(
            eastMeters: 0,
            northMeters: originNorthOffsetMeters,
            from: turnOrigin
        )
        let spot = TourismSpot(
            id: "route-arrow-target",
            name: "우회전 테스트 목적지",
            address: "실내 디버그",
            districtName: "테스트",
            category: "길찾기",
            source: .mock,
            geometryKind: .point,
            center: routeEnd,
            recognitionHints: ["우회전 테스트 목적지"],
            notes: "90도 우회전 경로 테스트"
        )
        let origin = LocationSnapshot(
            latitude: originCoordinate.latitude,
            longitude: originCoordinate.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let route = TMAPPedestrianRoute(
            destinationName: spot.name,
            requestedStart: originCoordinate,
            requestedDestination: spot.center,
            arrivalCoordinate: spot.center,
            routeCoordinates: [routeStart, turnCoordinate, routeEnd],
            totalDistanceMeters: nil,
            totalTimeSeconds: nil
        )
        let appState = AppState(spots: [spot])
        appState.spots = [spot]
        appState.selectedSpot = spot
        appState.navigationDestinationSpotID = spot.id
        appState.isNavigationModeEnabled = true
        appState.isIndoorDebugModeEnabled = true
        appState.latestLocationSnapshot = origin
        appState.latestGeospatialLocationSnapshot = origin
        appState.locationConfidence = .high
        appState.effectiveSpatialConfidence = .high
        appState.tmapArrivalRoutesBySpotID[spot.id] = route
        return (appState, spot)
    }

    private func makeSegmentedLeftTurnFixture() -> (appState: AppState, spot: TourismSpot) {
        let turnCoordinate = CLLocationCoordinate2D(latitude: 35.245700, longitude: 128.904000)
        let turnOrigin = LocationSnapshot(
            latitude: turnCoordinate.latitude,
            longitude: turnCoordinate.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )

        // 회전점 주변은 촘촘한 세그먼트로 두되, 도착점은 도착 반경(10m) 밖이 되도록 멀리 둔다.
        let routeCoordinates = [
            LocalENUProjector.coordinate(eastMeters: 0, northMeters: -8, from: turnOrigin),
            LocalENUProjector.coordinate(eastMeters: 0, northMeters: -5, from: turnOrigin),
            LocalENUProjector.coordinate(eastMeters: 0, northMeters: -2, from: turnOrigin),
            turnCoordinate,
            LocalENUProjector.coordinate(eastMeters: -2, northMeters: 0, from: turnOrigin),
            LocalENUProjector.coordinate(eastMeters: -5, northMeters: 0, from: turnOrigin),
            LocalENUProjector.coordinate(eastMeters: -8, northMeters: 0, from: turnOrigin),
            LocalENUProjector.coordinate(eastMeters: -20, northMeters: 0, from: turnOrigin)
        ]
        let originCoordinate = LocalENUProjector.coordinate(
            eastMeters: 0,
            northMeters: -5,
            from: turnOrigin
        )
        let spot = TourismSpot(
            id: "segmented-left-turn-target",
            name: "좌회전 테스트 목적지",
            address: "실내 디버그",
            districtName: "테스트",
            category: "길찾기",
            source: .mock,
            geometryKind: .point,
            center: routeCoordinates.last!,
            recognitionHints: ["좌회전 테스트 목적지"],
            notes: "짧은 세그먼트 좌회전 경로 테스트"
        )
        let origin = LocationSnapshot(
            latitude: originCoordinate.latitude,
            longitude: originCoordinate.longitude,
            altitude: nil,
            horizontalAccuracy: 1,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .arCoreGeospatial,
            capturedAt: Date()
        )
        let route = TMAPPedestrianRoute(
            destinationName: spot.name,
            requestedStart: originCoordinate,
            requestedDestination: spot.center,
            arrivalCoordinate: spot.center,
            routeCoordinates: routeCoordinates,
            totalDistanceMeters: nil,
            totalTimeSeconds: nil
        )
        let appState = AppState(spots: [spot])
        appState.spots = [spot]
        appState.selectedSpot = spot
        appState.navigationDestinationSpotID = spot.id
        appState.isNavigationModeEnabled = true
        appState.isIndoorDebugModeEnabled = true
        appState.latestLocationSnapshot = origin
        appState.latestGeospatialLocationSnapshot = origin
        appState.locationConfidence = .high
        appState.effectiveSpatialConfidence = .high
        appState.tmapArrivalRoutesBySpotID[spot.id] = route
        return (appState, spot)
    }
}
