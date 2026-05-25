import Foundation
import simd

struct CameraPoseSnapshot: Equatable {
    let headingDegrees: Double
    let pitchDegrees: Double
    let yawDegrees: Double
    let rollDegrees: Double
    let positionX: Double
    let positionY: Double
    let positionZ: Double
    let timestamp: TimeInterval
}

enum CameraHeadingCalculator {
    static func compassHeadingDegrees(from transform: simd_float4x4) -> Double {
        let forwardX = Double(-transform.columns.2.x)
        let forwardZ = Double(-transform.columns.2.z)
        let heading = atan2(forwardX, -forwardZ) * 180 / .pi
        return heading >= 0 ? heading : heading + 360
    }

    static func poseSnapshot(
        from transform: simd_float4x4,
        eulerAngles: simd_float3,
        timestamp: TimeInterval
    ) -> CameraPoseSnapshot {
        CameraPoseSnapshot(
            headingDegrees: compassHeadingDegrees(from: transform),
            pitchDegrees: Double(eulerAngles.x).radiansToDegrees,
            yawDegrees: Double(eulerAngles.y).radiansToDegrees,
            rollDegrees: Double(eulerAngles.z).radiansToDegrees,
            positionX: Double(transform.columns.3.x),
            positionY: Double(transform.columns.3.y),
            positionZ: Double(transform.columns.3.z),
            timestamp: timestamp
        )
    }
}

private extension Double {
    var radiansToDegrees: Double {
        self * 180 / .pi
    }
}
