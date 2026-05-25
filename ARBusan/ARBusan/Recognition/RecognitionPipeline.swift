import Foundation

struct RecognitionPipeline {
    private let scorer = CandidateScorer()

    func recognize(
        candidates: [TourismSpot],
        cameraText: String,
        locationConfidence: RecognitionConfidence,
        cameraDirectionSpotIDs: Set<String>,
        polygonValidatedSpotIDs: Set<String>,
        sceneSemanticsEvidenceBySpotID: [String: SceneSemanticsSpotEvidence] = [:]
    ) -> RecognitionResult {
        let scored = scorer.score(
            candidates: candidates,
            cameraText: cameraText,
            locationConfidence: locationConfidence,
            cameraDirectionSpotIDs: cameraDirectionSpotIDs,
            polygonValidatedSpotIDs: polygonValidatedSpotIDs,
            sceneSemanticsEvidenceBySpotID: sceneSemanticsEvidenceBySpotID
        )

        guard let first = scored.first else {
            return .none(reason: "후보 건물이 없습니다.")
        }

        if let conflictResult = makeSignalConflictResult(from: scored) {
            return conflictResult
        }

        if scored.count > 1, let second = scored.dropFirst().first, first.score - second.score < 15 {
            return .ambiguous(
                candidates: Array(scored.prefix(3).map(\.spot)),
                reason: "상위 후보의 점수 차이가 작아 사용자 선택이 필요합니다."
            )
        }

        if first.hasSpatialMatch && !first.hasVisualMatch {
            return .nearby(
                spot: first.spot,
                reason: "Polygon 후보는 \(first.spot.name)을 가리키지만 카메라 OCR 또는 방향 확인이 없습니다. 현재는 건물 인식 확정이 아니라 근처 후보로만 표시합니다."
            )
        }

        if first.score >= 80 {
            return .recognized(
                spot: first.spot,
                confidence: .high,
                reason: highConfidenceReason(for: first)
            )
        }

        if first.score >= 55 {
            return .recognized(
                spot: first.spot,
                confidence: .medium,
                reason: mediumConfidenceReason(for: first)
            )
        }

        return .none(reason: "신뢰도 기준을 넘는 후보가 없습니다.")
    }

    private func makeSignalConflictResult(from scored: [ScoredTourismSpot]) -> RecognitionResult? {
        guard let textMatched = scored.first(where: \.hasTextMatch) else {
            return nil
        }

        if textMatched.hasCameraDirectionMatch {
            return nil
        }

        let spatialMatches = scored.filter(\.hasSpatialMatch)
        guard !spatialMatches.isEmpty else {
            return nil
        }

        guard !spatialMatches.contains(where: { $0.spot.id == textMatched.spot.id }) else {
            return nil
        }

        let candidates = ([textMatched] + spatialMatches)
            .reduce(into: [ScoredTourismSpot]()) { unique, scoredSpot in
                if !unique.contains(where: { $0.spot.id == scoredSpot.spot.id }) {
                    unique.append(scoredSpot)
                }
            }
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map(\.spot)

        let spatialNames = spatialMatches
            .map(\.spot.name)
            .joined(separator: ", ")

        return .ambiguous(
            candidates: Array(candidates),
            reason: "OCR은 \(textMatched.spot.name)을 가리키지만 Polygon 후보는 \(spatialNames)을 가리킵니다. 현재는 자동 확정하지 않고 후보 선택이 필요합니다."
        )
    }

    private func highConfidenceReason(for scored: ScoredTourismSpot) -> String {
        var signals = ["카메라 OCR/방향 후보와 Polygon 검증이 같은 건물을 가리킵니다."]
        if let evidence = scored.sceneSemanticsEvidence {
            signals.append("Scene Semantics 보정: \(evidence.diagnosticText).")
        }
        signals.append("VPS는 위치 정확도 신호로만 반영했습니다.")
        return signals.joined(separator: " ")
    }

    private func mediumConfidenceReason(for scored: ScoredTourismSpot) -> String {
        var signals = ["일부 건물 인식 신호가 일치했습니다."]
        if let evidence = scored.sceneSemanticsEvidence {
            signals.append("Scene Semantics 보정: \(evidence.diagnosticText).")
        }
        signals.append("현장에서는 후보 선택 또는 추가 카메라 검증이 필요합니다.")
        return signals.joined(separator: " ")
    }
}
