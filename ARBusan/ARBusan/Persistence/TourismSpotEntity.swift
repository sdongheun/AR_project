import Foundation
import SwiftData

@Model
final class TourismSpotEntity {
    @Attribute(.unique) var spotID: String
    var name: String
    var districtName: String
    var centerLat: Double
    var centerLng: Double
    var isVisited: Bool
    var visitedTimestamp: Date?
    var rawPolygonPoints: String

    init(
        spotID: String,
        name: String,
        districtName: String,
        centerLat: Double,
        centerLng: Double,
        rawPolygonPoints: String = ""
    ) {
        self.spotID = spotID
        self.name = name
        self.districtName = districtName
        self.centerLat = centerLat
        self.centerLng = centerLng
        self.isVisited = false
        self.visitedTimestamp = nil
        self.rawPolygonPoints = rawPolygonPoints
    }
}

