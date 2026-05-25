import SwiftUI

struct ARExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsCollection = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ARViewContainer()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                if let overlayImage = appState.sceneSemanticsOverlayImage {
                    Image(uiImage: overlayImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(0.55)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if let label = appState.arLabelOverlay {
                    ARSpotLabelView(label: label)
                        .position(
                            x: label.normalizedX * geometry.size.width,
                            y: label.normalizedY * geometry.size.height
                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.18), value: label)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        APIKeyStatusView(statuses: appState.apiKeys.statuses)
                        GeospatialStatusView(
                            status: appState.geospatialStatus,
                            coreLocationSnapshot: appState.latestCoreLocationSnapshot,
                            geospatialSnapshot: appState.latestGeospatialLocationSnapshot
                        )
                        SceneSemanticsStatusView(status: appState.sceneSemanticsStatus)
                        TourismDataStatusView(status: appState.tourismDataStatus)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.recognitionResult.title)
                                .font(.headline)
                            Text(appState.recognitionResult.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        MVPRecognitionControlView()

                        CandidateSelectionView(result: appState.recognitionResult) { spot in
                            appState.selectCandidate(spot)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("김해 목업 건물 후보")
                                .font(.subheadline.weight(.semibold))
                            ForEach(appState.spots) { spot in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(spot.name)
                                        .font(.caption.weight(.semibold))
                                    Text("\(spot.address) / \(spot.source.displayName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Button("도감 열기") {
                            showsCollection = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .frame(width: geometry.size.width)
                .frame(maxHeight: min(430, geometry.size.height * 0.48))
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showsCollection) {
            CollectionBookView(spots: appState.spots, selectedSpot: appState.selectedSpot)
        }
    }
}

private struct ARSpotLabelView: View {
    let label: ARLabelOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(label.confidence.tintColor)
                    .frame(width: 8, height: 8)
                Text(label.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(label.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if label.isSceneSemanticsAdjusted {
                Text("building 영역 보정")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 210, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(label.confidence.tintColor.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

private extension RecognitionConfidence {
    var tintColor: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }
}

private struct ARViewContainer: UIViewControllerRepresentable {
    @EnvironmentObject private var appState: AppState

    func makeUIViewController(context: Context) -> ARSessionViewController {
        let viewController = ARSessionViewController(
            geospatialSessionManager: appState.geospatialSessionManager
        )
        viewController.onRecognizedCameraText = { text in
            appState.updateCameraTextFromLiveOCR(text)
        }
        viewController.onCameraPoseUpdated = { pose in
            appState.updateCameraPose(pose)
        }
        viewController.onCameraProjectionUpdated = { projection in
            appState.updateCameraProjection(projection)
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: ARSessionViewController, context: Context) {}
}

private struct SceneSemanticsStatusView: View {
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scene Semantics 디버그")
                .font(.caption.weight(.semibold))
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 82), alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                SemanticLegendItem(color: .blue, title: "building")
                SemanticLegendItem(color: .red, title: "sky")
                SemanticLegendItem(color: .yellow, title: "tree")
                SemanticLegendItem(color: .gray, title: "road")
                SemanticLegendItem(color: .cyan, title: "water")
            }
        }
    }
}

private struct SemanticLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Rectangle()
                .fill(color.opacity(0.8))
                .frame(width: 9, height: 9)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GeospatialStatusView: View {
    let status: String
    let coreLocationSnapshot: LocationSnapshot?
    let geospatialSnapshot: LocationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VPS/위치 상태")
                .font(.caption.weight(.semibold))
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)

            LocationSnapshotRow(
                title: "CoreLocation 좌표",
                snapshot: coreLocationSnapshot,
                emptyText: "CoreLocation 좌표 수신 대기 중"
            )

            LocationSnapshotRow(
                title: "VPS 보정 좌표",
                snapshot: geospatialSnapshot,
                emptyText: "ARCore Geospatial 좌표 수신 대기 중"
            )
        }
    }
}

private struct LocationSnapshotRow: View {
    let title: String
    let snapshot: LocationSnapshot?
    let emptyText: String

    var body: some View {
        if let snapshot {
            Text("\(title): \(snapshot.latitude.formatted(.number.precision(.fractionLength(6)))), \(snapshot.longitude.formatted(.number.precision(.fractionLength(6)))) / 정확도 \(Int(snapshot.horizontalAccuracy))m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("\(title): \(emptyText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TourismDataStatusView: View {
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TourAPI 데이터 상태")
                .font(.caption.weight(.semibold))
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private extension TourismSpot.Source {
    var displayName: String {
        switch self {
        case .tourAPI:
            return "TourAPI"
        case .mock:
            return "목업 fallback"
        }
    }
}
