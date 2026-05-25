import CoreLocation
import simd
import UIKit
import XCTest
@testable import ARBusan

final class CameraMatrixProjectorTests: XCTestCase {
    func testProjectingPointInFrontProducesCenterScreenPoint() {
        let origin = LocationSnapshot(
            latitude: 35,
            longitude: 128,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .coreLocation,
            capturedAt: Date()
        )
        let snapshot = CameraProjectionSnapshot.make(
            timestamp: 1,
            cameraTransform: matrix_identity_float4x4,
            viewMatrix: matrix_identity_float4x4,
            projectionMatrix: matrix_identity_float4x4,
            viewportSize: CGSize(width: 390, height: 844),
            interfaceOrientation: .portrait,
            trackingStateDescription: "normal"
        )
        let northCoordinate = CLLocationCoordinate2D(latitude: 35.0001, longitude: 128)

        let projected = CameraMatrixProjector.project(
            northCoordinate,
            from: origin,
            using: snapshot
        )

        XCTAssertNotNil(projected)
        XCTAssertEqual(try XCTUnwrap(projected).screenX, 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(projected).screenY, 0.5, accuracy: 0.001)
    }
}
