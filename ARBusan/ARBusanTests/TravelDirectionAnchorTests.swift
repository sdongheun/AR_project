import simd
import XCTest
@testable import ARBusan

final class TravelDirectionAnchorTests: XCTestCase {
    func testWorldForwardMapsBearingToGravityAndHeadingAxes() {
        // .gravityAndHeading: +X 동, -Z 북.
        let north = TravelDirectionAnchor.worldForward(bearingDegrees: 0)
        XCTAssertEqual(north.x, 0, accuracy: 1e-5)
        XCTAssertEqual(north.z, -1, accuracy: 1e-5)

        let east = TravelDirectionAnchor.worldForward(bearingDegrees: 90)
        XCTAssertEqual(east.x, 1, accuracy: 1e-5)
        XCTAssertEqual(east.z, 0, accuracy: 1e-5)

        let south = TravelDirectionAnchor.worldForward(bearingDegrees: 180)
        XCTAssertEqual(south.z, 1, accuracy: 1e-5)

        let west = TravelDirectionAnchor.worldForward(bearingDegrees: 270)
        XCTAssertEqual(west.x, -1, accuracy: 1e-5)
    }

    func testWorldPositionUsesCameraPositionAndHeight() {
        let camera = SIMD3<Float>(0, 1.4, 0)
        // 동쪽 5m, 높이 그대로
        let east = TravelDirectionAnchor.worldPosition(
            cameraWorldPosition: camera,
            bearingDegrees: 90,
            distanceMeters: 5,
            heightOffsetMeters: 0
        )
        XCTAssertEqual(east.x, 5, accuracy: 1e-4)
        XCTAssertEqual(east.y, 1.4, accuracy: 1e-4)
        XCTAssertEqual(east.z, 0, accuracy: 1e-4)

        // 높이 오프셋 반영
        let lowered = TravelDirectionAnchor.worldPosition(
            cameraWorldPosition: camera,
            bearingDegrees: 0,
            distanceMeters: 3,
            heightOffsetMeters: -0.3
        )
        XCTAssertEqual(lowered.y, 1.1, accuracy: 1e-4)
        XCTAssertEqual(lowered.z, -3, accuracy: 1e-4)
    }

    func testOrientationFacesAlongBearingUpright() {
        // 엔티티 정면 -Z를 방위 90도(동)로 돌리면 +X를 향해야 한다.
        let q = TravelDirectionAnchor.orientation(bearingDegrees: 90)
        let facing = q.act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(facing.x, 1, accuracy: 1e-5)
        XCTAssertEqual(facing.y, 0, accuracy: 1e-5)
        XCTAssertEqual(facing.z, 0, accuracy: 1e-5)
    }
}
