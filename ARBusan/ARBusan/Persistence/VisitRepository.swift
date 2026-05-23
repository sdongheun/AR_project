import Foundation
import SwiftData

@MainActor
struct VisitRepository {
    let context: ModelContext

    func markVisited(_ entity: TourismSpotEntity, at date: Date = .now) throws {
        entity.isVisited = true
        entity.visitedTimestamp = date
        try context.save()
    }
}

