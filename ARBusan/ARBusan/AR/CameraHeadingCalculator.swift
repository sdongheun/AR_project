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

/// ARCore VPS 지오공간 포즈에서 나침반 heading을 구한다.
/// VPS heading은 자기장 간섭에 면역인 절대 북 기준 → §4-C 북 보정·리본 방향의 신뢰 소스가 된다.
enum GeospatialHeading {
    /// `eastUpSouthQTarget`(target→East-Up-South 회전)에서 나침반 heading(북 0°, 동 90°)을 계산한다.
    /// 카메라 전방(-Z)을 EUS로 회전한 뒤 East/North 평면에 투영. 기기를 세워 들었을 때 yaw와 같고,
    /// 바닥/하늘을 향하면(전방이 수직) 부정확해지므로 호출부에서 `orientationYawAccuracy`로 게이팅한다.
    static func headingDegrees(eastUpSouthQTarget quaternion: simd_quatf) -> Double {
        let forwardEUS = quaternion.act(SIMD3<Float>(0, 0, -1))
        let east = Double(forwardEUS.x)
        let south = Double(forwardEUS.z)
        let heading = atan2(east, -south) * 180 / .pi
        return heading >= 0 ? heading : heading + 360
    }
}

private extension Double {
    var radiansToDegrees: Double {
        self * 180 / .pi
    }
}
