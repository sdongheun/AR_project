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
                        coreLocationSnapshot: appState.latestCoreLocationSnapshot,
                        geospatialSnapshot: appState.latestGeospatialLocationSnapshot
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
        viewController.onCameraPoseUpdated = { pose in
            appState.updateCameraPose(pose)
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: ARSessionViewController, context: Context) {}
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
