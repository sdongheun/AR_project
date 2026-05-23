import Foundation

struct VisitState: Hashable {
    let spotID: String
    var isVisited: Bool
    var visitedAt: Date?
}

