import Foundation

protocol TourAPIClient {
    func fetchTourismSpots() async throws -> [TourismSpot]
}

struct MockTourAPIClient: TourAPIClient {
    func fetchTourismSpots() async throws -> [TourismSpot] {
        MockTourismSpots.gimhae
    }
}

