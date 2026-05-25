import CoreLocation
import Foundation
import simd

struct CameraMatrixProjectedPoint: Equatable {
    let screenX: Double
    let screenY: Double
    let depth: Double
    let isInsideView: Bool
}

enum CameraMatrixProjector {
    static func project(
        _ coordinate: CLLocationCoordinate2D,
        altitude: CLLocationDistance? = nil,
        from origin: LocationSnapshot,
        using cameraSnapshot: CameraProjectionSnapshot
    ) -> CameraMatrixProjectedPoint? {
        let enu = LocalENUProjector.project(coordinate, altitude: altitude, from: origin)
        let cameraPosition = cameraSnapshot.cameraTransform.columns.3
        let worldPosition = SIMD4<Float>(
            cameraPosition.x + Float(enu.eastMeters),
            cameraPosition.y + Float(enu.upMeters),
            cameraPosition.z - Float(enu.northMeters),
            1
        )
        let clipPosition = cameraSnapshot.projectionMatrix * cameraSnapshot.viewMatrix * worldPosition

        guard clipPosition.w.isFinite, abs(clipPosition.w) > 0.0001 else {
            return nil
        }

        let ndc = SIMD3<Float>(
            clipPosition.x / clipPosition.w,
            clipPosition.y / clipPosition.w,
            clipPosition.z / clipPosition.w
        )
        guard ndc.x.isFinite, ndc.y.isFinite, ndc.z.isFinite else {
            return nil
        }

        let screenX = Double((ndc.x + 1) / 2)
        let screenY = Double((1 - ndc.y) / 2)
        let isInside = screenX >= 0 && screenX <= 1 && screenY >= 0 && screenY <= 1 && ndc.z >= -1 && ndc.z <= 1

        return CameraMatrixProjectedPoint(
            screenX: screenX,
            screenY: screenY,
            depth: Double(ndc.z),
            isInsideView: isInside
        )
    }
}
