import Foundation
import SwiftData

/// 도착 AR 포토존에서 촬영 시 획득하는 관광지 스탬프(로컬 저장). 관광지당 1개(spotID 고유).
@Model
final class StampRecord {
    @Attribute(.unique) var spotID: String
    var spotName: String
    var acquiredAt: Date
    /// 촬영 사진의 사진 라이브러리(PHAsset) localIdentifier. 이미지 자체는 SwiftData에 넣지 않는다.
    var photoLocalIdentifier: String?

    init(spotID: String, spotName: String, acquiredAt: Date, photoLocalIdentifier: String? = nil) {
        self.spotID = spotID
        self.spotName = spotName
        self.acquiredAt = acquiredAt
        self.photoLocalIdentifier = photoLocalIdentifier
    }
}

/// 스탬프 추가/조회 로직. 중복(이미 보유한 spotID)은 추가하지 않는다.
enum StampStore {
    /// 이미 보유한 spotID 집합에 비추어 새 스탬프를 추가해야 하는지. (SwiftData에 의존하지 않는 순수 판정 → 테스트 가능)
    static func shouldAddStamp(spotID: String, existingSpotIDs: Set<String>) -> Bool {
        !spotID.isEmpty && !existingSpotIDs.contains(spotID)
    }

    /// 컨텍스트에 스탬프를 추가한다(중복이면 무시). 추가했으면 true.
    @MainActor
    static func addStampIfNeeded(
        spotID: String,
        spotName: String,
        photoLocalIdentifier: String?,
        existing: [StampRecord],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let existingIDs = Set(existing.map(\.spotID))
        guard shouldAddStamp(spotID: spotID, existingSpotIDs: existingIDs) else {
            return false
        }
        context.insert(
            StampRecord(
                spotID: spotID,
                spotName: spotName,
                acquiredAt: now,
                photoLocalIdentifier: photoLocalIdentifier
            )
        )
        return true
    }
}
