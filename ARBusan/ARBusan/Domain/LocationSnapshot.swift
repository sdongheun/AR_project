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
}
