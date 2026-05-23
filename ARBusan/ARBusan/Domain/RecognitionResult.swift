import Foundation

enum RecognitionConfidence: String, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high:
            return "높음"
        case .medium:
            return "보통"
        case .low:
            return "낮음"
        }
    }
}

enum RecognitionResult {
    case recognized(spot: TourismSpot, confidence: RecognitionConfidence, reason: String)
    case nearby(spot: TourismSpot, reason: String)
    case ambiguous(candidates: [TourismSpot], reason: String)
    case none(reason: String)

    var title: String {
        switch self {
        case let .recognized(spot, confidence, _):
            return "\(spot.name) 건물 인식됨 (\(confidence.displayName))"
        case let .nearby(spot, _):
            return "\(spot.name) 근처 후보 감지"
        case .ambiguous:
            return "건물 후보 선택 필요"
        case .none:
            return "건물 인식 결과 없음"
        }
    }

    var detail: String {
        switch self {
        case let .recognized(_, _, reason),
            let .nearby(_, reason),
            let .ambiguous(_, reason),
            let .none(reason):
            return reason
        }
    }
}
