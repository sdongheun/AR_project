import CoreLocation
import Foundation

enum LocationSnapshotSource: String {
    case coreLocation = "CoreLocation"
    case arCoreGeospatial = "ARCore Geospatial"
}

struct LocationSnapshot: Equatable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let altitude: CLLocationDistance?
    let horizontalAccuracy: CLLocationAccuracy
    let verticalAccuracy: CLLocationAccuracy?
    let heading: CLLocationDirection?
    let headingAccuracy: CLLocationDirectionAccuracy?
    let source: LocationSnapshotSource
    let capturedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 좌표만 바꾼 사본을 만든다. 길찾기 안내에서 경로 스냅/위치 유지로 보정한 좌표를
    /// 기존 source/정확도/heading을 유지한 채 적용할 때 사용한다.
    func replacingCoordinate(_ newCoordinate: CLLocationCoordinate2D) -> LocationSnapshot {
        LocationSnapshot(
            latitude: newCoordinate.latitude,
            longitude: newCoordinate.longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            heading: heading,
            headingAccuracy: headingAccuracy,
            source: source,
            capturedAt: capturedAt
        )
    }
}
