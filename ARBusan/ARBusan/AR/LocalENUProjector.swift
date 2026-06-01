import CoreLocation
import Foundation

struct LocalENUCoordinate: Equatable {
    let eastMeters: Double
    let northMeters: Double
    let upMeters: Double

    var groundDistanceMeters: Double {
        hypot(eastMeters, northMeters)
    }

    var bearingDegrees: Double {
        atan2(eastMeters, northMeters).radiansToDegrees.normalizedDegrees
    }
}

enum LocalENUProjector {
    private static let earthRadiusMeters = 6_378_137.0

    static func project(
        _ coordinate: CLLocationCoordinate2D,
        altitude: CLLocationDistance? = nil,
        from origin: LocationSnapshot
    ) -> LocalENUCoordinate {
        let latitudeDelta = (coordinate.latitude - origin.latitude).degreesToRadians
        let longitudeDelta = (coordinate.longitude - origin.longitude).degreesToRadians
        let originLatitude = origin.latitude.degreesToRadians
        let east = longitudeDelta * earthRadiusMeters * cos(originLatitude)
        let north = latitudeDelta * earthRadiusMeters
        let up = (altitude ?? origin.altitude ?? 0) - (origin.altitude ?? 0)

        return LocalENUCoordinate(
            eastMeters: east,
            northMeters: north,
            upMeters: up
        )
    }

    static func coordinate(
        eastMeters: Double,
        northMeters: Double,
        from origin: LocationSnapshot
    ) -> CLLocationCoordinate2D {
        let originLatitudeRadians = origin.latitude.degreesToRadians
        let latitude = origin.latitude + (northMeters / earthRadiusMeters).radiansToDegrees
        let longitude = origin.longitude + (eastMeters / (earthRadiusMeters * cos(originLatitudeRadians))).radiansToDegrees

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension Double {
    var degreesToRadians: Double {
        self * .pi / 180
    }

    var radiansToDegrees: Double {
        self * 180 / .pi
    }

    var normalizedDegrees: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}
