import Foundation
import simd

// 주행 방향 앵커링 (AR_NAVIGATION_LOGIC_PLAN.md 3.10 앵커링 규칙).
//
// 3D 안내 오브젝트는 카메라 시선(pitch/yaw)을 따라가면 안 된다. 사용자가 바닥을 보거나
// 두리번거리며 걸으면 시선을 따라 엉뚱한 곳에 뜨기 때문이다. 대신 카메라의 "월드 위치"와
// "휴대폰 높이"만 취하고, 오브젝트를 "내가 가는 방향(경로/목적지 방위)" 전방에 둔다.
//
// 전제: ARWorldTrackingConfiguration.worldAlignment == .gravityAndHeading.
// 이때 AR 월드 좌표축은 +X = 동, +Y = 위(중력 반대), -Z = 진북에 정렬된다.
// 따라서 지리 방위 θ(0=북, 90=동)의 전방 단위벡터는 (sinθ, 0, -cosθ) 이다.
//
// 카메라 transform에서는 위치만 쓰고 회전은 쓰지 않으므로, 화면을 위/아래로 기울여도
// 오브젝트는 가는 방향·기기 높이에 그대로 유지된다.
enum TravelDirectionAnchor {
    /// 지리 방위(도)를 AR 월드 전방 단위벡터로 변환한다. (+X 동, -Z 북)
    static func worldForward(bearingDegrees: Double) -> SIMD3<Float> {
        let radians = Float(bearingDegrees * .pi / 180)
        return SIMD3<Float>(sin(radians), 0, -cos(radians))
    }

    /// 카메라 월드 위치 기준으로, 방위 전방 `distanceMeters`, 높이 `cameraY + heightOffset`에 둘 월드 좌표.
    /// 카메라의 수평 위치와 높이만 사용하고 회전은 사용하지 않는다.
    static func worldPosition(
        cameraWorldPosition: SIMD3<Float>,
        bearingDegrees: Double,
        distanceMeters: Float,
        heightOffsetMeters: Float
    ) -> SIMD3<Float> {
        let forward = worldForward(bearingDegrees: bearingDegrees)
        return SIMD3<Float>(
            cameraWorldPosition.x + forward.x * distanceMeters,
            cameraWorldPosition.y + heightOffsetMeters,
            cameraWorldPosition.z + forward.z * distanceMeters
        )
    }

    /// 엔티티의 정면(-Z)을 방위 전방으로 돌리는 yaw 회전(중력 정렬, pitch/roll = 0).
    /// 방향성이 있는 오브젝트(리본/화살표)용. 축대칭 오브젝트(핀)는 필요 없다.
    static func orientation(bearingDegrees: Double) -> simd_quatf {
        let yaw = Float(-bearingDegrees * .pi / 180)
        return simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }
}
