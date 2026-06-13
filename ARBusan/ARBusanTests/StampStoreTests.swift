import XCTest
@testable import ARBusan

final class StampStoreTests: XCTestCase {
    func testShouldAddStampOnlyForNewNonEmptySpot() {
        let existing: Set<String> = ["haeundae", "gwangan"]

        // 새 관광지 → 추가.
        XCTAssertTrue(StampStore.shouldAddStamp(spotID: "gamcheon", existingSpotIDs: existing))
        // 이미 보유 → 중복 추가 안 함.
        XCTAssertFalse(StampStore.shouldAddStamp(spotID: "haeundae", existingSpotIDs: existing))
        // 빈 ID → 추가 안 함.
        XCTAssertFalse(StampStore.shouldAddStamp(spotID: "", existingSpotIDs: existing))
        // 비어 있는 보유 목록 + 유효 ID → 추가.
        XCTAssertTrue(StampStore.shouldAddStamp(spotID: "haeundae", existingSpotIDs: []))
    }
}
