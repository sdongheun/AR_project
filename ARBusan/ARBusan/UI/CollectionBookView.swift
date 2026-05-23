import SwiftUI

struct CollectionBookView: View {
    let spots: [TourismSpot]
    let selectedSpot: TourismSpot?

    var body: some View {
        NavigationStack {
            List(spots) { spot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(spot.name)
                            .font(.headline)
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
                    Text(spot.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("목업 도감")
        }
    }
}

