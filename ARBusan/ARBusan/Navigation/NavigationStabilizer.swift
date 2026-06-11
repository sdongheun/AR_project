import CoreLocation
import Foundation

// 길찾기 안내의 위치/heading 불안정 대응 순수 로직.
//
// AR_NAVIGATION_LOGIC_PLAN.md 3.6(위치 불안정 대응), 3.7(heading 불안정 대응)을 구현한다.
// 이 파일은 AppState/UI/세션 매니저에 의존하지 않는 값 타입과 순수 함수만 둔다.
// 같은 로직을 실외 실측(실제 GPS) 경로와 실내 디버그(좌표 주입) 경로에서 똑같이 쓰고,
// 단위 테스트로 회귀를 막기 위함이다. 임계값은 모두 Config로 노출해 현장 튜닝을 쉽게 한다.

// MARK: - 경로선 기하

enum RouteGeometry {
    /// 경로 polyline에서 기준 좌표와 가장 가까운 점(선분 수직 투영)과 그 수직 거리(m)를 구한다.
    /// 좌표가 1개뿐이면 그 점까지의 거리를, 비어 있으면 nil을 반환한다.
    static func closestPointOnRoute(
        from coordinate: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> (coordinate: CLLocationCoordinate2D, distanceMeters: CLLocationDistance)? {
        guard let first = routeCoordinates.first else {
            return nil
        }
        guard routeCoordinates.count >= 2 else {
            return (first, planarDistanceMeters(coordinate, first))
        }

        let frame = PlanarFrame(reference: coordinate)
        var best: (coordinate: CLLocationCoordinate2D, distanceMeters: CLLocationDistance)?
        for index in 0..<(routeCoordinates.count - 1) {
            let projected = frame.projectOntoSegment(
                start: routeCoordinates[index],
                end: routeCoordinates[index + 1]
            )
            if best == nil || projected.distanceMeters < best!.distanceMeters {
                best = projected
            }
        }
        return best
    }

    /// 회전 지점까지의 거리가 오차 원을 고려할 때 turn boundary 안에 들어오는지 판단한다.
    /// 위치를 점 하나가 아니라 `현재 위치 + horizontalAccuracy` 오차 원으로 보고,
    /// 오차 원이 boundary와 겹치면 회전 준비 상태로 인정한다(3.6).
    static func turnBoundaryReached(
        distanceToTurnMeters: CLLocationDistance,
        accuracyRadiusMeters: CLLocationAccuracy,
        boundaryMeters: CLLocationDistance
    ) -> Bool {
        let radius = max(0, accuracyRadiusMeters)
        return (distanceToTurnMeters - radius) <= boundaryMeters
    }

    /// 곡선 리본(§3.2): 현재 위치 최근접점부터 전방으로 경로 폴리라인을 `spacing` 간격(arc-length)으로
    /// `maxLength`까지 재샘플한 좌표들. 도로의 휘는 정도가 이 점들에 그대로 담긴다.
    static func forwardRibbonSamples(
        from origin: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        spacingMeters: CLLocationDistance,
        maxLengthMeters: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard routeCoordinates.count >= 2, spacingMeters > 0, maxLengthMeters > 0 else {
            return []
        }

        // 1) 최근접 세그먼트와 그 위 투영점.
        var nearestSegment = 0
        var nearestPoint = routeCoordinates[0]
        var nearestDistance = Double.greatestFiniteMagnitude
        let frame = PlanarFrame(reference: origin)
        for index in 0..<(routeCoordinates.count - 1) {
            let projected = frame.projectOntoSegment(start: routeCoordinates[index], end: routeCoordinates[index + 1])
            if projected.distanceMeters < nearestDistance {
                nearestDistance = projected.distanceMeters
                nearestSegment = index
                nearestPoint = projected.coordinate
            }
        }

        // 2) 투영점부터 폴리라인을 따라 일정 간격으로 전진하며 샘플.
        var samples: [CLLocationCoordinate2D] = [nearestPoint]
        var cursor = nearestPoint
        var segmentIndex = nearestSegment
        var distanceToNextSample = spacingMeters
        var totalLength = 0.0

        while segmentIndex < routeCoordinates.count - 1, totalLength < maxLengthMeters {
            let segmentEnd = routeCoordinates[segmentIndex + 1]
            let segmentRemaining = planarDistanceMeters(cursor, segmentEnd)
            if segmentRemaining < 1e-6 {
                segmentIndex += 1
                cursor = segmentEnd
                continue
            }
            if segmentRemaining >= distanceToNextSample {
                let ratio = distanceToNextSample / segmentRemaining
                let sample = interpolateCoordinate(from: cursor, to: segmentEnd, ratio: ratio)
                samples.append(sample)
                totalLength += distanceToNextSample
                cursor = sample
                distanceToNextSample = spacingMeters
            } else {
                distanceToNextSample -= segmentRemaining
                totalLength += segmentRemaining
                cursor = segmentEnd
                segmentIndex += 1
            }
        }
        return samples
    }
}

// MARK: - 경로 이탈 자동 재탐색 (§4-A)

/// 자동 재탐색 판단. 오탐을 줄이기 위해 임계값/지속시간/쿨다운을 넉넉하게 둔다.
enum NavigationReroute {
    static func shouldAutoReroute(
        offRouteMeters: CLLocationDistance,
        offRouteSince: Date?,
        lastRerouteAt: Date?,
        now: Date,
        thresholdMeters: CLLocationDistance,
        sustainSeconds: TimeInterval,
        cooldownSeconds: TimeInterval
    ) -> Bool {
        guard offRouteMeters > thresholdMeters else {
            return false
        }
        guard let offRouteSince, now.timeIntervalSince(offRouteSince) >= sustainSeconds else {
            return false
        }
        if let lastRerouteAt, now.timeIntervalSince(lastRerouteAt) < cooldownSeconds {
            return false
        }
        return true
    }
}

// MARK: - 북 재보정 감지 (§4-C)

/// 세션 시작 시 `.gravityAndHeading`으로 고정한 월드 북이 틀어졌는지 판단한다(감지 전용).
/// 신뢰 가능한 나침반(절대 북)과 ARKit 월드 heading이 임계값 넘게 "지속" 발산하면 미스캘리브레이션으로 본다.
/// 실제 보정(세션 재실행)은 사용자가 수동으로 트리거한다.
enum NorthCalibration {
    static func shouldFlagMiscalibration(
        divergenceDegrees: Double,
        divergenceSince: Date?,
        compassAccuracyDegrees: Double,
        now: Date,
        thresholdDegrees: Double,
        sustainSeconds: TimeInterval,
        maxCompassAccuracyDegrees: Double
    ) -> Bool {
        // 나침반 자체가 못 믿을 정도(무효/정확도 나쁨)면 판단 보류 — 둘 다 틀리면 구분 불가.
        guard compassAccuracyDegrees >= 0, compassAccuracyDegrees <= maxCompassAccuracyDegrees else {
            return false
        }
        guard divergenceDegrees > thresholdDegrees else {
            return false
        }
        guard let divergenceSince, now.timeIntervalSince(divergenceSince) >= sustainSeconds else {
            return false
        }
        return true
    }
}

// MARK: - 3.6 위치 불안정 대응

/// 안내에 사용할 보정된 위치와 그 품질.
struct GuidanceFix {
    enum Quality: String {
        case stable   // 경로선 근처 + 정확도 양호: 원시 위치 그대로 사용
        case snapped  // 경로선에 스냅해서 안내
        case held     // 위치 튐 감지: 최근 안정 위치를 잠시 유지
        case unstable // 경로선에서 너무 멀거나 정확도가 나쁨: 보수적으로 표시

        var displayName: String {
            switch self {
            case .stable: return "안정"
            case .snapped: return "경로 스냅"
            case .held: return "위치 유지"
            case .unstable: return "위치 불안정"
            }
        }
    }

    let coordinate: CLLocationCoordinate2D
    let accuracyRadiusMeters: CLLocationAccuracy
    let offRouteDistanceMeters: CLLocationDistance?
    let quality: Quality
    let didSnapToRoute: Bool

    /// 좌/우 회전 안내를 확정해도 되는 상태인지. 불안정하면 보수적으로 처리한다.
    var allowsTurnCommitment: Bool {
        quality != .unstable && quality != .held
    }
}

/// 현재 위치를 오차 원으로 보고, 경로선 스냅과 위치 튐 유지를 적용해 안내용 위치를 만든다(3.6).
/// 직전 안정 위치/시각을 들고 있는 작은 상태 머신이며, 시간은 호출자가 주입한다(테스트 결정성).
struct NavigationGuidanceStabilizer {
    struct Config {
        /// 이 이내면 이미 경로 위로 보고 원시 위치를 그대로 쓴다.
        var onRouteDistanceMeters: CLLocationDistance = 4
        /// 이 거리까지는 경로선에 스냅한다. 넘으면 스냅하지 않고 불안정으로 본다.
        var maxSnapDistanceMeters: CLLocationDistance = 20
        /// 이 이상이면 정확도가 나빠 불안정으로 본다.
        var unstableAccuracyMeters: CLLocationAccuracy = 25
        /// 직전 안정 위치에서 이 이상 점프하면 튐 후보로 본다.
        var jumpHoldDistanceMeters: CLLocationDistance = 15
        /// 튐 후보를 이 시간 동안은 직전 안정 위치로 유지한다. 지나면 새 위치를 받는다.
        var jumpHoldDurationSeconds: TimeInterval = 2.0
    }

    var config = Config()
    private(set) var lastAcceptedCoordinate: CLLocationCoordinate2D?
    private(set) var lastAcceptedAt: Date?

    mutating func reset() {
        lastAcceptedCoordinate = nil
        lastAcceptedAt = nil
    }

    mutating func stabilize(
        rawCoordinate: CLLocationCoordinate2D,
        accuracyRadiusMeters: CLLocationAccuracy,
        routeCoordinates: [CLLocationCoordinate2D],
        now: Date
    ) -> GuidanceFix {
        let closest = RouteGeometry.closestPointOnRoute(from: rawCoordinate, routeCoordinates: routeCoordinates)
        let offRoute = closest?.distanceMeters

        // 1) 위치 튐 유지: 직전 안정 위치에서 크게 점프 + 유지 시간 이내면 직전 위치를 그대로 쓴다.
        if let last = lastAcceptedCoordinate, let lastAt = lastAcceptedAt {
            let jump = planarDistanceMeters(rawCoordinate, last)
            if jump > config.jumpHoldDistanceMeters,
               now.timeIntervalSince(lastAt) < config.jumpHoldDurationSeconds {
                return GuidanceFix(
                    coordinate: last,
                    accuracyRadiusMeters: accuracyRadiusMeters,
                    offRouteDistanceMeters: offRoute,
                    quality: .held,
                    didSnapToRoute: false
                )
            }
        }

        let accuracyPoor = accuracyRadiusMeters > config.unstableAccuracyMeters

        // 2) 경로선 스냅 판단
        guard let closest, let offRoute else {
            // 경로 좌표가 없으면 스냅할 기준선이 없다. 원시 위치를 쓰되 정확도만 반영한다.
            accept(rawCoordinate, at: now)
            return GuidanceFix(
                coordinate: rawCoordinate,
                accuracyRadiusMeters: accuracyRadiusMeters,
                offRouteDistanceMeters: nil,
                quality: accuracyPoor ? .unstable : .stable,
                didSnapToRoute: false
            )
        }

        if offRoute > config.maxSnapDistanceMeters {
            // 경로선에서 너무 멀다: 잘못 스냅하면 엉뚱한 안내가 되므로 스냅하지 않고 불안정으로 둔다.
            accept(rawCoordinate, at: now)
            return GuidanceFix(
                coordinate: rawCoordinate,
                accuracyRadiusMeters: accuracyRadiusMeters,
                offRouteDistanceMeters: offRoute,
                quality: .unstable,
                didSnapToRoute: false
            )
        }

        if offRoute <= config.onRouteDistanceMeters {
            accept(rawCoordinate, at: now)
            return GuidanceFix(
                coordinate: rawCoordinate,
                accuracyRadiusMeters: accuracyRadiusMeters,
                offRouteDistanceMeters: offRoute,
                quality: accuracyPoor ? .unstable : .stable,
                didSnapToRoute: false
            )
        }

        // 경로 근처지만 약간 벗어남: 경로선으로 스냅한다.
        accept(closest.coordinate, at: now)
        return GuidanceFix(
            coordinate: closest.coordinate,
            accuracyRadiusMeters: accuracyRadiusMeters,
            offRouteDistanceMeters: offRoute,
            quality: accuracyPoor ? .unstable : .snapped,
            didSnapToRoute: true
        )
    }

    private mutating func accept(_ coordinate: CLLocationCoordinate2D, at time: Date) {
        lastAcceptedCoordinate = coordinate
        lastAcceptedAt = time
    }
}

// MARK: - 3.7 이동 방향 추적

/// 최근 위치 변화에서 이동 방향(bearing)을 추정한다. 걷는 중이면 heading보다 이동 방향이 더 믿을 만하다.
struct MovementDirectionTracker {
    struct Config {
        /// 이 이상 움직였을 때만 이동 방향을 갱신한다(정지 시 잡음 무시).
        var minStepMeters: CLLocationDistance = 1.5
        /// 마지막 이동 이후 이 시간이 지나면 더 이상 걷는 중으로 보지 않는다.
        var staleSeconds: TimeInterval = 4.0
    }

    var config = Config()
    private var anchorCoordinate: CLLocationCoordinate2D?
    private(set) var movementBearingDegrees: Double?
    private(set) var lastMovedAt: Date?

    mutating func reset() {
        anchorCoordinate = nil
        movementBearingDegrees = nil
        lastMovedAt = nil
    }

    mutating func update(coordinate: CLLocationCoordinate2D, now: Date) {
        guard let anchor = anchorCoordinate else {
            anchorCoordinate = coordinate
            return
        }

        let step = planarDistanceMeters(coordinate, anchor)
        guard step >= config.minStepMeters else {
            return
        }

        movementBearingDegrees = planarBearingDegrees(from: anchor, to: coordinate)
        lastMovedAt = now
        anchorCoordinate = coordinate
    }

    func isWalking(now: Date) -> Bool {
        guard let lastMovedAt else {
            return false
        }
        return now.timeIntervalSince(lastMovedAt) <= config.staleSeconds
    }
}

// MARK: - 3.7 heading 융합 / 방향 구간

/// 사용자가 향한 방향 추정값과 그 신뢰 여부. heading 하나로 좌/우를 확정하지 않기 위함이다.
struct FacingEstimate {
    let bearingDegrees: Double?
    let isConfident: Bool
    let usedMovementDirection: Bool
}

/// 방향 안내 구간. 정밀 각도가 아니라 사람이 바로 행동할 수 있는 구간으로 표현한다(3.7).
enum DirectionZone: String {
    case straight
    case slightLeft
    case left
    case slightRight
    case right
    case behindLeft
    case behindRight
    case uncertain // heading/이동 방향이 불안정해 좌/우를 확정할 수 없음

    var title: String {
        switch self {
        case .straight: return "계속 직진하세요"
        case .slightLeft: return "왼쪽으로 살짝 이동"
        case .left: return "왼쪽으로 이동하세요"
        case .slightRight: return "오른쪽으로 살짝 이동"
        case .right: return "오른쪽으로 이동하세요"
        case .behindLeft: return "뒤쪽 왼편으로 돌아보세요"
        case .behindRight: return "뒤쪽 오른편으로 돌아보세요"
        case .uncertain: return "천천히 주변을 비춰 방향을 확인하세요"
        }
    }

    var systemImageName: String {
        switch self {
        case .straight: return "arrow.up"
        case .slightLeft, .left: return "arrow.left"
        case .slightRight, .right: return "arrow.right"
        case .behindLeft: return "arrow.uturn.left"
        case .behindRight: return "arrow.uturn.right"
        case .uncertain: return "viewfinder"
        }
    }

    var horizontalOffsetRatio: Double {
        switch self {
        case .straight, .uncertain: return 0
        case .slightLeft: return -0.16
        case .left: return -0.28
        case .slightRight: return 0.16
        case .right: return 0.28
        case .behindLeft: return -0.34
        case .behindRight: return 0.34
        }
    }
}

enum HeadingGuidance {
    /// 향한 방향을 추정한다. 걷는 중이면 이동 방향을, 아니면 나침반 heading을 쓰고,
    /// 나침반 변화량이 크면(불안정) 신뢰하지 않는다.
    static func facingEstimate(
        compassHeadingDegrees: Double?,
        compassDeltaDegrees: Double?,
        movementBearingDegrees: Double?,
        isWalking: Bool,
        instabilityThresholdDegrees: Double
    ) -> FacingEstimate {
        if isWalking, let movementBearingDegrees {
            return FacingEstimate(
                bearingDegrees: movementBearingDegrees,
                isConfident: true,
                usedMovementDirection: true
            )
        }

        if let compassHeadingDegrees {
            let isConfident = (compassDeltaDegrees ?? 0) <= instabilityThresholdDegrees
            return FacingEstimate(
                bearingDegrees: compassHeadingDegrees,
                isConfident: isConfident,
                usedMovementDirection: false
            )
        }

        return FacingEstimate(bearingDegrees: nil, isConfident: false, usedMovementDirection: false)
    }

    /// 향한 방향과 목표 방향의 부호 있는 각도 차이를 방향 구간으로 매핑한다.
    /// signedDelta는 향한 방향 기준 목표 방향이 오른쪽이면 양수, 왼쪽이면 음수다.
    static func zone(forSignedDeltaDegrees signedDelta: Double) -> DirectionZone {
        switch signedDelta {
        case ..<(-120):
            return .behindLeft
        case -120 ..< -55:
            return .left
        case -55 ..< -20:
            return .slightLeft
        case -20 ... 20:
            return .straight
        case 20 ... 55:
            return .slightRight
        case 55 ... 120:
            return .right
        default:
            return .behindRight
        }
    }
}

// MARK: - 평면 근사 헬퍼 (이 파일 내부 전용)

/// 기준 좌표 근방에서 위/경도를 미터 평면(x=동, y=북)으로 근사 변환하는 프레임.
private struct PlanarFrame {
    private let referenceLatitude: Double
    private let referenceLongitude: Double
    private let metersPerDegreeLatitude = 111_320.0
    private let metersPerDegreeLongitude: Double

    init(reference: CLLocationCoordinate2D) {
        referenceLatitude = reference.latitude
        referenceLongitude = reference.longitude
        metersPerDegreeLongitude = 111_320.0 * cos(reference.latitude * .pi / 180)
    }

    func toXY(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        (
            (coordinate.longitude - referenceLongitude) * metersPerDegreeLongitude,
            (coordinate.latitude - referenceLatitude) * metersPerDegreeLatitude
        )
    }

    func toCoordinate(x: Double, y: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: referenceLatitude + (metersPerDegreeLatitude == 0 ? 0 : y / metersPerDegreeLatitude),
            longitude: referenceLongitude + (metersPerDegreeLongitude == 0 ? 0 : x / metersPerDegreeLongitude)
        )
    }

    /// 기준점(원점)에서 선분 start-end 위의 가장 가까운 점과 거리를 구한다.
    func projectOntoSegment(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> (coordinate: CLLocationCoordinate2D, distanceMeters: CLLocationDistance) {
        let a = toXY(start)
        let b = toXY(end)
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby

        guard lengthSquared > 0 else {
            return (start, hypot(a.x, a.y))
        }

        // 원점(기준점) P=(0,0)에서 선분 위로의 투영 비율 t를 [0,1]로 클램프.
        let t = max(0, min(1, -(a.x * abx + a.y * aby) / lengthSquared))
        let projX = a.x + t * abx
        let projY = a.y + t * aby
        return (toCoordinate(x: projX, y: projY), hypot(projX, projY))
    }
}

/// 두 좌표 사이의 평면 근사 거리(m).
private func planarDistanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
    let frame = PlanarFrame(reference: a)
    let xy = frame.toXY(b)
    return hypot(xy.x, xy.y)
}

/// 두 좌표 사이를 비율(0~1)로 선형 보간. 도시 스케일에서 충분히 정확.
private func interpolateCoordinate(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D,
    ratio: Double
) -> CLLocationCoordinate2D {
    let clamped = max(0, min(1, ratio))
    return CLLocationCoordinate2D(
        latitude: start.latitude + (end.latitude - start.latitude) * clamped,
        longitude: start.longitude + (end.longitude - start.longitude) * clamped
    )
}

/// 두 좌표 사이의 평면 근사 방위각(도, 북=0, 동=90).
private func planarBearingDegrees(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
    let frame = PlanarFrame(reference: start)
    let xy = frame.toXY(end)
    let degrees = atan2(xy.x, xy.y) * 180 / .pi
    return degrees >= 0 ? degrees : degrees + 360
}
