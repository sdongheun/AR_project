import CoreLocation
import Foundation

struct CameraDirectionCandidate {
    let spot: TourismSpot
    let bearingDegrees: Double
    let headingDifferenceDegrees: Double
    let distanceMeters: CLLocationDistance
}

struct CameraDirectionCandidateProvider {
    private let maxHeadingDifferenceDegrees: Double
    private let maxDistanceMeters: CLLocationDistance

    init(maxHeadingDifferenceDegrees: Double = 25, maxDistanceMeters: CLLocationDistance = 120) {
        self.maxHeadingDifferenceDegrees = maxHeadingDifferenceDegrees
        self.maxDistanceMeters = maxDistanceMeters
    }

    func candidate(
        from location: LocationSnapshot?,
        cameraHeadingDegrees: Double?,
        spots: [TourismSpot]
    ) -> CameraDirectionCandidate? {
        guard let location, let cameraHeadingDegrees else {
            return nil
        }

        let origin = location.coordinate

        return spots
            .compactMap { spot -> CameraDirectionCandidate? in
                let distance = origin.distance(to: spot.center)
                guard distance <= maxDistanceMeters else {
                    return nil
                }

                let bearing = origin.bearing(to: spot.center)
                let difference = cameraHeadingDegrees.angularDifference(to: bearing)

                guard difference <= maxHeadingDifferenceDegrees else {
                    return nil
                }

                return CameraDirectionCandidate(
                    spot: spot,
                    bearingDegrees: bearing,
                    headingDifferenceDegrees: difference,
                    distanceMeters: distance
                )
            }
            .sorted {
                if $0.headingDifferenceDegrees == $1.headingDifferenceDegrees {
                    return $0.distanceMeters < $1.distanceMeters
                }
                return $0.headingDifferenceDegrees < $1.headingDifferenceDegrees
            }
            .first
    }
}

private extension CLLocationCoordinate2D {
    func distance(to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }

    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let startLatitude = latitude.degreesToRadians
        let startLongitude = longitude.degreesToRadians
        let endLatitude = destination.latitude.degreesToRadians
        let endLongitude = destination.longitude.degreesToRadians
        let longitudeDelta = endLongitude - startLongitude

        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return atan2(y, x).radiansToDegrees.normalizedDegrees
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

    func angularDifference(to other: Double) -> Double {
        let difference = abs(normalizedDegrees - other.normalizedDegrees)
        return min(difference, 360 - difference)
    }
}
