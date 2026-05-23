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

    static func == (lhs: TourismSpot, rhs: TourismSpot) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

