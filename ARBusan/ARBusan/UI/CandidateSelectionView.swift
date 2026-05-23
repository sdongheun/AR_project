import SwiftUI

struct CandidateSelectionView: View {
    let result: RecognitionResult
    let onSelect: (TourismSpot) -> Void

    var body: some View {
        if case let .ambiguous(candidates, _) = result {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(candidates) { spot in
                    Button {
                        onSelect(spot)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(spot.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(spot.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

