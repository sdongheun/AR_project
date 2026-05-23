import SwiftUI

struct ARExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsCollection = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    APIKeyStatusView(statuses: appState.apiKeys.statuses)
                    GeospatialStatusView(
                        status: appState.geospatialStatus,
                        snapshot: appState.latestLocationSnapshot
                    )
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 430)
            .background(.regularMaterial)
        }
        .sheet(isPresented: $showsCollection) {
            CollectionBookView(spots: appState.spots, selectedSpot: appState.selectedSpot)
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
        viewController.onCameraHeadingUpdated = { heading in
            appState.updateCameraHeading(heading)
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: ARSessionViewController, context: Context) {}
}

private struct GeospatialStatusView: View {
    let status: String
    let snapshot: LocationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VPS/위치 상태")
                .font(.caption.weight(.semibold))
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let snapshot {
                Text("\(snapshot.source.rawValue) \(snapshot.latitude.formatted(.number.precision(.fractionLength(5)))), \(snapshot.longitude.formatted(.number.precision(.fractionLength(5)))) / 정확도 \(Int(snapshot.horizontalAccuracy))m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
