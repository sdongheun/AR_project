import CoreLocation
import XCTest
@testable import ARBusan

final class NavigationStabilizerTests: XCTestCase {
    private let base = CLLocationCoordinate2D(latitude: 35.245700, longitude: 128.904000)

    /// 기준점에서 동/북 미터만큼 떨어진 좌표(평면 근사). 테스트 지오메트리 구성용.
    private func offset(east: Double, north: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(base.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: base.latitude + north / metersPerDegreeLatitude,
            longitude: base.longitude + east / metersPerDegreeLongitude
        )
    }

    /// 북쪽으로 뻗는 직선 경로(동=0, 북 0~30m).
    private var northRoute: [CLLocationCoordinate2D] {
        [offset(east: 0, north: 0), offset(east: 0, north: 30)]
    }

    // MARK: - RouteGeometry

    func testClosestPointOnRouteReturnsPerpendicularDistance() throws {
        let point = offset(east: 5, north: 10)
        let result = try XCTUnwrap(RouteGeometry.closestPointOnRoute(from: point, routeCoordinates: northRoute))
        XCTAssertEqual(result.distanceMeters, 5, accuracy: 0.5)
        // 가장 가까운 점은 경로선(동=0) 위 북 10m 부근이어야 한다.
        XCTAssertEqual(result.coordinate.longitude, base.longitude, accuracy: 0.00002)
    }

    func testClosestPointClampsBeyondSegmentEnd() throws {
        // 경로 시작점보다 더 남쪽(북 -10m)인 점은 시작점으로 클램프된다.
        let point = offset(east: 0, north: -10)
        let result = try XCTUnwrap(RouteGeometry.closestPointOnRoute(from: point, routeCoordinates: northRoute))
        XCTAssertEqual(result.distanceMeters, 10, accuracy: 0.5)
    }

    func testTurnBoundaryReachedWidensWithAccuracyCircle() {
        // 오차 원(5m)이 boundary(18m)와 겹치면 회전 준비로 인정.
        XCTAssertTrue(RouteGeometry.turnBoundaryReached(distanceToTurnMeters: 20, accuracyRadiusMeters: 5, boundaryMeters: 18))
        // 오차 원이 없으면 boundary 밖.
        XCTAssertFalse(RouteGeometry.turnBoundaryReached(distanceToTurnMeters: 20, accuracyRadiusMeters: 0, boundaryMeters: 18))
    }

    // MARK: - NavigationGuidanceStabilizer (3.6)

    func testStabilizerStableWhenOnRouteWithGoodAccuracy() {
        var stabilizer = NavigationGuidanceStabilizer()
        let fix = stabilizer.stabilize(
            rawCoordinate: offset(east: 0, north: 10),
            accuracyRadiusMeters: 5,
            routeCoordinates: northRoute,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(fix.quality, .stable)
        XCTAssertFalse(fix.didSnapToRoute)
        XCTAssertTrue(fix.allowsTurnCommitment)
    }

    func testStabilizerSnapsWhenSlightlyOffRoute() {
        var stabilizer = NavigationGuidanceStabilizer()
        let fix = stabilizer.stabilize(
            rawCoordinate: offset(east: 10, north: 10),
            accuracyRadiusMeters: 5,
            routeCoordinates: northRoute,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(fix.quality, .snapped)
        XCTAssertTrue(fix.didSnapToRoute)
        // 스냅된 좌표는 경로선(동=0)에 가까워져야 한다.
        XCTAssertEqual(fix.coordinate.longitude, base.longitude, accuracy: 0.00002)
    }

    func testStabilizerUnstableWhenFarFromRoute() {
        var stabilizer = NavigationGuidanceStabilizer()
        let fix = stabilizer.stabilize(
            rawCoordinate: offset(east: 40, north: 10),
            accuracyRadiusMeters: 5,
            routeCoordinates: northRoute,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(fix.quality, .unstable)
        XCTAssertFalse(fix.didSnapToRoute)
        XCTAssertFalse(fix.allowsTurnCommitment)
    }

    func testStabilizerUnstableWhenAccuracyPoor() {
        var stabilizer = NavigationGuidanceStabilizer()
        let fix = stabilizer.stabilize(
            rawCoordinate: offset(east: 0, north: 10),
            accuracyRadiusMeters: 30,
            routeCoordinates: northRoute,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(fix.quality, .unstable)
    }

    func testStabilizerHoldsLastStableOnSuddenJumpThenAcceptsAfterWindow() {
        var stabilizer = NavigationGuidanceStabilizer()
        let start = Date(timeIntervalSince1970: 0)

        // 1) 첫 안정 위치 확정.
        let first = stabilizer.stabilize(
            rawCoordinate: offset(east: 0, north: 5),
            accuracyRadiusMeters: 5,
            routeCoordinates: northRoute,
            now: start
        )
        XCTAssertEqual(first.quality, .stable)

        // 2) 1초 뒤 25m 점프 -> 유지 시간(2초) 이내라 직전 위치를 유지.
        let jumped = stabilizer.stabilize(
            rawCoordinate: offset(east: 25, north: 5),
            accuracyRadiusMeters: 5,
            routeCoordinates: northRoute,
            now: start.addingTimeInterval(1)
        )
        XCTAssertEqual(jumped.quality, .held)
        XCTAssertEqual(jumped.coordinate.latitude, first.coordinate.latitude, accuracy: 0.0000001)
        XCTAssertEqual(jumped.coordinate.longitude, first.coordinate.longitude, accuracy: 0.0000001)

        // 3) 유지 시간이 지나면 새 위치를 받아들인다.
        let accepted = stabilizer.stabilize(
            rawCoordinate: offset(east: 25, north: 5),
            accuracyRadiusMeters: 5,
            routeCoordinates: northRoute,
            now: start.addingTimeInterval(3.5)
        )
        XCTAssertNotEqual(accepted.quality, .held)
    }

    // MARK: - MovementDirectionTracker (3.7)

    func testMovementTrackerEstimatesBearingAfterStep() {
        var tracker = MovementDirectionTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        tracker.update(coordinate: offset(east: 0, north: 0), now: t0)
        XCTAssertNil(tracker.movementBearingDegrees)

        // 북쪽으로 3m 이동 -> 이동 방향 약 0도(북), 걷는 중.
        tracker.update(coordinate: offset(east: 0, north: 3), now: t0.addingTimeInterval(1))
        let bearing = try? XCTUnwrap(tracker.movementBearingDegrees)
        XCTAssertEqual(bearing ?? -1, 0, accuracy: 3)
        XCTAssertTrue(tracker.isWalking(now: t0.addingTimeInterval(1)))
        // 4초 넘게 지나면 더 이상 걷는 중으로 보지 않는다.
        XCTAssertFalse(tracker.isWalking(now: t0.addingTimeInterval(6)))
    }

    func testMovementTrackerIgnoresTinyJitter() {
        var tracker = MovementDirectionTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        tracker.update(coordinate: offset(east: 0, north: 0), now: t0)
        // 0.5m 미세 이동은 무시(잡음).
        tracker.update(coordinate: offset(east: 0, north: 0.5), now: t0.addingTimeInterval(1))
        XCTAssertNil(tracker.movementBearingDegrees)
    }

    // MARK: - HeadingGuidance (3.7)

    func testFacingPrefersMovementDirectionWhenWalking() {
        let facing = HeadingGuidance.facingEstimate(
            compassHeadingDegrees: 200,
            compassDeltaDegrees: 40,
            movementBearingDegrees: 90,
            isWalking: true,
            instabilityThresholdDegrees: 12
        )
        XCTAssertEqual(facing.bearingDegrees, 90)
        XCTAssertTrue(facing.isConfident)
        XCTAssertTrue(facing.usedMovementDirection)
    }

    func testFacingUsesCompassWhenStableAndNotWalking() {
        let facing = HeadingGuidance.facingEstimate(
            compassHeadingDegrees: 45,
            compassDeltaDegrees: 5,
            movementBearingDegrees: nil,
            isWalking: false,
            instabilityThresholdDegrees: 12
        )
        XCTAssertEqual(facing.bearingDegrees, 45)
        XCTAssertTrue(facing.isConfident)
        XCTAssertFalse(facing.usedMovementDirection)
    }

    func testFacingNotConfidentWhenCompassUnstable() {
        let facing = HeadingGuidance.facingEstimate(
            compassHeadingDegrees: 45,
            compassDeltaDegrees: 30,
            movementBearingDegrees: nil,
            isWalking: false,
            instabilityThresholdDegrees: 12
        )
        XCTAssertFalse(facing.isConfident)
    }

    func testFacingNilWhenNoSignals() {
        let facing = HeadingGuidance.facingEstimate(
            compassHeadingDegrees: nil,
            compassDeltaDegrees: nil,
            movementBearingDegrees: nil,
            isWalking: false,
            instabilityThresholdDegrees: 12
        )
        XCTAssertNil(facing.bearingDegrees)
        XCTAssertFalse(facing.isConfident)
    }

    func testDirectionZoneMapping() {
        XCTAssertEqual(HeadingGuidance.zone(forSignedDeltaDegrees: 0), .straight)
        XCTAssertEqual(HeadingGuidance.zone(forSignedDeltaDegrees: 35), .slightRight)
        XCTAssertEqual(HeadingGuidance.zone(forSignedDeltaDegrees: 90), .right)
        XCTAssertEqual(HeadingGuidance.zone(forSignedDeltaDegrees: 150), .behindRight)
        XCTAssertEqual(HeadingGuidance.zone(forSignedDeltaDegrees: -35), .slightLeft)
        XCTAssertEqual(HeadingGuidance.zone(forSignedDeltaDegrees: -90), .left)
        XCTAssertEqual(HeadingGuidance.zone(forSignedDeltaDegrees: -150), .behindLeft)
    }
}
