import SwiftUI

struct ARExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsCollection = false

    var body: some View {
        GeometryReader { geometry in
            let bottomPanelHeight = min(430, geometry.size.height * 0.48)
            ZStack(alignment: .bottom) {
                ARViewContainer()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                if !FeatureFlags.useARMapMVPDirection, let label = appState.arLabelOverlay {
                    ARSpotLabelView(label: label)
                        .position(
                            x: label.normalizedX * geometry.size.width,
                            y: label.normalizedY * geometry.size.height
                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.18), value: label)
                }

                if FeatureFlags.enableLegacyMatrixDebugOverlay,
                   appState.showsMatrixDebugMarker,
                   let debugOverlay = appState.matrixProjectionDebugOverlay {
                    MatrixProjectionDebugMarkerView(overlay: debugOverlay)
                        .position(
                            x: debugOverlay.normalizedX * geometry.size.width,
                            y: debugOverlay.normalizedY * geometry.size.height
                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.12), value: debugOverlay)
                }

                if FeatureFlags.enableLegacyOnScreenCandidateDebugMarkers,
                   appState.showsOnScreenCandidateDebugMarkers {
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

                if !appState.radarMarkerOverlays.isEmpty {
                    RadarOverlayView(markers: appState.radarMarkerOverlays) { markerID in
                        if let spot = appState.spots.first(where: { $0.id == markerID }) {
                            appState.selectCandidate(spot)
                        }
                    }
                    .frame(width: min(geometry.size.width - 32, 360), height: 150)
                    .padding(.bottom, bottomPanelHeight + 8)
                    .transition(.opacity)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        APIKeyStatusView(statuses: appState.apiKeys.statuses)
                        if FeatureFlags.showCompactDebugDashboard {
                            DebugDashboardView(
                                overviewRows: appState.debugOverviewRows,
                                locationRows: appState.locationDebugRows,
                                dataRows: appState.dataDebugRows,
                                displayRows: appState.displayDebugRows,
                                anchorRows: appState.anchorDebugRows
                            )
                        }
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
                .frame(maxHeight: bottomPanelHeight)
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showsCollection) {
            CollectionBookView(spots: appState.spots, selectedSpot: appState.selectedSpot)
        }
    }
}

private struct RadarOverlayView: View {
    let markers: [RadarMarkerOverlay]
    let onSelect: (TourismSpot.ID) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadarBackgroundShape()
                    .fill(.black.opacity(0.48))
                RadarBackgroundShape()
                    .stroke(.white.opacity(0.5), lineWidth: 1)

                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let center = CGPoint(x: width / 2, y: height - 8)
                    path.move(to: CGPoint(x: width * 0.5, y: height - 8))
                    path.addLine(to: CGPoint(x: width * 0.5, y: 12))
                    path.move(to: CGPoint(x: width * 0.12, y: height - 8))
                    path.addLine(to: CGPoint(x: width * 0.88, y: height - 8))
                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: min(width * 0.38, height * 0.76),
                        startAngle: .degrees(200),
                        endAngle: .degrees(340),
                        clockwise: false
                    )
                }
                .stroke(.white.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                VStack(spacing: 2) {
                    Image(systemName: "location.north.fill")
                        .font(.caption.weight(.bold))
                    Text("내 시야")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.88))
                .position(x: geometry.size.width / 2, y: geometry.size.height - 26)

                ForEach(markers) { marker in
                    Button {
                        onSelect(marker.id)
                    } label: {
                        RadarMarkerDotView(marker: marker)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: marker.normalizedX * geometry.size.width,
                        y: marker.normalizedY * geometry.size.height
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
    }
}

private struct RadarBackgroundShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY - 8)
        let radius = min(rect.width * 0.48, rect.height * 0.92)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(200),
            endAngle: .degrees(340),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct RadarMarkerDotView: View {
    let marker: RadarMarkerOverlay

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(marker.isSelected ? .blue : .red)
                .frame(width: marker.isSelected ? 13 : 10, height: marker.isSelected ? 13 : 10)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(marker.isSelected ? 0.95 : 0.75), lineWidth: 1)
                )
                .opacity(marker.isBehind ? 0.55 : 1)

            Text(marker.shortTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(marker.distanceText)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(marker.isSelected ? 0.58 : 0.34), in: RoundedRectangle(cornerRadius: 6))
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
        viewController.onRouteArrowRenderStatusUpdated = { diagnostics in
            DispatchQueue.main.async {
                appState.updateRouteArrowRenderDiagnostics(diagnostics)
            }
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: ARSessionViewController, context: Context) {
        uiViewController.setShows3DGeospatialDebugMarker(appState.shows3DGeospatialDebugMarker)
        uiViewController.setRouteArrowPath(appState.routeArrowPath)
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
