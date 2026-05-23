import Foundation

struct ScoredTourismSpot {
    let spot: TourismSpot
    let score: Int
}

struct CandidateScorer {
    func score(
        candidates: [TourismSpot],
        cameraText: String,
        locationConfidence: RecognitionConfidence,
        vpsNearbySpotIDs: Set<String>,
        polygonValidatedSpotIDs: Set<String>
    ) -> [ScoredTourismSpot] {
        candidates
            .map { spot in
                var score = 0
                let normalizedText = cameraText.normalizedRecognitionText
                let hasTextMatch = spot.recognitionHints.contains {
                    normalizedText.contains($0.normalizedRecognitionText)
                }

                if hasTextMatch {
                    score += 45
                }

                if vpsNearbySpotIDs.contains(spot.id) {
                    score += 20
                }

                if polygonValidatedSpotIDs.contains(spot.id) {
                    score += 30
                }

                switch locationConfidence {
                case .high:
                    score += 15
                case .medium:
                    score += 10
                case .low:
                    score += 5
                }

                return ScoredTourismSpot(spot: spot, score: score)
            }
            .sorted { $0.score > $1.score }
    }
}

private extension String {
    var normalizedRecognitionText: String {
        uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
