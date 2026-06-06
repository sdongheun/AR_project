import CoreLocation
import SwiftUI
import TMapSDK
import UIKit

struct MainMapHomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSpot: TourismSpot?
    @State private var showsARNavigation = false
    @State private var showsInfoSheet = false

    private var mapCenter: CLLocationCoordinate2D {
        if let coordinate = appState.latestLocationSnapshot?.coordinate {
            return coordinate
        }

        if let selectedSpot {
            return selectedSpot.center
        }

        return appState.spots.first?.center ?? CLLocationCoordinate2D(latitude: 35.1796, longitude: 129.0756)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TMAPNativeMapView(
                apiKey: appState.apiKeys.tmap,
                spots: appState.spots,
                selectedSpotID: selectedSpot?.id,
                center: mapCenter,
                currentLocation: appState.latestCoreLocationSnapshot?.coordinate ?? appState.latestLocationSnapshot?.coordinate,
                onSelectSpot: { spotID in
                    guard let spot = appState.spots.first(where: { $0.id == spotID }) else {
                        return
                    }

                    selectedSpot = spot
                    appState.selectCandidate(spot)
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                MainMapHeaderView(
                    spotCount: appState.spots.count,
                    isTmapConfigured: appState.apiKeys.tmap.isConfiguredForMapRuntime
                )

                Spacer()

                if let selectedSpot {
                    TourismSpotMapCard(
                        spot: selectedSpot,
                        onShowInfo: {
                            showsInfoSheet = true
                        },
                        onStartNavigation: {
                            appState.selectNavigationDestination(selectedSpot)
                            showsARNavigation = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    MainMapEmptySelectionHint()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: selectedSpot?.id)
        .sheet(isPresented: $showsInfoSheet) {
            TourismSpotInfoPlaceholderView(spot: selectedSpot)
        }
        .fullScreenCover(isPresented: $showsARNavigation) {
            ARExploreView()
                .environmentObject(appState)
        }
        .task {
            appState.startMainMapLocationUpdates()
        }
    }
}

private struct MainMapHeaderView: View {
    let spotCount: Int
    let isTmapConfigured: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ARBusan")
                    .font(.title3.weight(.black))
                Text("현재 위치 기준 1km 관광지 핀")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isTmapConfigured ? Color.green : Color.red)
                    .frame(width: 9, height: 9)
                Text("TMAP")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Text("\(spotCount)개")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct MainMapEmptySelectionHint: View {
    var body: some View {
        Text("지도 핀을 선택하면 관광지 카드가 표시됩니다.")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TourismSpotMapCard: View {
    let spot: TourismSpot
    let onShowInfo: () -> Void
    let onStartNavigation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.teal.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 5) {
                    Text(spot.name)
                        .font(.headline.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(spot.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)

                    Text(spot.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onShowInfo) {
                    Label("정보보기", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onStartNavigation) {
                    Label("길찾기", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
    }
}

private struct TourismSpotInfoPlaceholderView: View {
    let spot: TourismSpot?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(spot?.name ?? "관광지 정보")
                    .font(.title2.weight(.black))

                Text("1차 MVP에서는 상세 정보 창 전환만 구현합니다. 관광지 사진과 상세 설명은 TourAPI 이미지/상세 정보 연결 단계에서 채웁니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let spot {
                    Divider()
                    Text(spot.address)
                        .font(.subheadline)
                    Text(spot.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("정보보기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct TMAPNativeMapView: UIViewRepresentable {
    let apiKey: String
    let spots: [TourismSpot]
    let selectedSpotID: TourismSpot.ID?
    let center: CLLocationCoordinate2D
    let currentLocation: CLLocationCoordinate2D?
    let onSelectSpot: (TourismSpot.ID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectSpot: onSelectSpot)
    }

    func makeUIView(context: Context) -> TMapView {
        let mapView = TMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.backgroundColor = .systemBackground
        mapView.isPanningEnable = true
        mapView.isZoomEnable = true
        mapView.isShowCompass = true
        mapView.setAppName("ARBusan")
        if apiKey.isConfiguredForMapRuntime {
            mapView.setApiKey(apiKey)
        }
        mapView.setCenter(center)
        mapView.setZoom(16)
        context.coordinator.renderMarkers(
            on: mapView,
            spots: spots,
            selectedSpotID: selectedSpotID,
            center: center,
            currentLocation: currentLocation
        )
        return mapView
    }

    func updateUIView(_ mapView: TMapView, context: Context) {
        context.coordinator.onSelectSpot = onSelectSpot
        context.coordinator.renderMarkers(
            on: mapView,
            spots: spots,
            selectedSpotID: selectedSpotID,
            center: center,
            currentLocation: currentLocation
        )
    }

    final class Coordinator: NSObject, TMapViewDelegate {
        var onSelectSpot: (TourismSpot.ID) -> Void
        private var lastSignature = ""
        private var lastSpotLayoutSignature = ""
        private var markers: [TMapMarker] = []
        private var currentLocationMarker: TMapMarker?
        private var latestCurrentLocation: CLLocationCoordinate2D?
        private var hasCenteredOnCurrentLocation = false

        init(onSelectSpot: @escaping (TourismSpot.ID) -> Void) {
            self.onSelectSpot = onSelectSpot
        }

        func renderMarkers(
            on mapView: TMapView,
            spots: [TourismSpot],
            selectedSpotID: TourismSpot.ID?,
            center: CLLocationCoordinate2D,
            currentLocation: CLLocationCoordinate2D?
        ) {
            let spotLayoutSignature = spots.map { "\($0.id):\($0.center.latitude):\($0.center.longitude)" }.joined(separator: "|")
            let currentLocationSignature = currentLocation.map { "\($0.latitude):\($0.longitude)" } ?? "none"
            let signature = "\(spotLayoutSignature)-\(selectedSpotID ?? "")-\(currentLocationSignature)"
            guard lastSignature != signature else {
                return
            }

            lastSignature = signature
            let shouldFitBounds = lastSpotLayoutSignature != spotLayoutSignature
            lastSpotLayoutSignature = spotLayoutSignature
            updateCurrentLocationMarker(on: mapView, currentLocation: currentLocation)

            markers.forEach { $0.map = nil }
            markers.removeAll()

            guard !spots.isEmpty else {
                mapView.setCenter(center)
                mapView.setZoom(16)
                return
            }

            markers = spots.map { spot in
                let marker = TMapMarker(position: spot.center)
                marker.title = spot.name
                marker.icon = Self.markerImage(isSelected: spot.id == selectedSpotID)
                marker.isUseImage = true
                marker.setCanShowCallout = true
                marker.setTapCallback { [weak self] _ in
                    self?.onSelectSpot(spot.id)
                }
                marker.map = mapView
                return marker
            }

            if let currentLocation, !hasCenteredOnCurrentLocation {
                centerOnCurrentLocationIfNeeded(mapView)
            } else if shouldFitBounds, hasCenteredOnCurrentLocation || currentLocation == nil && markers.count > 1 {
                mapView.fitMapBoundsWithMarkers(
                    markers,
                    inset: UIEdgeInsets(top: 120, left: 40, bottom: 220, right: 40)
                )
            } else if let selectedSpot = spots.first(where: { $0.id == selectedSpotID }) {
                mapView.animateTo(location: selectedSpot.center)
            }
        }

        private func updateCurrentLocationMarker(on mapView: TMapView, currentLocation: CLLocationCoordinate2D?) {
            guard let currentLocation else {
                currentLocationMarker?.map = nil
                currentLocationMarker = nil
                latestCurrentLocation = nil
                hasCenteredOnCurrentLocation = false
                return
            }

            latestCurrentLocation = currentLocation
            if let currentLocationMarker {
                currentLocationMarker.position = currentLocation
                currentLocationMarker.map = mapView
            } else {
                let marker = TMapMarker(position: currentLocation)
                marker.title = "내 위치"
                marker.icon = Self.currentLocationImage()
                marker.isUseImage = true
                marker.setCanShowCallout = true
                marker.map = mapView
                currentLocationMarker = marker
            }
        }

        private func centerOnCurrentLocationIfNeeded(_ mapView: TMapView) {
            guard let latestCurrentLocation, !hasCenteredOnCurrentLocation else {
                return
            }

            hasCenteredOnCurrentLocation = true
            mapView.setCenter(latestCurrentLocation)
            mapView.setZoom(17)
            mapView.animateTo(location: latestCurrentLocation)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak mapView] in
                guard let self, let mapView, let latestCurrentLocation = self.latestCurrentLocation else {
                    return
                }
                mapView.setCenter(latestCurrentLocation)
                mapView.setZoom(17)
            }
        }

        func mapViewDidFinishLoadingMap() {
            if let mapView = currentLocationMarker?.map {
                centerOnCurrentLocationIfNeeded(mapView)
            }
        }

        func SKTMapApikeySucceed() {
            if let mapView = currentLocationMarker?.map {
                centerOnCurrentLocationIfNeeded(mapView)
            }
        }

        private static func currentLocationImage() -> UIImage {
            let size = CGSize(width: 34, height: 34)
            return UIGraphicsImageRenderer(size: size).image { context in
                let cgContext = context.cgContext
                cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: UIColor.black.withAlphaComponent(0.24).cgColor)
                UIColor.systemBlue.withAlphaComponent(0.22).setFill()
                UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 32, height: 32)).fill()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor.systemBlue.setFill()
                UIBezierPath(ovalIn: CGRect(x: 8, y: 8, width: 18, height: 18)).fill()
                UIColor.white.setStroke()
                UIBezierPath(ovalIn: CGRect(x: 8, y: 8, width: 18, height: 18)).stroke()
            }
        }

        private static func markerImage(isSelected: Bool) -> UIImage {
            let size = CGSize(width: 44, height: 56)
            let fillColor = isSelected ? UIColor.systemRed : UIColor.systemBlue
            return UIGraphicsImageRenderer(size: size).image { context in
                let cgContext = context.cgContext
                cgContext.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: UIColor.black.withAlphaComponent(0.26).cgColor)

                let pinPath = UIBezierPath()
                pinPath.move(to: CGPoint(x: 22, y: 54))
                pinPath.addCurve(to: CGPoint(x: 5, y: 21), controlPoint1: CGPoint(x: 14, y: 43), controlPoint2: CGPoint(x: 5, y: 34))
                pinPath.addCurve(to: CGPoint(x: 22, y: 4), controlPoint1: CGPoint(x: 5, y: 11), controlPoint2: CGPoint(x: 12, y: 4))
                pinPath.addCurve(to: CGPoint(x: 39, y: 21), controlPoint1: CGPoint(x: 32, y: 4), controlPoint2: CGPoint(x: 39, y: 11))
                pinPath.addCurve(to: CGPoint(x: 22, y: 54), controlPoint1: CGPoint(x: 39, y: 34), controlPoint2: CGPoint(x: 30, y: 43))
                pinPath.close()
                fillColor.setFill()
                pinPath.fill()

                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 15, y: 14, width: 14, height: 14)).fill()
            }
        }
    }
}

private extension String {
    var isConfiguredForMapRuntime: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}

struct ARExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsCollection = false

    var body: some View {
        GeometryReader { geometry in
            let bottomPanelHeight = min(430, geometry.size.height * 0.48)
            let guidanceWidth = min(geometry.size.width - 48, 360)
            let guidanceCenterX = min(
                max(
                    geometry.size.width / 2 + appState.navigationGuidanceHorizontalOffsetRatio * geometry.size.width,
                    guidanceWidth / 2 + 16
                ),
                geometry.size.width - guidanceWidth / 2 - 16
            )
            let guidanceCenterY = max(
                116,
                min(geometry.size.height * 0.22, geometry.size.height - bottomPanelHeight - 120)
            )
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

                if appState.isNavigationModeEnabled {
                    NavigationARGuidanceOverlay(
                        title: appState.navigationGuidanceTitle,
                        detail: appState.navigationGuidanceDetail,
                        systemImageName: appState.navigationGuidanceSystemImageName,
                        isArrivalNearby: appState.navigationGuidanceIsArrivalNearby
                    )
                    .frame(width: guidanceWidth)
                    .position(x: guidanceCenterX, y: guidanceCenterY)
                    .animation(.easeOut(duration: 0.18), value: appState.navigationGuidanceTitle)
                    .animation(.easeOut(duration: 0.18), value: appState.navigationGuidanceHorizontalOffsetRatio)
                    .allowsHitTesting(false)
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

private struct NavigationARGuidanceOverlay: View {
    let title: String
    let detail: String
    let systemImageName: String
    let isArrivalNearby: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.title.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background((isArrivalNearby ? Color.green : Color.blue).opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
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
                .fill(marker.isArrivalNearby ? .green : marker.isSelected ? .blue : .red)
                .frame(width: marker.isArrivalNearby ? 17 : marker.isSelected ? 13 : 10, height: marker.isArrivalNearby ? 17 : marker.isSelected ? 13 : 10)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(marker.isSelected ? 0.95 : 0.75), lineWidth: 1)
                )
                .opacity(marker.isBehind ? 0.55 : 1)
                .overlay {
                    if marker.isArrivalNearby {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white)
                    }
                }

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
        .background((marker.isArrivalNearby ? Color.green : Color.black).opacity(marker.isSelected ? 0.62 : 0.34), in: RoundedRectangle(cornerRadius: 6))
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
        case .tmap:
            return "TMAP 검색"
        }
    }
}
