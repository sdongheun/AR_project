import XCTest
@testable import ARBusan

@MainActor
final class AppStateHeadingDiagnosticsTests: XCTestCase {
    func testCameraHeadingUpdatesDiagnosticsForRealtimeDeviceCheck() {
        let appState = AppState()

        appState.updateCameraHeading(10)

        XCTAssertEqual(appState.cameraHeadingDegrees, 10)
        XCTAssertEqual(appState.cameraHeadingSampleCount, 1)
        XCTAssertNil(appState.cameraHeadingDeltaDegrees)
        XCTAssertNotNil(appState.cameraHeadingLastUpdatedAt)
        XCTAssertTrue(appState.cameraHeadingDiagnostics.contains("첫 heading 수신"))

        appState.updateCameraHeading(25)

        XCTAssertEqual(appState.cameraHeadingDegrees, 25)
        XCTAssertEqual(appState.cameraHeadingSampleCount, 2)
        XCTAssertEqual(try XCTUnwrap(appState.cameraHeadingDeltaDegrees), 15, accuracy: 0.0001)
        XCTAssertTrue(appState.cameraHeadingDiagnostics.contains("실시간 heading 수신 중"))
        XCTAssertTrue(appState.cameraHeadingDiagnostics.contains("샘플 2개"))
    }

    func testCameraHeadingDeltaUsesShortestAngularDifference() {
        let appState = AppState()

        appState.updateCameraHeading(350)
        appState.updateCameraHeading(10)

        XCTAssertEqual(try XCTUnwrap(appState.cameraHeadingDeltaDegrees), 20, accuracy: 0.0001)
    }

    func testUnstableHeadingDowngradesEffectiveSpatialConfidence() {
        let appState = AppState()

        appState.updateCameraHeading(10)
        appState.updateCameraHeading(35)

        XCTAssertEqual(appState.locationConfidence, .high)
        XCTAssertEqual(appState.effectiveSpatialConfidence, .medium)
        XCTAssertTrue(appState.spatialTrackingDiagnostics.contains("heading 불안정"))
    }

    func testCameraPoseUpdatesHeadingAndPoseDiagnostics() {
        let appState = AppState()
        let pose = CameraPoseSnapshot(
            headingDegrees: 120,
            pitchDegrees: 10,
            yawDegrees: 20,
            rollDegrees: -5,
            positionX: 1,
            positionY: 2,
            positionZ: 3,
            timestamp: 1
        )

        appState.updateCameraPose(pose)

        XCTAssertEqual(appState.cameraHeadingDegrees, 120)
        XCTAssertEqual(appState.cameraPoseSnapshot, pose)
        XCTAssertTrue(appState.cameraPoseDiagnostics.contains("pitch 10도"))
        XCTAssertTrue(appState.cameraPoseDiagnostics.contains("roll -5도"))
    }
}
