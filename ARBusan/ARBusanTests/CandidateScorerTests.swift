import XCTest
@testable import ARBusan

final class CandidateScorerTests: XCTestCase {
    func testScoresTextPolygonAndLocationMatchHighest() {
        let scorer = CandidateScorer()
        let spots = MockTourismSpots.gimhae

        let scored = scorer.score(
            candidates: spots,
            cameraText: "투썸플레이스",
            locationConfidence: .high,
            cameraDirectionSpotIDs: [],
            vpsNearbySpotIDs: ["mock-gimhae-twosome-inje-192"],
            polygonValidatedSpotIDs: ["mock-gimhae-twosome-inje-192"]
        )

        XCTAssertEqual(scored.first?.spot.id, "mock-gimhae-twosome-inje-192")
        XCTAssertEqual(scored.first?.score, 110)
    }

    func testPipelineDoesNotRecognizeSpatialCandidateWhenOCRConflicts() {
        let pipeline = RecognitionPipeline()

        let result = pipeline.recognize(
            candidates: MockTourismSpots.gimhae,
            cameraText: "후참잘",
            locationConfidence: .high,
            cameraDirectionSpotIDs: [],
            vpsNearbySpotIDs: ["mock-gimhae-twosome-inje-192"],
            polygonValidatedSpotIDs: ["mock-gimhae-twosome-inje-192"]
        )

        guard case let .ambiguous(candidates, reason) = result else {
            XCTFail("OCR과 VPS/Polygon이 충돌하면 자동 인식 대신 후보 선택으로 보내야 합니다.")
            return
        }

        XCTAssertTrue(candidates.contains { $0.id == "mock-gimhae-hoochamjal-inje-191" })
        XCTAssertTrue(candidates.contains { $0.id == "mock-gimhae-twosome-inje-192" })
        XCTAssertTrue(reason.contains("OCR은 후참잘"))
    }

    func testPipelineTreatsSpatialOnlyMatchAsNearbyCandidate() {
        let pipeline = RecognitionPipeline()

        let result = pipeline.recognize(
            candidates: MockTourismSpots.gimhae,
            cameraText: "",
            locationConfidence: .high,
            cameraDirectionSpotIDs: [],
            vpsNearbySpotIDs: ["mock-gimhae-twosome-inje-192"],
            polygonValidatedSpotIDs: ["mock-gimhae-twosome-inje-192"]
        )

        guard case let .nearby(spot, reason) = result else {
            XCTFail("OCR 확인 없이 VPS/Polygon만 맞으면 인식 확정이 아니라 근처 후보여야 합니다.")
            return
        }

        XCTAssertEqual(spot.id, "mock-gimhae-twosome-inje-192")
        XCTAssertTrue(reason.contains("카메라 OCR 또는 방향 확인이 없습니다"))
    }

    func testPipelineRecognizesWhenCameraDirectionAndSpatialSignalsMatch() {
        let pipeline = RecognitionPipeline()

        let result = pipeline.recognize(
            candidates: MockTourismSpots.gimhae,
            cameraText: "",
            locationConfidence: .high,
            cameraDirectionSpotIDs: ["mock-gimhae-hoochamjal-inje-191"],
            vpsNearbySpotIDs: ["mock-gimhae-hoochamjal-inje-191"],
            polygonValidatedSpotIDs: ["mock-gimhae-hoochamjal-inje-191"]
        )

        guard case let .recognized(spot, confidence, _) = result else {
            XCTFail("카메라 방향, VPS, Polygon이 같은 후보를 가리키면 인식되어야 합니다.")
            return
        }

        XCTAssertEqual(spot.id, "mock-gimhae-hoochamjal-inje-191")
        XCTAssertEqual(confidence, .high)
    }

    func testPipelinePrioritizesMatchingOCRAndCameraDirectionOverStaleSpatialSelection() {
        let pipeline = RecognitionPipeline()

        let result = pipeline.recognize(
            candidates: MockTourismSpots.gimhae,
            cameraText: "후참잘",
            locationConfidence: .high,
            cameraDirectionSpotIDs: ["mock-gimhae-hoochamjal-inje-191"],
            vpsNearbySpotIDs: ["mock-gimhae-twosome-inje-192"],
            polygonValidatedSpotIDs: ["mock-gimhae-twosome-inje-192"]
        )

        guard case let .recognized(spot, confidence, _) = result else {
            XCTFail("OCR과 카메라 방향이 같은 건물을 가리키면 이전 VPS/Polygon 수동값보다 우선해야 합니다.")
            return
        }

        XCTAssertEqual(spot.id, "mock-gimhae-hoochamjal-inje-191")
        XCTAssertEqual(confidence, .high)
    }
}
