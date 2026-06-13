import CoreLocation
import XCTest
@testable import ARBusan

@MainActor
final class RouteArrowIndoorDebugTests: XCTestCase {
    func testFarDestinationShows2DOverlayNotPin() throws {
        // 멀면(>30m) 3D 핀 대신 2D 목적지 표시(라벨/가장자리 지시). 회전 화살표는 폐기되어 항상 nil.
        let fixture = makeStraightNorthRouteFixture(originDistanceMeters: 45)
        fixture.appState.updateCameraHeading(0)

        XCTAssertNil(fixture.appState.arrivalPin)
        XCTAssertNotNil(fixture.appState.navigationDestinationOverlay)
    }

    func testNearDestinationShows3DPinNotOverlay() throws {
        // 가까우면(≤30m, 도착 반경 밖) 3D 공간 고정 핀을 띄우고 2D 오버레이는 끈다.
        let fixture = makeStraightNorthRouteFixture(originDistanceMeters: 25)
        fixture.appState.updateCameraHeading(0)

        XCTAssertNotNil(fixture.appState.arrivalPin)
        XCTAssertNil(fixture.appState.navigationDestinationOverlay)
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
        XCTAssertTrue(appState.edgeMarkerOverlays.isEmpty)
        XCTAssertTrue(appState.navigationGuidanceIsArrivalNearby)
    }

    func testTrackingLimitedHidesDestinationGuidance() {
        // AR 트래킹이 불안정하면 3D 핀/2D 목적지 표시를 모두 끄고 보수 텍스트로 강등한다(§4-B).
        let fixture = makeRightTurnFixture(originNorthOffsetMeters: -5)
        fixture.appState.arTrackingLimited = true

        fixture.appState.updateCameraHeading(0)

        XCTAssertNil(fixture.appState.arrivalPin)
        XCTAssertNil(fixture.appState.navigationDestinationOverlay)
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
}
