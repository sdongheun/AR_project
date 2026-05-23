import SwiftUI

struct APIKeyStatusView: View {
    let statuses: [APIKeyStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API 키 상태")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(statuses) { status in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.isConfigured ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(status.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

