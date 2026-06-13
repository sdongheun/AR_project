import CoreLocation
import SwiftUI
import TMapSDK
import UIKit

struct MainMapHomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSpot: TourismSpot?
    @State private var showsARNavigation = false
    @State private var showsInfoSheet = false
    @State private var showsCollection = false

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
                currentHeadingDegrees: appState.cameraHeadingDegrees,
                onSelectSpot: { spotID in
                    guard let spot = appState.spots.first(where: { $0.id == spotID }) else {
                        return
                    }

                    selectedSpot = spot
                    appState.selectCandidate(spot)
                },
                onTapMap: { _ in
                    // 빈 지도 탭 → 선택 해제(길찾기 박스 닫히고 플로팅 메뉴바 복귀).
                    selectedSpot = nil
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
                    // 핀 선택: 플로팅 메뉴바는 내려가고 길찾기 박스가 올라온다.
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
                    // 기본: 하단 타원 플로팅 메뉴바.
                    BottomFloatingMenuBar(
                        onMap: { selectedSpot = nil },
                        onExplore: { showsARNavigation = true },
                        onRecord: { showsCollection = true }
                    )
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: selectedSpot?.id)
        .sheet(isPresented: $showsInfoSheet) {
            TourismSpotInfoPlaceholderView(spot: selectedSpot)
        }
        .sheet(isPresented: $showsCollection) {
            CollectionBookView(spots: appState.spots, selectedSpot: selectedSpot)
        }
        .fullScreenCover(isPresented: $showsARNavigation) {
            ARExploreView {
                appState.setNavigationModeEnabled(false)
                showsARNavigation = false
            }
                .environmentObject(appState)
        }
        .task {
            appState.startMainMapLocationUpdates()
            await appState.loadTourAPISpots()
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
                Text("현재 위치 기준 3km 관광지 핀")
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

/// 메인 지도 하단의 타원(캡슐) 플로팅 메뉴바. 기본 상태에서 표시되고, 핀 선택 시 아래로 슬라이드된다.
private struct BottomFloatingMenuBar: View {
    let onMap: () -> Void
    let onExplore: () -> Void
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            item(title: "지도", systemImage: "map.fill", isCurrent: true, action: onMap)
            item(title: "탐색", systemImage: "camera.viewfinder", isCurrent: false, action: onExplore)
            item(title: "기록", systemImage: "star.circle.fill", isCurrent: false, action: onRecord)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
    }

    private func item(title: String, systemImage: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isCurrent ? Color.white : Color.primary.opacity(0.65))
            .frame(width: 66, height: 50)
            .background(isCurrent ? Color.blue.opacity(0.92) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
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
    var currentHeadingDegrees: Double?
    var routeCoordinates: [CLLocationCoordinate2D] = []
    var destinationCoordinate: CLLocationCoordinate2D?
    var isInteractionEnabled = true
    var zoomLevel: Int = 16
    var mapInsets = UIEdgeInsets(top: 120, left: 40, bottom: 220, right: 40)
    let onSelectSpot: (TourismSpot.ID) -> Void
    var onTapMap: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectSpot: onSelectSpot, onTapMap: onTapMap)
    }

    func makeUIView(context: Context) -> TMapView {
        let mapView = TMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.backgroundColor = .systemBackground
        mapView.isPanningEnable = isInteractionEnabled
        mapView.isZoomEnable = isInteractionEnabled
        mapView.isUserInteractionEnabled = isInteractionEnabled
        mapView.isShowCompass = true
        mapView.setAppName("ARBusan")
        if apiKey.isConfiguredForMapRuntime {
            mapView.setApiKey(apiKey)
        }
        mapView.setCenter(center)
        mapView.setZoom(zoomLevel)
        context.coordinator.renderMarkers(
            on: mapView,
            spots: spots,
            selectedSpotID: selectedSpotID,
            center: center,
            currentLocation: currentLocation,
            currentHeadingDegrees: currentHeadingDegrees,
            routeCoordinates: routeCoordinates,
            destinationCoordinate: destinationCoordinate,
            zoomLevel: zoomLevel,
            mapInsets: mapInsets
        )
        return mapView
    }

    func updateUIView(_ mapView: TMapView, context: Context) {
        mapView.isPanningEnable = isInteractionEnabled
        mapView.isZoomEnable = isInteractionEnabled
        mapView.isUserInteractionEnabled = isInteractionEnabled
        context.coordinator.onSelectSpot = onSelectSpot
        context.coordinator.onTapMap = onTapMap
        context.coordinator.renderMarkers(
            on: mapView,
            spots: spots,
            selectedSpotID: selectedSpotID,
            center: center,
            currentLocation: currentLocation,
            currentHeadingDegrees: currentHeadingDegrees,
            routeCoordinates: routeCoordinates,
            destinationCoordinate: destinationCoordinate,
            zoomLevel: zoomLevel,
            mapInsets: mapInsets
        )
    }

    final class Coordinator: NSObject, TMapViewDelegate {
        var onSelectSpot: (TourismSpot.ID) -> Void
        var onTapMap: ((CLLocationCoordinate2D) -> Void)?
        private var lastSignature = ""
        private var lastSpotLayoutSignature = ""
        private var markers: [TMapMarker] = []
        private var currentLocationMarker: TMapMarker?
        private var destinationMarker: TMapMarker?
        private var routePolyline: TMapPolyline?
        private var latestCurrentLocation: CLLocationCoordinate2D?
        private var hasCenteredOnCurrentLocation = false
        private var hasFitRouteBounds = false
        private var userDidInteractWithMap = false
        private var lastRouteBoundsSignature = ""
        private var lastRouteOverlaySignature = ""
        private var lastMapTapCoordinate: CLLocationCoordinate2D?
        private var lastMapTapAt: Date?

        init(
            onSelectSpot: @escaping (TourismSpot.ID) -> Void,
            onTapMap: ((CLLocationCoordinate2D) -> Void)?
        ) {
            self.onSelectSpot = onSelectSpot
            self.onTapMap = onTapMap
        }

        func renderMarkers(
            on mapView: TMapView,
            spots: [TourismSpot],
            selectedSpotID: TourismSpot.ID?,
            center: CLLocationCoordinate2D,
            currentLocation: CLLocationCoordinate2D?,
            currentHeadingDegrees: Double?,
            routeCoordinates: [CLLocationCoordinate2D],
            destinationCoordinate: CLLocationCoordinate2D?,
            zoomLevel: Int,
            mapInsets: UIEdgeInsets
        ) {
            let spotLayoutSignature = spots.map { "\($0.id):\($0.center.latitude):\($0.center.longitude)" }.joined(separator: "|")
            let currentLocationSignature = currentLocation.map { "\($0.latitude):\($0.longitude)" } ?? "none"
            let headingSignature = currentHeadingDegrees.map { "\(Int($0.rounded()))" } ?? "none"
            let routeSignature = routeCoordinates.map { "\($0.latitude):\($0.longitude)" }.joined(separator: "|")
            let destinationSignature = destinationCoordinate.map { "\($0.latitude):\($0.longitude)" } ?? "none"
            let signature = "\(spotLayoutSignature)-\(selectedSpotID ?? "")-\(currentLocationSignature)-\(headingSignature)-\(routeSignature)-\(destinationSignature)-\(zoomLevel)"
            guard lastSignature != signature else {
                return
            }

            lastSignature = signature
            let routeBoundsSignature = "\(routeSignature)-\(destinationSignature)"
            if lastRouteBoundsSignature != routeBoundsSignature {
                lastRouteBoundsSignature = routeBoundsSignature
                hasFitRouteBounds = false
                userDidInteractWithMap = false
            }
            let shouldFitBounds = lastSpotLayoutSignature != spotLayoutSignature
            lastSpotLayoutSignature = spotLayoutSignature
            updateCurrentLocationMarker(on: mapView, currentLocation: currentLocation, headingDegrees: currentHeadingDegrees)
            updateRouteOverlay(
                on: mapView,
                routeCoordinates: routeCoordinates,
                destinationCoordinate: destinationCoordinate
            )

            markers.forEach { $0.map = nil }
            markers.removeAll()

            if spots.isEmpty, routeCoordinates.isEmpty {
                mapView.setCenter(center)
                mapView.setZoom(zoomLevel)
                return
            }

            markers = spots.map { spot in
                let marker = TMapMarker(position: spot.center)
                marker.title = spot.name
                marker.icon = Self.markerImage(source: spot.source, isSelected: spot.id == selectedSpotID)
                marker.isUseImage = true
                marker.setCanShowCallout = true
                marker.setTapCallback { [weak self] _ in
                    self?.onSelectSpot(spot.id)
                }
                marker.map = mapView
                return marker
            }

            if currentLocation != nil, !hasCenteredOnCurrentLocation {
                centerOnCurrentLocationIfNeeded(mapView)
            } else if !routeCoordinates.isEmpty, !hasFitRouteBounds, !userDidInteractWithMap {
                hasFitRouteBounds = true
                fitRouteBounds(on: mapView, routeCoordinates: routeCoordinates, destinationCoordinate: destinationCoordinate, currentLocation: currentLocation, insets: mapInsets)
            } else if routeCoordinates.isEmpty,
                      !userDidInteractWithMap,
                      shouldFitBounds,
                      hasCenteredOnCurrentLocation || currentLocation == nil && markers.count > 1 {
                mapView.fitMapBoundsWithMarkers(markers, inset: mapInsets)
            } else if routeCoordinates.isEmpty,
                      !userDidInteractWithMap,
                      let selectedSpot = spots.first(where: { $0.id == selectedSpotID }) {
                mapView.animateTo(location: selectedSpot.center)
            }
        }

        private func updateCurrentLocationMarker(
            on mapView: TMapView,
            currentLocation: CLLocationCoordinate2D?,
            headingDegrees: Double?
        ) {
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
                currentLocationMarker.icon = Self.currentLocationImage(headingDegrees: headingDegrees)
                currentLocationMarker.map = mapView
            } else {
                let marker = TMapMarker(position: currentLocation)
                marker.title = "내 위치"
                marker.icon = Self.currentLocationImage(headingDegrees: headingDegrees)
                marker.isUseImage = true
                marker.setCanShowCallout = true
                marker.map = mapView
                currentLocationMarker = marker
            }
        }

        private func updateRouteOverlay(
            on mapView: TMapView,
            routeCoordinates: [CLLocationCoordinate2D],
            destinationCoordinate: CLLocationCoordinate2D?
        ) {
            let routeSignature = routeCoordinates.map { "\($0.latitude):\($0.longitude)" }.joined(separator: "|")
            let destinationSignature = destinationCoordinate.map { "\($0.latitude):\($0.longitude)" } ?? "none"
            let overlaySignature = "\(routeSignature)-\(destinationSignature)"
            if lastRouteOverlaySignature == overlaySignature {
                routePolyline?.map = mapView
                destinationMarker?.map = mapView
                return
            }

            lastRouteOverlaySignature = overlaySignature
            routePolyline?.map = nil
            routePolyline = nil
            destinationMarker?.map = nil
            destinationMarker = nil

            if routeCoordinates.count >= 2 {
                let polyline = TMapPolyline(coordinates: routeCoordinates)
                polyline.strokeColor = UIColor.systemBlue
                polyline.strokeWidth = 7
                polyline.opacity = 0.92
                polyline.showPriority = 1_000
                polyline.map = mapView
                routePolyline = polyline
            }

            if let destinationCoordinate {
                let marker = TMapMarker(position: destinationCoordinate)
                marker.title = "도착"
                marker.icon = Self.destinationImage()
                marker.isUseImage = true
                marker.setCanShowCallout = true
                marker.map = mapView
                destinationMarker = marker
            }
        }

        private func fitRouteBounds(
            on mapView: TMapView,
            routeCoordinates: [CLLocationCoordinate2D],
            destinationCoordinate: CLLocationCoordinate2D?,
            currentLocation: CLLocationCoordinate2D?,
            insets: UIEdgeInsets
        ) {
            var fitMarkers: [TMapMarker] = []
            if let currentLocationMarker {
                fitMarkers.append(currentLocationMarker)
            } else if let currentLocation {
                fitMarkers.append(TMapMarker(position: currentLocation))
            }
            if let destinationMarker {
                fitMarkers.append(destinationMarker)
            } else if let destinationCoordinate {
                fitMarkers.append(TMapMarker(position: destinationCoordinate))
            }

            if fitMarkers.count >= 2 {
                mapView.fitMapBoundsWithMarkers(fitMarkers, inset: insets)
            } else if let routePolyline {
                mapView.fitMapBoundsWithPolylines([routePolyline], inset: insets)
            } else if let first = routeCoordinates.first {
                mapView.setCenter(first)
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

        func mapViewWillStartPan(_ mapView: TMapView) {
            userDidInteractWithMap = true
        }

        func mapView(_ mapView: TMapView, singleTapOnMap location: CLLocationCoordinate2D) {
            handleMapTap(location)
        }

        func mapView(_ mapView: TMapView, singleTapOnMapWithoutTMapShape location: CLLocationCoordinate2D) {
            handleMapTap(location)
        }

        private func handleMapTap(_ location: CLLocationCoordinate2D) {
            userDidInteractWithMap = true

            let now = Date()
            if let lastMapTapAt,
               let lastMapTapCoordinate,
               now.timeIntervalSince(lastMapTapAt) < 0.2,
               Self.distance(from: lastMapTapCoordinate, to: location) < 0.5 {
                return
            }

            lastMapTapAt = now
            lastMapTapCoordinate = location
            onTapMap?(location)
        }

        private static func distance(
            from origin: CLLocationCoordinate2D,
            to destination: CLLocationCoordinate2D
        ) -> CLLocationDistance {
            CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        }

        func mapViewWillPinchIn(_ mapView: TMapView) {
            userDidInteractWithMap = true
        }

        func mapViewWillPinchOut(_ mapView: TMapView) {
            userDidInteractWithMap = true
        }

        func SKTMapApikeySucceed() {
            if let mapView = currentLocationMarker?.map {
                centerOnCurrentLocationIfNeeded(mapView)
            }
        }

        private static func currentLocationImage(headingDegrees: Double?) -> UIImage {
            let size = CGSize(width: 54, height: 54)
            let baseImage = UIGraphicsImageRenderer(size: size).image { context in
                let cgContext = context.cgContext
                cgContext.translateBy(x: size.width / 2, y: size.height / 2)

                cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: UIColor.black.withAlphaComponent(0.28).cgColor)
                UIColor.systemBlue.withAlphaComponent(0.22).setFill()
                UIBezierPath(ovalIn: CGRect(x: -19, y: -19, width: 38, height: 38)).fill()

                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor.systemBlue.withAlphaComponent(0.24).setFill()
                let directionCone = UIBezierPath()
                directionCone.move(to: CGPoint(x: 0, y: -26))
                directionCone.addLine(to: CGPoint(x: 12, y: -7))
                directionCone.addQuadCurve(to: CGPoint(x: -12, y: -7), controlPoint: CGPoint(x: 0, y: -2))
                directionCone.close()
                directionCone.fill()

                UIColor.systemBlue.setFill()
                UIBezierPath(ovalIn: CGRect(x: -10, y: -10, width: 20, height: 20)).fill()
                UIColor.white.setStroke()
                UIBezierPath(ovalIn: CGRect(x: -10, y: -10, width: 20, height: 20)).stroke()
            }

            guard let headingDegrees else {
                return baseImage
            }

            return UIGraphicsImageRenderer(size: size).image { context in
                let cgContext = context.cgContext
                cgContext.translateBy(x: size.width / 2, y: size.height / 2)
                cgContext.rotate(by: CGFloat(headingDegrees * .pi / 180))
                baseImage.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
            }
        }

        private static func markerImage(source: TourismSpot.Source, isSelected: Bool) -> UIImage {
            let size = CGSize(width: 44, height: 56)
            let fillColor: UIColor
            if isSelected {
                fillColor = .systemRed
            } else {
                switch source {
                case .mock:
                    fillColor = .systemOrange
                case .tourAPI:
                    fillColor = .systemGreen
                case .tmap:
                    fillColor = .systemPurple
                }
            }
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

        private static func destinationImage() -> UIImage {
            let size = CGSize(width: 42, height: 42)
            return UIGraphicsImageRenderer(size: size).image { context in
                let cgContext = context.cgContext
                cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: UIColor.black.withAlphaComponent(0.26).cgColor)
                UIColor.systemRed.setFill()
                UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 36, height: 36)).fill()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor.white.setFill()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 21, y: 10))
                path.addLine(to: CGPoint(x: 26, y: 20))
                path.addLine(to: CGPoint(x: 21, y: 32))
                path.addLine(to: CGPoint(x: 16, y: 20))
                path.close()
                path.fill()
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
    @State private var showsIndoorNavigationDebug = false
    @State private var isIndoorNavigationDebugCollapsed = false
    var onClose: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = max(geometry.size.width, 1)
            let safeHeight = max(geometry.size.height, 1)
            let isLogPanelVisible = appState.showsFullDebugLogs
            let bottomPanelHeight = isLogPanelVisible ? min(430, safeHeight * 0.48) : 0
            let navigationMapHeight = max(180, safeHeight / 3)
            let guidanceWidth = max(1, min(safeWidth - 48, 360))
            let guidanceCenterX = min(
                max(
                    safeWidth / 2 + appState.navigationGuidanceHorizontalOffsetRatio * safeWidth,
                    guidanceWidth / 2 + 16
                ),
                safeWidth - guidanceWidth / 2 - 16
            )
            let guidanceCenterY = max(
                116,
                min(safeHeight * 0.22, safeHeight - bottomPanelHeight - 120)
            )
            ZStack(alignment: .bottom) {
                ARViewContainer()
                    .frame(width: safeWidth, height: safeHeight)
                    .ignoresSafeArea()

                VStack {
	                    HStack {
                            if appState.isNavigationModeEnabled {
                                Button {
                                    appState.setIndoorDebugModeEnabled(false)
                                    onClose?()
                                } label: {
                                    Label("지도 복귀", systemImage: "chevron.left")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 8)
                                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(0.28), lineWidth: 1)
                                        )
                                }
                                .padding(.leading, 14)
                                .padding(.top, 14)
                            }
	                        DebugLogToggleButton(isExpanded: $appState.showsFullDebugLogs)
	                            .padding(.leading, appState.isNavigationModeEnabled ? 0 : 14)
	                            .padding(.top, 14)
                            if appState.isNavigationModeEnabled {
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        showsIndoorNavigationDebug.toggle()
                                    }
                                } label: {
                                    Label("실내 테스트", systemImage: "slider.horizontal.3")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 9)
                                        .background(.black.opacity(0.58), in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .padding(.top, 14)
                            }
	                        Spacer()
	                    }
	                    Spacer()
	                }
                .frame(width: safeWidth, height: safeHeight)
                .allowsHitTesting(true)

	                if !FeatureFlags.useARMapMVPDirection, let label = appState.arLabelOverlay {
		                    ARSpotLabelView(label: label)
		                        .position(
		                            x: label.normalizedX.screenCoordinate(in: safeWidth),
		                            y: label.normalizedY.screenCoordinate(in: safeHeight)
		                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.18), value: label)
                }

                if FeatureFlags.enableLegacyMatrixDebugOverlay,
                   appState.showsMatrixDebugMarker,
                   let debugOverlay = appState.matrixProjectionDebugOverlay {
		                    MatrixProjectionDebugMarkerView(overlay: debugOverlay)
		                        .position(
		                            x: debugOverlay.normalizedX.screenCoordinate(in: safeWidth),
		                            y: debugOverlay.normalizedY.screenCoordinate(in: safeHeight)
		                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.12), value: debugOverlay)
                }

                if FeatureFlags.enableLegacyOnScreenCandidateDebugMarkers,
                   appState.showsOnScreenCandidateDebugMarkers {
                    ForEach(appState.onScreenCandidateMarkerOverlays) { marker in
		                        OnScreenCandidateMarkerView(marker: marker)
		                            .position(
		                                x: marker.normalizedX.screenCoordinate(in: safeWidth),
		                                y: marker.normalizedY.screenCoordinate(in: safeHeight)
		                            )
                            .allowsHitTesting(false)
                            .animation(.easeOut(duration: 0.14), value: marker)
                    }
                }

                ForEach(appState.edgeMarkerOverlays) { marker in
		                    EdgeMarkerView(marker: marker)
		                        .position(
		                            x: marker.normalizedX.screenCoordinate(in: safeWidth),
		                            y: marker.normalizedY.screenCoordinate(in: safeHeight)
		                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.16), value: marker)
                }

                // 먼 거리(>30m) 목적지 2D 표시: 화면 안이면 라벨, 밖이면 가장자리 방향 지시(기존 EdgeMarkerView 재사용).
                if appState.isNavigationModeEnabled, let destination = appState.navigationDestinationOverlay {
                    EdgeMarkerView(marker: destination)
                        .position(
                            x: destination.normalizedX.screenCoordinate(in: safeWidth),
                            y: destination.normalizedY.screenCoordinate(in: safeHeight)
                        )
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.16), value: destination)
                }

	                // 길찾기 중 방향은 바닥 리본/회전 chevron이 담당하므로 상단 2D 방향 라벨은 평소 숨긴다.
	                // 도착 또는 위치/heading 불안정(좌우 확정 불가)일 때만 텍스트 배너로 표시한다.
	                if appState.isNavigationModeEnabled,
	                   appState.navigationGuidanceIsArrivalNearby || appState.navigationGuidanceIsConservative {
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

                if appState.isNavigationModeEnabled, showsIndoorNavigationDebug {
                    IndoorNavigationDebugPanel {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showsIndoorNavigationDebug = false
                        }
                    } onToggleCollapse: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isIndoorNavigationDebugCollapsed.toggle()
                        }
                    }
                        .environmentObject(appState)
                        .frame(width: max(1, min(safeWidth - 28, 390)))
                        // 상단 safe area(다이나믹 아일랜드/노치)만큼 내려 패널 상단이 가리지 않게 한다.
                        .position(
                            x: safeWidth / 2,
                            y: (isIndoorNavigationDebugCollapsed ? 122 : 176) + max(geometry.safeAreaInsets.top, 44)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 북 재보정 경고(§4-C): 나침반과 ARKit 월드 북이 지속 발산할 때 탭 → 세션 재고정. 상단.
                if appState.isNavigationModeEnabled,
                   appState.headingMiscalibrated || appState.isRecalibratingNorth {
                    Button {
                        appState.requestNorthRecalibration()
                    } label: {
                        Label(
                            appState.isRecalibratingNorth ? "방향 보정 중…" : "방향이 어긋난 듯해요 · 방향 보정",
                            systemImage: appState.isRecalibratingNorth ? "arrow.triangle.2.circlepath" : "location.north.line.fill"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(.orange.opacity(0.92), in: Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    }
                    .disabled(appState.isRecalibratingNorth)
                    .position(
                        x: safeWidth / 2,
                        y: max(geometry.safeAreaInsets.top, 44) + 28
                    )
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.18), value: appState.headingMiscalibrated)
                    .animation(.easeOut(duration: 0.18), value: appState.isRecalibratingNorth)
                }

                if isLogPanelVisible, !appState.radarMarkerOverlays.isEmpty {
                    RadarOverlayView(markers: appState.radarMarkerOverlays) { markerID in
                        if let spot = appState.spots.first(where: { $0.id == markerID }) {
                            appState.selectCandidate(spot)
                        }
                    }
                    .frame(width: max(1, min(safeWidth - 32, 360)), height: 150)
                    .padding(.bottom, bottomPanelHeight + 8)
                    .transition(.opacity)
                }

                if appState.isNavigationModeEnabled, !isLogPanelVisible {
                    NavigationRouteMiniMapView(
                        height: navigationMapHeight,
                        allowsIndoorMapTap: showsIndoorNavigationDebug || appState.isIndoorDebugModeEnabled
                    )
                        .environmentObject(appState)
                        .frame(width: safeWidth, height: navigationMapHeight)
                        // 2D 지도 상단 오른쪽: "다시 맞추기"(항상 위치/heading 보정, 실제 이탈 시에만 경로 재탐색).
                        .overlay(alignment: .topTrailing) {
                            VStack(alignment: .trailing, spacing: 6) {
                                if let quality = appState.navigationLocationQuality {
                                    Text(quality)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            (appState.navigationLocationIsAccurate ? Color.green : Color.orange).opacity(0.85),
                                            in: Capsule()
                                        )
                                }
                                Button {
                                    appState.requestReroute(manual: true)
                                } label: {
                                    Label(appState.isRerouting ? "재검색 중" : "다시 맞추기",
                                          systemImage: "location.circle")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.blue.opacity(0.9), in: Capsule())
                                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                                }
                                .disabled(appState.isRerouting)

                                if let notice = appState.navigationManualNotice {
                                    Text(notice)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.black.opacity(0.6), in: Capsule())
                                        .transition(.opacity)
                                }
                            }
                            .padding(10)
                            .animation(.easeOut(duration: 0.18), value: appState.navigationManualNotice)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isLogPanelVisible {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            APIKeyStatusView(statuses: appState.apiKeys.statuses)
                            if FeatureFlags.showCompactDebugDashboard {
                                DebugDashboardView(
                                    overviewRows: appState.debugOverviewRows,
                                    locationRows: appState.locationDebugRows,
                                    navigationRows: appState.navigationDebugRows
                                )
                            }
                            GeospatialStatusView(
                                status: appState.geospatialStatus,
                                coreLocationSnapshot: appState.latestCoreLocationSnapshot,
                                geospatialSnapshot: appState.latestGeospatialLocationSnapshot
                            )

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

                            Button("도감 열기") {
                                showsCollection = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .frame(width: safeWidth, alignment: .leading)
                    }
                    .frame(width: safeWidth)
                    .frame(maxHeight: bottomPanelHeight)
                    .background(.regularMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showsCollection) {
            CollectionBookView(spots: appState.spots, selectedSpot: appState.selectedSpot)
        }
    }
}

private struct NavigationRouteMiniMapView: View {
    @EnvironmentObject private var appState: AppState
    let height: CGFloat
    let allowsIndoorMapTap: Bool

    private var destinationSpot: TourismSpot? {
        appState.navigationDestinationSpot
    }

    private var route: TMAPPedestrianRoute? {
        guard let destinationSpot else {
            return nil
        }

        return appState.tmapArrivalRoutesBySpotID[destinationSpot.id]
    }

    private var currentLocation: CLLocationCoordinate2D? {
        if appState.isIndoorDebugModeEnabled {
            return appState.latestLocationSnapshot?.coordinate
                ?? appState.latestGeospatialLocationSnapshot?.coordinate
                ?? appState.latestCoreLocationSnapshot?.coordinate
        }

        return appState.latestCoreLocationSnapshot?.coordinate
            ?? appState.latestGeospatialLocationSnapshot?.coordinate
            ?? appState.latestLocationSnapshot?.coordinate
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        if let route, route.routeCoordinates.count >= 2 {
            return route.routeCoordinates
        }

        guard let currentLocation, let destinationSpot else {
            return []
        }

        return [currentLocation, destinationSpot.center]
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        route?.arrivalCoordinate ?? destinationSpot?.center
    }

    private var mapCenter: CLLocationCoordinate2D {
        currentLocation ?? destinationCoordinate ?? destinationSpot?.center ?? CLLocationCoordinate2D(latitude: 35.1796, longitude: 129.0756)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TMAPNativeMapView(
                apiKey: appState.apiKeys.tmap,
                spots: destinationSpot.map { [$0] } ?? [],
                selectedSpotID: destinationSpot?.id,
                center: mapCenter,
                currentLocation: currentLocation,
                currentHeadingDegrees: appState.cameraHeadingDegrees,
                routeCoordinates: routeCoordinates,
                destinationCoordinate: destinationCoordinate,
                isInteractionEnabled: true,
                zoomLevel: 17,
                mapInsets: UIEdgeInsets(top: 24, left: 24, bottom: 28, right: 24),
                onSelectSpot: { _ in },
                onTapMap: { coordinate in
                    guard allowsIndoorMapTap else {
                        return
                    }
                    appState.recordIndoorNavigationMapTapLocation(coordinate)
                }
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(destinationSpot?.name ?? "목적지")
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                Text(route == nil ? "경로 준비 중" : "TMAP 도착 좌표 표시")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
        .frame(height: height)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.28))
                .frame(height: 1)
        }
    }
}

private struct IndoorNavigationDebugPanel: View {
    @EnvironmentObject private var appState: AppState
    let onClose: () -> Void
    let onToggleCollapse: () -> Void
    @State private var isCollapsed = false

    private var selectedSpot: TourismSpot? {
        if let id = appState.indoorDebugSelectedSpotID,
           let spot = appState.spots.first(where: { $0.id == id }) {
            return spot
        }

        return appState.navigationDestinationSpot ?? appState.selectedSpot ?? appState.spots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: appState.isIndoorDebugModeEnabled ? "location.fill" : "location.slash")
                    .foregroundStyle(appState.isIndoorDebugModeEnabled ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("실내 길찾기 디버그")
                        .font(.subheadline.weight(.semibold))
                    Text("하단 2D 지도를 탭해 내 위치를 주입하고, heading은 실제 기기 값을 사용합니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isCollapsed.toggle()
                    onToggleCollapse()
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel(isCollapsed ? "실내 테스트 패널 펼치기" : "실내 테스트 패널 접기")

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("실내 테스트 패널 닫기")
            }

            if isCollapsed {
                compactArrowStatus
            } else {
                expandedContent
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private var compactArrowStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill((appState.arrivalPin != nil || appState.navigationDestinationOverlay != nil) ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(appState.arrivalPin != nil
                 ? "목적지 핀(근거리)"
                 : (appState.navigationDestinationOverlay != nil ? "목적지 표시(원거리)" : "목적지 안내 없음"))
                .font(.caption.weight(.bold))
            Spacer(minLength: 0)
            Text(appState.cameraHeadingDegrees.map { "heading \(Int($0))도" } ?? "heading 대기")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var expandedContent: some View {
        Group {
            Menu {
                ForEach(Array(appState.spots.prefix(80))) { spot in
                    Button(spot.name) {
                        appState.selectIndoorNavigationDebugDestination(spot)
                    }
                }
            } label: {
                HStack {
                    Text(selectedSpot?.name ?? "목적지 선택")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                Image(systemName: appState.pendingIndoorDebugMapTapCoordinate == nil ? "hand.tap" : "mappin.and.ellipse")
                    .foregroundStyle(appState.pendingIndoorDebugMapTapCoordinate == nil ? Color.secondary : Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.pendingIndoorDebugMapTapCoordinate == nil ? "하단 2D 지도에서 내 위치를 탭하세요." : "탭 위치 저장됨")
                        .font(.caption.weight(.semibold))
                    if let coordinate = appState.pendingIndoorDebugMapTapCoordinate {
                        Text(Self.coordinateText(coordinate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("적용 전까지 실제 위치와 경로는 변경되지 않습니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            Text(appState.indoorDebugStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $appState.indoorDebugSimulatesPoorAccuracy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("정확도 저하 시뮬레이션")
                        .font(.caption.weight(.semibold))
                    Text("실내에서 GPS 오차 원을 키워 위치 불안정 안내(3.6)를 검증합니다. 적용 시 반영됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
            .tint(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            Toggle(isOn: $appState.prefersHighResolutionCamera) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("고해상도 카메라")
                        .font(.caption.weight(.semibold))
                    Text("기본은 저해상도(발열 절감). 켜면 고해상도로 전환되며 발열이 늘 수 있습니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
            .tint(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            Text(appState.navigationStabilityDiagnostics)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill((appState.arrivalPin != nil || appState.navigationDestinationOverlay != nil) ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.arrivalPin != nil
                         ? "목적지 핀(근거리)"
                         : (appState.navigationDestinationOverlay != nil ? "목적지 표시(원거리)" : "목적지 안내 없음"))
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                }

                Text(appState.routeArrowDiagnostics)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(appState.routeArrowComputationDiagnostics)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(appState.routeArrowRenderDiagnostics)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button {
                    appState.applyPendingIndoorNavigationMapTapLocation()
                } label: {
                    Label("적용", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.pendingIndoorDebugMapTapCoordinate == nil)

                Button {
                    appState.setIndoorDebugModeEnabled(false)
                    onClose()
                } label: {
                    Label("실내 테스트 종료", systemImage: "location")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private static func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude.formatted(.number.precision(.fractionLength(6)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(6))))"
    }
}

private struct DebugLogToggleButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            Label(isExpanded ? "로그 닫기" : "로그 열기", systemImage: isExpanded ? "doc.text.magnifyingglass" : "doc.text")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "로그 닫기" : "로그 열기")
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
	                        x: marker.normalizedX.screenCoordinate(in: geometry.size.width),
	                        y: marker.normalizedY.screenCoordinate(in: geometry.size.height)
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
    let navigationRows: [DebugStatusRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("테스트 로그 요약")
                .font(.caption.weight(.semibold))

            DebugStatusRowsView(rows: overviewRows)

            // 내비게이션/VPS 실측에 필요한 그룹만 표시한다(인식기 잔재 데이터/표시/3D 그룹은 제외).
            VStack(alignment: .leading, spacing: 10) {
                DebugStatusGroupView(title: "위치/VPS", rows: locationRows)
                DebugStatusGroupView(title: "내비", rows: navigationRows)
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
        viewController.onTrackingStateChanged = { limited, reason in
            appState.updateARTrackingState(limited: limited, reason: reason)
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: ARSessionViewController, context: Context) {
        uiViewController.setShows3DGeospatialDebugMarker(appState.shows3DGeospatialDebugMarker)
        uiViewController.setPrefersHighResolutionCamera(appState.prefersHighResolutionCamera)
        uiViewController.setArrivalPin(appState.arrivalPin)
        // 북 재보정(§4-C): requestID가 바뀐 경우에만 세션을 리셋 재실행해 월드 북을 다시 고정한다.
        uiViewController.applyRecalibrationIfNeeded(requestID: appState.northRecalibrationRequestID)
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

private extension Double {
    func screenCoordinate(in length: CGFloat) -> CGFloat {
        guard isFinite, length.isFinite, length > 0 else {
            return 0
        }

        let clamped = min(max(self, 0), 1)
        return CGFloat(clamped) * length
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
