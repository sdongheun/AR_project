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

                if let label = appState.arLabelOverlay {
                    ARSpotLabelView(label: label)
                        .position(
                            x: label.normalizedX * geometry.size.width,
                            y: label.normalizedY * geometry.size.height
                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.18), value: label)
                }

                if appState.showsMatrixDebugMarker, let debugOverlay = appState.matrixProjectionDebugOverlay {
                    MatrixProjectionDebugMarkerView(overlay: debugOverlay)
                        .position(
                            x: debugOverlay.normalizedX * geometry.size.width,
                            y: debugOverlay.normalizedY * geometry.size.height
                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.12), value: debugOverlay)
                }

                if appState.showsOnScreenCandidateDebugMarkers {
                    ForEach(appState.onScreenCandidateMarkerOverlays) { marker in
                        OnScreenCandidateMarkerView(marker: marker)
                            .position(
                                x: marker.normalizedX * geometry.size.width,
                                y: marker.normalizedY * geometry.size.height
                            )
                            .allowsHitTesting(false)
                            .animation(.easeOut(duration: 0.14), value: marker)
                    }
                }

                ForEach(appState.edgeMarkerOverlays) { marker in
                    EdgeMarkerView(marker: marker)
                        .position(
                            x: marker.normalizedX * geometry.size.width,
                            y: marker.normalizedY * geometry.size.height
                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.16), value: marker)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        APIKeyStatusView(statuses: appState.apiKeys.statuses)
                        DebugDashboardView(
                            overviewRows: appState.debugOverviewRows,
                            locationRows: appState.locationDebugRows,
                            dataRows: appState.dataDebugRows,
                            displayRows: appState.displayDebugRows,
                            anchorRows: appState.anchorDebugRows
                        )
                        if appState.showsFullDebugLogs {
                            GeospatialStatusView(
                                status: appState.geospatialStatus,
                                coreLocationSnapshot: appState.latestCoreLocationSnapshot,
                                geospatialSnapshot: appState.latestGeospatialLocationSnapshot
                            )
                        } else {
                            CompactGeospatialStatusView(
                                geospatialSnapshot: appState.latestGeospatialLocationSnapshot,
                                coreLocationSnapshot: appState.latestCoreLocationSnapshot,
                                locationConfidence: appState.locationConfidence,
                                stableOriginDiagnostics: appState.stableOriginDiagnostics,
                                wgs84CandidateDiagnostics: appState.geospatialWGS84CandidateDiagnostics,
                                geospatialAnchorStateDiagnostics: appState.geospatialAnchorStateDiagnostics
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.recognitionResult.title)
                                .font(.headline)
                            Text(appState.recognitionResult.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        MVPRecognitionControlView()

                        if appState.showsFullDebugLogs {
                            CandidateSelectionView(result: appState.recognitionResult) { spot in
                                appState.selectCandidate(spot)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("테스트 목업 건물 후보")
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

private struct DebugDashboardView: View {
    let overviewRows: [DebugStatusRow]
    let locationRows: [DebugStatusRow]
    let dataRows: [DebugStatusRow]
    let displayRows: [DebugStatusRow]
    let anchorRows: [DebugStatusRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("테스트 로그 요약")
                .font(.caption.weight(.semibold))

            DebugStatusRowsView(rows: overviewRows)

            VStack(alignment: .leading, spacing: 10) {
                DebugStatusGroupView(title: "위치", rows: locationRows)
                DebugStatusGroupView(title: "데이터", rows: dataRows)
                DebugStatusGroupView(title: "표시", rows: displayRows)
                DebugStatusGroupView(title: "3D", rows: anchorRows)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DebugStatusGroupView: View {
    let title: String
    let rows: [DebugStatusRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
            DebugStatusRowsView(rows: rows)
        }
    }
}

private struct DebugStatusRowsView: View {
    let rows: [DebugStatusRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 6) {
                    Text(row.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 48, alignment: .leading)
                    Text(row.value)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct OnScreenCandidateMarkerView: View {
    let marker: OnScreenCandidateMarkerOverlay

    var body: some View {
        HStack(spacing: 4) {
            Text(marker.shortTitle)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let distanceText = marker.distanceText {
                Text(distanceText)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(marker.role.markerColor.opacity(0.84), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.82), lineWidth: 1)
        )
        .scaleEffect(marker.scale)
        .shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 2)
    }
}

private struct EdgeMarkerView: View {
    let marker: EdgeMarkerOverlay

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: marker.systemImageName)
                .font(.caption2.weight(.bold))
            Text(marker.shortTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let distanceText = marker.distanceText {
                Text(distanceText)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.72), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.75), lineWidth: 1)
        )
        .scaleEffect(marker.scale)
        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
    }
}

private extension OnScreenCandidateMarkerOverlay.Role {
    var markerColor: Color {
        switch self {
        case .primary:
            return .pink
        case .secondary:
            return .orange
        }
    }
}

private struct MatrixProjectionDebugMarkerView: View {
    let overlay: MatrixProjectionDebugOverlay

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(overlay.isInsideView ? .purple : .red)
                    .frame(width: 12, height: 12)
            }

            Text("\(overlay.title) \(overlay.insidePointCount)/\(overlay.totalPointCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(overlay.isInsideView ? .purple.opacity(0.82) : .red.opacity(0.82), in: Capsule())
        }
        .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 2)
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

    func updateUIViewController(_ uiViewController: ARSessionViewController, context: Context) {
        uiViewController.setShows3DGeospatialDebugMarker(appState.shows3DGeospatialDebugMarker)
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

private struct CompactGeospatialStatusView: View {
    let geospatialSnapshot: LocationSnapshot?
    let coreLocationSnapshot: LocationSnapshot?
    let locationConfidence: RecognitionConfidence
    let stableOriginDiagnostics: String
    let wgs84CandidateDiagnostics: String
    let geospatialAnchorStateDiagnostics: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VPS/위치 요약")
                .font(.caption.weight(.semibold))

            if let geospatialSnapshot {
                Text("VPS 보정 좌표 수신 / 정확도 약 \(Int(geospatialSnapshot.horizontalAccuracy))m / 위치 신뢰도 \(locationConfidence.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let coreLocationSnapshot {
                Text("CoreLocation 수신 / 정확도 약 \(Int(coreLocationSnapshot.horizontalAccuracy))m / VPS 보정 대기")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("위치 수신 대기 중")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("3D 기준 위치: \(stableOriginDiagnostics)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("WGS84 후보: \(wgs84CandidateDiagnostics)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("WGS84 앵커: \(geospatialAnchorStateDiagnostics)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
