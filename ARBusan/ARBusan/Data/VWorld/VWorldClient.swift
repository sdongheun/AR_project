import Foundation

protocol VWorldClient {
    func validatePolygon(for spot: TourismSpot) async throws -> Bool
}

struct MockVWorldClient: VWorldClient {
    func validatePolygon(for spot: TourismSpot) async throws -> Bool {
        spot.geometryKind == .buildingPolygon
    }
}

