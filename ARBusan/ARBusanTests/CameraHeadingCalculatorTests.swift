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

    private func makeCameraTransform(forForwardX forwardX: Float, forwardZ: Float) -> simd_float4x4 {
        var transform = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        transform.columns.2 = SIMD4<Float>(-forwardX, 0, -forwardZ, 0)
        return transform
    }
}
