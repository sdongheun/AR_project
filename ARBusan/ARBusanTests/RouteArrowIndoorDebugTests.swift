import CoreLocation
import XCTest
@testable import ARBusan

@MainActor
final class RouteArrowIndoorDebugTests: XCTestCase {
    func testRightTurnArrowAppearsInsideTurnBoundaryWhenHeadingIsNotAligned() throws {
        let fixture = makeRightTurnFixture(originNorthOffsetMeters: -5)

        fixture.appState.updateCameraHeading(0)

        let path = try XCTUnwrap(fixture.appState.routeArrowPath)
        XCTAssertEqual(path.arrows.count, 1)
        XCTAssertEqual(path.arrows[0].turnDirection, .right)
        XCTAssertEqual(path.arrows[0].distanceFromOriginMeters, 5, accuracy: 0.8)
        XCTAssertTrue(fixture.appState.routeArrowDiagnostics.contains("전방 3D 대형 화살표"))
    }

    func testTurnArrowIsHiddenWhenHeadingAlreadyMatchesOutgoingRoute() {
        // 회전점 바로 앞(2m)에서 진행 방향(동쪽 90도)을 이미 향하고 있으면 화살표를 숨긴다.
        let fixture = makeRightTurnFixture(originNorthOffsetMeters: -2)

        fixture.appState.updateCameraHeading(90)

        XCTAssertNil(fixture.appState.routeArrowPath)
        XCTAssertTrue(fixture.appState.routeArrowComputationDiagnostics.contains("이미 방향 정렬"))
    }

    func testTurnArrowIsHiddenOutsideTurnBoundary() {
        let fixture = makeRightTurnFixture(originNorthOffsetMeters: -25)

        fixture.appState.updateCameraHeading(0)

        XCTAssertNil(fixture.appState.routeArrowPath)
        XCTAssertTrue(fixture.appState.routeArrowComputationDiagnostics.contains("boundary"))
    }

    func testTurnArrowAppearsForDenselySegmentedTurnRoute() throws {
        let fixture = makeSegmentedLeftTurnFixture()

        fixture.appState.updateCameraHeading(0)

        let path = try XCTUnwrap(fixture.appState.routeArrowPath)
        XCTAssertEqual(path.arrows.count, 1)
        XCTAssertEqual(path.arrows[0].turnDirection, .left)
        XCTAssertTrue(fixture.appState.routeArrowComputationDiagnostics.contains("전방 AR 화살표"))
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
