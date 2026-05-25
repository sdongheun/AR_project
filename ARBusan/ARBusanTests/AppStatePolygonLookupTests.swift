import CoreLocation
import XCTest
@testable import ARBusan

@MainActor
final class AppStatePolygonLookupTests: XCTestCase {
    func testLookingAtMockBuildingFetchesAndStoresBuildingPolygon() async throws {
        let vworldClient = CapturingVWorldClient(result: .polygon)
        let appState = AppState(vworldClient: vworldClient)
        let target = MockTourismSpots.gimhae[0]

        publishLocation(
            latitude: target.center.latitude,
            longitude: target.center.longitude - 0.00030,
            to: appState
        )
        await waitUntil { appState.latestLocationSnapshot != nil }

        appState.updateCameraHeading(90)

        await waitUntil {
            appState.buildingPolygonsBySpotID[target.id] != nil
        }

        XCTAssertEqual(appState.cameraDirectionSpotID, target.id)
        XCTAssertEqual(appState.polygonValidatedSpotID, target.id)
        XCTAssertNotNil(appState.polygonLookupStartedAt)
        XCTAssertNotNil(appState.polygonLookupFinishedAt)
        XCTAssertEqual(vworldClient.requestedSpotIDs, [target.id])

        let polygon = try XCTUnwrap(appState.buildingPolygonsBySpotID[target.id])
        XCTAssertEqual(polygon.vertexCount, 5)
        XCTAssertEqual(polygon.sourceLayer, "test-vworld")
        XCTAssertTrue(appState.polygonValidationStatus.contains("브이월드 Polygon 확보"))
    }

    func testNoCameraDirectionCandidateDoesNotRequestVWorldPolygon() async {
        let vworldClient = CapturingVWorldClient(result: .polygon)
        let appState = AppState(vworldClient: vworldClient)
        let target = MockTourismSpots.gimhae[0]

        publishLocation(
            latitude: target.center.latitude,
            longitude: target.center.longitude - 0.00030,
            to: appState
        )
        await waitUntil { appState.latestLocationSnapshot != nil }

        appState.updateCameraHeading(270)

        await waitUntil {
            appState.polygonValidationStatus == "카메라 시야 방향과 일치하는 목업 Polygon 후보가 없습니다."
        }

        XCTAssertNil(appState.cameraDirectionSpotID)
        XCTAssertNil(appState.polygonValidatedSpotID)
        XCTAssertTrue(vworldClient.requestedSpotIDs.isEmpty)
    }

    func testCompletedEmptyVWorldResponseUpdatesStatusFromLoadingToNotFound() async {
        let vworldClient = CapturingVWorldClient(result: .empty)
        let appState = AppState(vworldClient: vworldClient)
        let target = MockTourismSpots.gimhae[0]

        publishLocation(
            latitude: target.center.latitude,
            longitude: target.center.longitude - 0.00030,
            to: appState
        )
        await waitUntil { appState.latestLocationSnapshot != nil }

        appState.updateCameraHeading(90)

        await waitUntil {
            appState.polygonValidationStatus.contains("찾지 못했습니다")
        }

        XCTAssertEqual(vworldClient.requestedSpotIDs, [target.id])
        XCTAssertNil(appState.polygonValidatedSpotID)
        XCTAssertNotNil(appState.polygonLookupStartedAt)
        XCTAssertNotNil(appState.polygonLookupFinishedAt)
    }

    func testCompletedVWorldErrorUpdatesStatusFromLoadingToFailure() async {
        let vworldClient = CapturingVWorldClient(result: .failure(TestVWorldError.responseFinishedWithError))
        let appState = AppState(vworldClient: vworldClient)
        let target = MockTourismSpots.gimhae[0]

        publishLocation(
            latitude: target.center.latitude,
            longitude: target.center.longitude - 0.00030,
            to: appState
        )
        await waitUntil { appState.latestLocationSnapshot != nil }

        appState.updateCameraHeading(90)

        await waitUntil {
            appState.polygonValidationStatus.contains("조회 실패")
        }

        XCTAssertEqual(vworldClient.requestedSpotIDs, [target.id])
        XCTAssertNil(appState.polygonValidatedSpotID)
        XCTAssertNotNil(appState.polygonLookupStartedAt)
        XCTAssertNotNil(appState.polygonLookupFinishedAt)
    }

    func testSlowVWorldResponseRemainsLoadingUntilRequestFinishes() async {
        let vworldClient = CapturingVWorldClient(result: .delayedPolygon(nanoseconds: 300_000_000))
        let appState = AppState(vworldClient: vworldClient)
        let target = MockTourismSpots.gimhae[0]

        publishLocation(
            latitude: target.center.latitude,
            longitude: target.center.longitude - 0.00030,
            to: appState
        )
        await waitUntil { appState.latestLocationSnapshot != nil }

        appState.updateCameraHeading(90)

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(appState.polygonValidationStatus.contains("조회 중입니다"))
        XCTAssertNotNil(appState.polygonLookupStartedAt)
        XCTAssertNil(appState.polygonLookupFinishedAt)

        await waitUntil {
            appState.polygonValidationStatus.contains("Polygon 확보")
        }

        XCTAssertNotNil(appState.polygonLookupFinishedAt)
    }

    func testRepeatedHeadingUpdatesDoNotRestartSamePolygonLookup() async {
        let vworldClient = CapturingVWorldClient(result: .delayedPolygon(nanoseconds: 300_000_000))
        let appState = AppState(vworldClient: vworldClient)
        let target = MockTourismSpots.gimhae[0]

        publishLocation(
            latitude: target.center.latitude,
            longitude: target.center.longitude - 0.00030,
            to: appState
        )
        await waitUntil { appState.latestLocationSnapshot != nil }

        appState.updateCameraHeading(90)
        appState.updateCameraHeading(91)
        appState.updateCameraHeading(89)
        appState.updateCameraHeading(90)

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vworldClient.requestedSpotIDs, [target.id])
        XCTAssertEqual(appState.polygonLookupLogs.filter { $0.contains("Polygon 조회 시작") }.count, 1)

        await waitUntil {
            appState.polygonValidationStatus.contains("Polygon 확보")
        }

        XCTAssertEqual(vworldClient.requestedSpotIDs, [target.id])
    }

    func testPolygonProjectionDiagnosticsReportsViewIntersection() async {
        let vworldClient = CapturingVWorldClient(result: .polygon)
        let appState = AppState(vworldClient: vworldClient)
        let target = MockTourismSpots.gimhae[0]

        publishLocation(
            latitude: target.center.latitude,
            longitude: target.center.longitude - 0.00030,
            to: appState
        )
        await waitUntil { appState.latestLocationSnapshot != nil }

        appState.updateCameraPose(
            CameraPoseSnapshot(
                headingDegrees: 90,
                pitchDegrees: 0,
                yawDegrees: 0,
                rollDegrees: 0,
                positionX: 0,
                positionY: 0,
                positionZ: 0,
                timestamp: 1
            )
        )

        await waitUntil {
            appState.polygonProjectionDiagnostics.contains("시야 교차")
        }

        XCTAssertTrue(appState.polygonProjectionDiagnostics.contains("화면 안 외곽점"))
    }

    private func publishLocation(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        to appState: AppState
    ) {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        appState.geospatialSessionManager.locationManager(CLLocationManager(), didUpdateLocations: [location])
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class CapturingVWorldClient: VWorldClient {
    enum Result {
        case polygon
        case delayedPolygon(nanoseconds: UInt64)
        case empty
        case failure(Error)
    }

    private let result: Result
    private(set) var requestedSpotIDs: [TourismSpot.ID] = []

    init(result: Result) {
        self.result = result
    }

    func validatePolygon(for spot: TourismSpot) async throws -> Bool {
        try await fetchBuildingPolygon(for: spot) != nil
    }

    func fetchBuildingPolygon(for spot: TourismSpot) async throws -> BuildingPolygon? {
        requestedSpotIDs.append(spot.id)

        switch result {
        case .polygon:
            break
        case let .delayedPolygon(nanoseconds):
            try await Task.sleep(nanoseconds: nanoseconds)
        case .empty:
            return nil
        case let .failure(error):
            throw error
        }

        let offset = 0.00005
        let center = spot.center
        return BuildingPolygon(
            spotID: spot.id,
            rings: [[
                CLLocationCoordinate2D(latitude: center.latitude - offset, longitude: center.longitude - offset),
                CLLocationCoordinate2D(latitude: center.latitude - offset, longitude: center.longitude + offset),
                CLLocationCoordinate2D(latitude: center.latitude + offset, longitude: center.longitude + offset),
                CLLocationCoordinate2D(latitude: center.latitude + offset, longitude: center.longitude - offset),
                CLLocationCoordinate2D(latitude: center.latitude - offset, longitude: center.longitude - offset),
            ]],
            sourceLayer: "test-vworld",
            buildingName: spot.name,
            heightMeters: nil,
            groundFloorCount: nil,
            sourceProperties: [:]
        )
    }
}

private enum TestVWorldError: LocalizedError {
    case responseFinishedWithError

    var errorDescription: String? {
        "테스트 브이월드 응답 에러"
    }
}
