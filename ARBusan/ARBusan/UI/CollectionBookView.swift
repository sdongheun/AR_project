import SwiftData
import SwiftUI

struct CollectionBookView: View {
    let spots: [TourismSpot]
    let selectedSpot: TourismSpot?

    @Query(sort: \StampRecord.acquiredAt, order: .reverse) private var stamps: [StampRecord]

    private var stampsBySpotID: [String: StampRecord] {
        Dictionary(stamps.map { ($0.spotID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List(spots) { spot in
                let stamp = stampsBySpotID[spot.id]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(spot.name)
                            .font(.headline)
                        if stamp != nil {
                            Label("스탬프", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.18))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                        if spot.id == selectedSpot?.id {
                            Text("인식됨")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(spot.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let stamp {
                        Text("획득: \(stamp.acquiredAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text(spot.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("도감 · 스탬프 \(stamps.count)")
        }
    }
}
