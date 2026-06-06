import SwiftUI

struct MVPRecognitionControlView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsIndoorDebugSpotList = false
    @State private var showsNavigationDestinationList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("테스트 제어")
                .font(.subheadline.weight(.semibold))

            if FeatureFlags.enableIndoorDebugControls {
                RecognitionSignalSection(
                    title: "해운대 TourAPI 실내 디버그",
                    caption: "실제 GPS/VPS 대신 해운대 TourAPI POI 주변의 가상 위치와 heading을 주입해 계산 로직을 검증합니다."
                ) {
                    Toggle(
                        "실내 디버그 모드",
                        isOn: Binding(
                            get: { appState.isIndoorDebugModeEnabled },
                            set: { appState.setIndoorDebugModeEnabled($0) }
                        )
                    )
                    .font(.caption)

                    Button("해운대 TourAPI 후보 불러오기") {
                        Task {
                            await appState.loadHaeundaeTourAPIDebugSpots()
                        }
                    }
                    .buttonStyle(.bordered)

                    if !appState.spots.isEmpty {
                        IndoorDebugSpotSelector(
                            title: "대상 POI",
                            spots: Array(appState.spots.prefix(120)),
                            selectedSpotID: appState.indoorDebugSelectedSpotID ?? appState.spots.first?.id,
                            isExpanded: $showsIndoorDebugSpotList
                        ) { spot in
                            appState.selectIndoorDebugSpot(id: spot.id)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(IndoorDebugScenario.allCases) { scenario in
                            Button(scenario.title) {
                                appState.applyIndoorDebugScenario(scenario)
                            }
                            .buttonStyle(.bordered)
                            .tint(appState.indoorDebugScenario == scenario ? .blue : .secondary)
                            .font(.caption)
                        }
                    }

                    Text(appState.indoorDebugStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if FeatureFlags.enableNavigationRouteControls {
                RecognitionSignalSection(
                    title: "길찾기",
                    caption: "목적지를 직접 입력하면 TMAP 검색 결과를 기반으로 보행자 경로와 도착 좌표를 준비합니다."
                ) {
                    Toggle(
                        "길찾기 모드",
                        isOn: Binding(
                            get: { appState.isNavigationModeEnabled },
                            set: { appState.setNavigationModeEnabled($0) }
                        )
                    )
                    .font(.caption)

                    if appState.isNavigationModeEnabled {
                        HStack(spacing: 8) {
                            TextField("예: 투썸플레이스, 신세계백화점 센텀시티점", text: $appState.navigationSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .submitLabel(.search)
                                .onSubmit {
                                    appState.searchNavigationDestinationFromInput()
                                }

                            Button("검색") {
                                appState.searchNavigationDestinationFromInput()
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption.weight(.semibold))
                        }

                        Text(appState.navigationSearchStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        if !appState.navigationSearchResults.isEmpty {
                            TMAPSearchResultListView(
                                results: Array(appState.navigationSearchResults.prefix(3)),
                                selectedSpotID: appState.navigationDestinationSpotID
                            ) { result in
                                appState.selectNavigationSearchResult(result)
                            }
                        }

                        IndoorDebugSpotSelector(
                            title: "목업/후보에서 선택",
                            spots: appState.spots,
                            selectedSpotID: appState.navigationDestinationSpotID,
                            isExpanded: $showsNavigationDestinationList
                        ) { spot in
                            appState.selectNavigationDestination(spot)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.navigationGuidanceTitle)
                                .font(.headline.weight(.semibold))
                            Text(appState.navigationGuidanceDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        Text(appState.routeArrowDiagnostics)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        if appState.showsFullDebugLogs {
                            Text(appState.routeArrowComputationDiagnostics)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(appState.routeArrowRenderDiagnostics)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if FeatureFlags.enableLegacyMatrixDebugOverlay ||
                FeatureFlags.enableLegacyOnScreenCandidateDebugMarkers ||
                FeatureFlags.enableLegacyGeospatial3DMarkers ||
                FeatureFlags.enableLegacyFullDebugLogs {
                RecognitionSignalSection(
                    title: "디버그 표시",
                    caption: "기본 화면은 현장 테스트용으로 축약합니다. 필요할 때만 상세 로그를 켭니다."
                ) {
                    if FeatureFlags.enableLegacyMatrixDebugOverlay {
                        Toggle("matrix 마커 표시", isOn: $appState.showsMatrixDebugMarker)
                            .font(.caption)
                    }
                    if FeatureFlags.enableLegacyOnScreenCandidateDebugMarkers {
                        Toggle("핑크/주황 후보 마커 표시", isOn: $appState.showsOnScreenCandidateDebugMarkers)
                            .font(.caption)
                    }
                    if FeatureFlags.enableLegacyGeospatial3DMarkers {
                        Toggle("3D 지리 앵커 마커 표시", isOn: $appState.shows3DGeospatialDebugMarker)
                            .font(.caption)
                    }
                    if FeatureFlags.enableLegacyFullDebugLogs {
                        Toggle("전체 로그 보기", isOn: $appState.showsFullDebugLogs)
                            .font(.caption)
                    }
                }
            }

            if appState.showsFullDebugLogs {
                RecognitionSignalSection(
                    title: "1. 위치/방향 상세",
                    caption: "현재 기준 위치, heading, pose, local ENU를 확인합니다."
                ) {
                    DebugRowsBlock(rows: appState.locationDebugRows)

                    if let heading = appState.cameraHeadingDegrees {
                        Text("카메라 heading: \(Int(heading))도")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    DetailedLogText(title: "방향 후보", text: appState.cameraDirectionStatus)
                    DetailedLogText(title: "heading", text: appState.cameraHeadingDiagnostics)
                    DetailedLogText(title: "pose", text: appState.cameraPoseDiagnostics)
                    DetailedLogText(title: "matrix", text: appState.cameraProjectionDiagnostics)
                    DetailedLogText(title: "local ENU", text: appState.localCoordinateDiagnostics)

                    if let lastUpdatedAt = appState.cameraHeadingLastUpdatedAt {
                        Text("마지막 heading 갱신: \(lastUpdatedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                RecognitionSignalSection(
                    title: "2. VPS/위치 정확도",
                    caption: "VPS는 건물 후보를 고르는 신호가 아니라 현재 위치/방향 정확도를 보정하는 신호입니다."
                ) {
                    Text("위치 신뢰도: \(appState.locationConfidence.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("점수화 반영 신뢰도: \(appState.effectiveSpatialConfidence.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(appState.spatialTrackingDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(appState.geospatialStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if FeatureFlags.enableVWorldPolygonDebugUI {
                    RecognitionSignalSection(
                        title: "3. 브이월드 Polygon",
                        caption: "POI 주변 Polygon 조회 상태와 선택 근거를 확인합니다."
                    ) {
                        DebugRowsBlock(rows: appState.dataDebugRows)
                        DetailedLogText(title: "정렬", text: appState.spatialAlignmentDiagnostics)

                        if let startedAt = appState.polygonLookupStartedAt {
                            Text("조회 시작: \(startedAt.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let finishedAt = appState.polygonLookupFinishedAt {
                            Text("조회 완료: \(finishedAt.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if !appState.polygonLookupLogs.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("브이월드 응답 로그")
                                    .font(.caption2.weight(.semibold))
                                ForEach(Array(appState.polygonLookupLogs.enumerated()), id: \.offset) { _, log in
                                    PolygonLogLineView(log: log)
                                }
                            }
                        }
                    }
                }

                RecognitionSignalSection(
                    title: "4. 화면 투영/2D 표시",
                    caption: "화면 안/밖 여부, matrix 투영, edge marker 상태를 확인합니다."
                ) {
                    DebugRowsBlock(rows: appState.displayDebugRows)
                    DetailedLogText(title: "Polygon 화면 투영", text: appState.polygonProjectionDiagnostics)
                    DetailedLogText(title: "Matrix 비교", text: appState.matrixProjectionComparisonDiagnostics)
                    DetailedLogText(title: "2D 라벨", text: appState.arLabelOverlayDiagnostics)
                    DetailedLogText(title: "길찾기 화살표 계산", text: appState.routeArrowComputationDiagnostics)
                    DetailedLogText(title: "길찾기 화살표 렌더", text: appState.routeArrowRenderDiagnostics)
                }

                if FeatureFlags.enableLegacy3DAnchorDebugUI {
                    RecognitionSignalSection(
                        title: "5. 3D Anchor/라벨",
                        caption: "외벽 후보점, 라벨 높이, WGS84 Anchor 생성 상태를 확인합니다."
                    ) {
                        DebugRowsBlock(rows: appState.anchorDebugRows)
                        DetailedLogText(title: "외벽 후보", text: appState.buildingFacadeAnchorDiagnostics)
                        DetailedLogText(title: "높이", text: appState.buildingLabelHeightDiagnostics)
                        DetailedLogText(title: "WGS84 후보", text: appState.geospatialWGS84CandidateDiagnostics)
                        DetailedLogText(title: "WGS84 앵커", text: appState.geospatialAnchorStateDiagnostics)
                    }
                }

                RecognitionSignalSection(
                    title: "6. 화면 Overlay 라벨 원문",
                    caption: "인식된 후보를 현재 화면 좌표에 표시합니다."
                ) {
                    Text(appState.arLabelOverlayDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("건물 인식 실행") {
                    appState.runRecognition()
                }
                .buttonStyle(.borderedProminent)

                Button("투썸 건물 샘플") {
                    appState.runMockRecognition()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct RecognitionSignalSection<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct IndoorDebugSpotSelector: View {
    let title: String
    let spots: [TourismSpot]
    let selectedSpotID: TourismSpot.ID?
    @Binding var isExpanded: Bool
    let onSelect: (TourismSpot) -> Void

    private var selectedSpot: TourismSpot? {
        guard let selectedSpotID else {
            return nil
        }

        return spots.first(where: { $0.id == selectedSpotID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedSpot?.name ?? "선택 없음")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer()
                    Text("\(spots.count)개")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(spots) { spot in
                            Button {
                                onSelect(spot)
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    isExpanded = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: spot.id == selectedSpotID ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(spot.id == selectedSpotID ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(spot.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(spot.address)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    spot.id == selectedSpotID
                                        ? Color.blue.opacity(0.12)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 230)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }
}

private struct DebugRowsBlock: View {
    let rows: [DebugStatusRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 6) {
                    Text(row.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 58, alignment: .leading)
                    Text(row.value)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct TMAPSearchResultListView: View {
    let results: [TMAPPOISearchResult]
    let selectedSpotID: TourismSpot.ID?
    let onSelect: (TMAPPOISearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TMAP 검색 결과")
                .font(.caption.weight(.semibold))

            ForEach(results) { result in
                TMAPSearchResultRowView(
                    result: result,
                    isSelected: "tmap-\(result.id)" == selectedSpotID
                ) {
                    onSelect(result)
                }
            }
        }
    }
}

private struct TMAPSearchResultRowView: View {
    let result: TMAPPOISearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.caption.weight(.semibold))
                Text(result.address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(coordinateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .blue : .secondary)
    }

    private var coordinateText: String {
        "\(String(format: "%.6f", result.coordinate.latitude)), \(String(format: "%.6f", result.coordinate.longitude))"
    }
}

private struct DetailedLogText: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.top, 2)
    }
}

private struct PolygonLogLineView: View {
    let log: String

    var body: some View {
        if log.isEmpty {
            Divider()
                .padding(.vertical, 2)
        } else if log.hasPrefix("────") {
            Text(log)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.top, 4)
                .textSelection(.enabled)
        } else {
            Text(log)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
