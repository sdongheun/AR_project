import Foundation

struct RecognitionPipeline {
    private let scorer = CandidateScorer()

    func recognize(
        candidates: [TourismSpot],
        cameraText: String,
        locationConfidence: RecognitionConfidence,
        vpsNearbySpotIDs: Set<String>,
        polygonValidatedSpotIDs: Set<String>
    ) -> RecognitionResult {
        let scored = scorer.score(
            candidates: candidates,
            cameraText: cameraText,
            locationConfidence: locationConfidence,
            vpsNearbySpotIDs: vpsNearbySpotIDs,
            polygonValidatedSpotIDs: polygonValidatedSpotIDs
        )

        guard let first = scored.first else {
            return .none(reason: "후보 건물이 없습니다.")
        }

        if scored.count > 1, let second = scored.dropFirst().first, first.score - second.score < 15 {
            return .ambiguous(
                candidates: Array(scored.prefix(3).map(\.spot)),
                reason: "상위 후보의 점수 차이가 작아 사용자 선택이 필요합니다."
            )
        }

        if first.score >= 80 {
            return .recognized(
                spot: first.spot,
                confidence: .high,
                reason: "카메라 OCR, VPS 후보, polygon 검증이 같은 건물을 가리킵니다."
            )
        }

        if first.score >= 55 {
            return .recognized(
                spot: first.spot,
                confidence: .medium,
                reason: "일부 건물 인식 신호가 일치했습니다. 현장에서는 후보 선택 또는 추가 카메라 검증이 필요합니다."
            )
        }

        return .none(reason: "신뢰도 기준을 넘는 후보가 없습니다.")
    }
}
