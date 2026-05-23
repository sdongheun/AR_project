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
            vpsNearbySpotIDs: ["mock-gimhae-twosome-inje-192"],
            polygonValidatedSpotIDs: ["mock-gimhae-twosome-inje-192"]
        )

        XCTAssertEqual(scored.first?.spot.id, "mock-gimhae-twosome-inje-192")
        XCTAssertEqual(scored.first?.score, 110)
    }
}
