import SwiftUI

struct MVPRecognitionControlView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("테스트 제어")
                .font(.subheadline.weight(.semibold))

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
                    Picker(
                        "대상 POI",
                        selection: Binding(
                            get: { appState.indoorDebugSelectedSpotID ?? appState.spots.first?.id ?? "" },
                            set: { appState.selectIndoorDebugSpot(id: $0) }
                        )
                    ) {
                        ForEach(appState.spots.prefix(80)) { spot in
                            Text(spot.name)
                                .tag(spot.id)
                        }
                    }
                    .font(.caption)
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

            RecognitionSignalSection(
                title: "디버그 표시",
                caption: "기본 화면은 현장 테스트용으로 축약합니다. 필요할 때만 상세 로그를 켭니다."
            ) {
                Toggle("matrix 마커 표시", isOn: $appState.showsMatrixDebugMarker)
                    .font(.caption)
                Toggle("핑크/주황 후보 마커 표시", isOn: $appState.showsOnScreenCandidateDebugMarkers)
                    .font(.caption)
                Toggle("3D 지리 앵커 마커 표시", isOn: $appState.shows3DGeospatialDebugMarker)
                    .font(.caption)
                Toggle("전체 로그 보기", isOn: $appState.showsFullDebugLogs)
                    .font(.caption)
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
                                Text(log)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
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
                }

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
