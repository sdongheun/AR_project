import CoreLocation
import Foundation

struct TourismSpot: Identifiable, Hashable {
    enum Source: String, Hashable {
        case tourAPI
        case mock
    }

    enum GeometryKind: String, Hashable {
        case point
        case buildingPolygon
        case areaPolygon
    }

    let id: String
    let name: String
    let address: String
    let districtName: String
    let category: String
    let source: Source
    let geometryKind: GeometryKind
    let center: CLLocationCoordinate2D
    let recognitionHints: [String]
    let notes: String
    let preferredMarkerCoordinate: CLLocationCoordinate2D?
    let entranceCoordinate: CLLocationCoordinate2D?
    let frontHeadingDegrees: Double?

    init(
        id: String,
        name: String,
        address: String,
        districtName: String,
        category: String,
        source: Source,
        geometryKind: GeometryKind,
        center: CLLocationCoordinate2D,
        recognitionHints: [String],
        notes: String,
        preferredMarkerCoordinate: CLLocationCoordinate2D? = nil,
        entranceCoordinate: CLLocationCoordinate2D? = nil,
        frontHeadingDegrees: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.districtName = districtName
        self.category = category
        self.source = source
        self.geometryKind = geometryKind
        self.center = center
        self.recognitionHints = recognitionHints
        self.notes = notes
        self.preferredMarkerCoordinate = preferredMarkerCoordinate
        self.entranceCoordinate = entranceCoordinate
        self.frontHeadingDegrees = frontHeadingDegrees
    }

    static func == (lhs: TourismSpot, rhs: TourismSpot) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
