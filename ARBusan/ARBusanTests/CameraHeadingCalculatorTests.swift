import simd
import XCTest
@testable import ARBusan

final class CameraHeadingCalculatorTests: XCTestCase {
    func testHeadingIsZeroWhenCameraFacesNorth() {
        let transform = makeCameraTransform(forForwardX: 0, forwardZ: -1)

        let heading = CameraHeadingCalculator.compassHeadingDegrees(from: transform)

        XCTAssertEqual(heading, 0, accuracy: 0.0001)
    }

    func testHeadingIsNinetyWhenCameraFacesEast() {
        let transform = makeCameraTransform(forForwardX: 1, forwardZ: 0)

        let heading = CameraHeadingCalculator.compassHeadingDegrees(from: transform)

        XCTAssertEqual(heading, 90, accuracy: 0.0001)
    }

    func testHeadingIsOneEightyWhenCameraFacesSouth() {
        let transform = makeCameraTransform(forForwardX: 0, forwardZ: 1)

        let heading = CameraHeadingCalculator.compassHeadingDegrees(from: transform)

        XCTAssertEqual(heading, 180, accuracy: 0.0001)
    }

    func testHeadingIsTwoSeventyWhenCameraFacesWest() {
        let transform = makeCameraTransform(forForwardX: -1, forwardZ: 0)

        let heading = CameraHeadingCalculator.compassHeadingDegrees(from: transform)

        XCTAssertEqual(heading, 270, accuracy: 0.0001)
    }

    func testPoseSnapshotIncludesEulerAnglesAndPosition() {
        var transform = makeCameraTransform(forForwardX: 1, forwardZ: 0)
        transform.columns.3 = SIMD4<Float>(1.5, 2.5, -3.5, 1)

        let pose = CameraHeadingCalculator.poseSnapshot(
            from: transform,
            eulerAngles: SIMD3<Float>(Float.pi / 6, Float.pi / 4, -Float.pi / 8),
            timestamp: 12.5
        )

        XCTAssertEqual(pose.headingDegrees, 90, accuracy: 0.0001)
        XCTAssertEqual(pose.pitchDegrees, 30, accuracy: 0.0001)
        XCTAssertEqual(pose.yawDegrees, 45, accuracy: 0.0001)
        XCTAssertEqual(pose.rollDegrees, -22.5, accuracy: 0.0001)
        XCTAssertEqual(pose.positionX, 1.5, accuracy: 0.0001)
        XCTAssertEqual(pose.positionY, 2.5, accuracy: 0.0001)
        XCTAssertEqual(pose.positionZ, -3.5, accuracy: 0.0001)
        XCTAssertEqual(pose.timestamp, 12.5, accuracy: 0.0001)
    }

    private func makeCameraTransform(forForwardX forwardX: Float, forwardZ: Float) -> simd_float4x4 {
        var transform = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        transform.columns.2 = SIMD4<Float>(-forwardX, 0, -forwardZ, 0)
        return transform
    }
}
