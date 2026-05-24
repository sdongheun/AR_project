import Foundation
import simd

enum CameraHeadingCalculator {
    static func compassHeadingDegrees(from transform: simd_float4x4) -> Double {
        let forwardX = Double(-transform.columns.2.x)
        let forwardZ = Double(-transform.columns.2.z)
        let heading = atan2(forwardX, -forwardZ) * 180 / .pi
        return heading >= 0 ? heading : heading + 360
    }
}
