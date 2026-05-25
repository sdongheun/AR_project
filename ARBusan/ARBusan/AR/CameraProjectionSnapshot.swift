import Foundation
import simd
import UIKit

struct CameraProjectionSnapshot: Equatable {
    let timestamp: TimeInterval
    let viewportWidth: Double
    let viewportHeight: Double
    let interfaceOrientation: String
    let trackingState: String
    let cameraTransformTranslation: SIMD3<Double>
    let viewMatrixColumnZ: SIMD4<Double>
    let projectionMatrixDiagonal: SIMD2<Double>
    let cameraTransform: simd_float4x4
    let viewMatrix: simd_float4x4
    let projectionMatrix: simd_float4x4

    var diagnosticText: String {
        let viewport = "\(Int(viewportWidth))x\(Int(viewportHeight))"
        let position = "pos x \(cameraTransformTranslation.x.formatted(.number.precision(.fractionLength(2)))) y \(cameraTransformTranslation.y.formatted(.number.precision(.fractionLength(2)))) z \(cameraTransformTranslation.z.formatted(.number.precision(.fractionLength(2))))"
        let viewZ = "view.z \(viewMatrixColumnZ.x.formatted(.number.precision(.fractionLength(2))))/\(viewMatrixColumnZ.y.formatted(.number.precision(.fractionLength(2))))/\(viewMatrixColumnZ.z.formatted(.number.precision(.fractionLength(2))))/\(viewMatrixColumnZ.w.formatted(.number.precision(.fractionLength(2))))"
        let projection = "proj diag \(projectionMatrixDiagonal.x.formatted(.number.precision(.fractionLength(2))))/\(projectionMatrixDiagonal.y.formatted(.number.precision(.fractionLength(2))))"
        return "matrix 수신 / \(viewport) / \(interfaceOrientation) / \(trackingState) / \(position) / \(viewZ) / \(projection)"
    }

    static func make(
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        viewportSize: CGSize,
        interfaceOrientation: UIInterfaceOrientation,
        trackingStateDescription: String
    ) -> CameraProjectionSnapshot {
        CameraProjectionSnapshot(
            timestamp: timestamp,
            viewportWidth: Double(viewportSize.width),
            viewportHeight: Double(viewportSize.height),
            interfaceOrientation: interfaceOrientation.debugName,
            trackingState: trackingStateDescription,
            cameraTransformTranslation: SIMD3<Double>(
                Double(cameraTransform.columns.3.x),
                Double(cameraTransform.columns.3.y),
                Double(cameraTransform.columns.3.z)
            ),
            viewMatrixColumnZ: SIMD4<Double>(
                Double(viewMatrix.columns.2.x),
                Double(viewMatrix.columns.2.y),
                Double(viewMatrix.columns.2.z),
                Double(viewMatrix.columns.2.w)
            ),
            projectionMatrixDiagonal: SIMD2<Double>(
                Double(projectionMatrix.columns.0.x),
                Double(projectionMatrix.columns.1.y)
            ),
            cameraTransform: cameraTransform,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )
    }

    static func == (lhs: CameraProjectionSnapshot, rhs: CameraProjectionSnapshot) -> Bool {
        lhs.timestamp == rhs.timestamp
            && lhs.viewportWidth == rhs.viewportWidth
            && lhs.viewportHeight == rhs.viewportHeight
            && lhs.interfaceOrientation == rhs.interfaceOrientation
            && lhs.trackingState == rhs.trackingState
            && lhs.cameraTransformTranslation == rhs.cameraTransformTranslation
            && lhs.viewMatrixColumnZ == rhs.viewMatrixColumnZ
            && lhs.projectionMatrixDiagonal == rhs.projectionMatrixDiagonal
            && lhs.cameraTransform.isApproximatelyEqual(to: rhs.cameraTransform)
            && lhs.viewMatrix.isApproximatelyEqual(to: rhs.viewMatrix)
            && lhs.projectionMatrix.isApproximatelyEqual(to: rhs.projectionMatrix)
    }
}

extension CameraProjectionSnapshot {
    init(
        timestamp: TimeInterval,
        viewportWidth: Double,
        viewportHeight: Double,
        interfaceOrientation: String,
        trackingState: String,
        cameraTransformTranslation: SIMD3<Double>,
        viewMatrixColumnZ: SIMD4<Double>,
        projectionMatrixDiagonal: SIMD2<Double>
    ) {
        self.timestamp = timestamp
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.interfaceOrientation = interfaceOrientation
        self.trackingState = trackingState
        self.cameraTransformTranslation = cameraTransformTranslation
        self.viewMatrixColumnZ = viewMatrixColumnZ
        self.projectionMatrixDiagonal = projectionMatrixDiagonal
        self.cameraTransform = matrix_identity_float4x4
        self.viewMatrix = matrix_identity_float4x4
        self.projectionMatrix = matrix_identity_float4x4
    }
}

private extension simd_float4x4 {
    func isApproximatelyEqual(to other: simd_float4x4, tolerance: Float = 0.0001) -> Bool {
        columns.0.isApproximatelyEqual(to: other.columns.0, tolerance: tolerance)
            && columns.1.isApproximatelyEqual(to: other.columns.1, tolerance: tolerance)
            && columns.2.isApproximatelyEqual(to: other.columns.2, tolerance: tolerance)
            && columns.3.isApproximatelyEqual(to: other.columns.3, tolerance: tolerance)
    }
}

private extension SIMD4<Float> {
    func isApproximatelyEqual(to other: SIMD4<Float>, tolerance: Float) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(z - other.z) <= tolerance
            && abs(w - other.w) <= tolerance
    }
}

extension UIInterfaceOrientation {
    var debugName: String {
        switch self {
        case .portrait:
            return "portrait"
        case .portraitUpsideDown:
            return "portraitUpsideDown"
        case .landscapeLeft:
            return "landscapeLeft"
        case .landscapeRight:
            return "landscapeRight"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
}
