import Foundation

struct ScoredTourismSpot {
    let spot: TourismSpot
    let score: Int
    let hasTextMatch: Bool
    let hasCameraDirectionMatch: Bool
    let hasVPSMatch: Bool
    let hasPolygonMatch: Bool

    var hasVisualMatch: Bool {
        hasTextMatch || hasCameraDirectionMatch
    }

    var hasSpatialMatch: Bool {
        hasVPSMatch || hasPolygonMatch
    }
}

struct CandidateScorer {
    func score(
        candidates: [TourismSpot],
        cameraText: String,
        locationConfidence: RecognitionConfidence,
        cameraDirectionSpotIDs: Set<String>,
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
                let hasCameraDirectionMatch = cameraDirectionSpotIDs.contains(spot.id)
                let hasVPSMatch = vpsNearbySpotIDs.contains(spot.id)
                let hasPolygonMatch = polygonValidatedSpotIDs.contains(spot.id)

                if hasTextMatch {
                    score += 45
                }

                if hasCameraDirectionMatch {
                    score += 35
                }

                if hasVPSMatch {
                    score += 20
                }

                if hasPolygonMatch {
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

                return ScoredTourismSpot(
                    spot: spot,
                    score: score,
                    hasTextMatch: hasTextMatch,
                    hasCameraDirectionMatch: hasCameraDirectionMatch,
                    hasVPSMatch: hasVPSMatch,
                    hasPolygonMatch: hasPolygonMatch
                )
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
