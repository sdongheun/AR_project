import CoreLocation
import XCTest
@testable import ARBusan

final class LocalENUProjectorTests: XCTestCase {
    func testProjectingNorthKeepsEastNearZero() {
        let origin = LocationSnapshot(
            latitude: 35,
            longitude: 128,
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 2,
            heading: nil,
            headingAccuracy: nil,
            source: .coreLocation,
            capturedAt: Date()
        )
        let destination = CLLocationCoordinate2D(latitude: 35.0001, longitude: 128)

        let projected = LocalENUProjector.project(destination, from: origin)

        XCTAssertEqual(projected.eastMeters, 0, accuracy: 0.01)
        XCTAssertGreaterThan(projected.northMeters, 0)
        XCTAssertEqual(projected.bearingDegrees, 0, accuracy: 0.01)
    }

    func testProjectingEastProducesPositiveEastAndEastBearing() {
        let origin = LocationSnapshot(
            latitude: 35,
            longitude: 128,
            altitude: nil,
            horizontalAccuracy: 5,
            verticalAccuracy: nil,
            heading: nil,
            headingAccuracy: nil,
            source: .coreLocation,
            capturedAt: Date()
        )
        let destination = CLLocationCoordinate2D(latitude: 35, longitude: 128.0001)

        let projected = LocalENUProjector.project(destination, from: origin)

        XCTAssertGreaterThan(projected.eastMeters, 0)
        XCTAssertEqual(projected.northMeters, 0, accuracy: 0.01)
        XCTAssertEqual(projected.bearingDegrees, 90, accuracy: 0.01)
    }
}
