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
                    title: "1. OCR 입력",
                    caption: "카메라가 읽은 간판/상호 텍스트입니다. 자동 인식이 안 되면 직접 입력합니다."
                ) {
                    TextField("예: 투썸플레이스, 올리브영, 후참잘, 더존 101", text: $appState.cameraTextInput)
                        .textFieldStyle(.roundedBorder)
                }

                RecognitionSignalSection(
                    title: "2. 카메라 방향 후보",
                    caption: "내 위치와 카메라 heading을 테스트 목업 건물 좌표와 비교해 자동 계산한 후보입니다."
                ) {
                    Text(appState.cameraDirectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let heading = appState.cameraHeadingDegrees {
                        Text("카메라 heading: \(Int(heading))도")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(appState.cameraHeadingDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(appState.cameraPoseDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(appState.cameraProjectionDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(appState.spatialAlignmentDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(appState.localCoordinateDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(appState.polygonProjectionDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(appState.matrixProjectionComparisonDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(appState.buildingFacadeAnchorDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(appState.buildingLabelHeightDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("WGS84 후보: \(appState.geospatialWGS84CandidateDiagnostics)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("WGS84 앵커 상태: \(appState.geospatialAnchorStateDiagnostics)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if let lastUpdatedAt = appState.cameraHeadingLastUpdatedAt {
                        Text("마지막 heading 갱신: \(lastUpdatedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                RecognitionSignalSection(
                    title: "3. VPS/위치 정확도",
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
                    title: "4. 브이월드 Polygon 자동 후보",
                    caption: "현재는 목업 좌표와 카메라 방향으로 자동 계산합니다. 실제 브이월드 Polygon 조회는 다음 단계입니다."
                ) {
                    Text(appState.polygonValidationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                    title: "5. Scene Semantics 라벨 보정",
                    caption: "Scene Semantics는 인식 점수에 반영하지 않습니다. building 영역이 잡히면 라벨 위치 보정과 디버그에만 사용합니다."
                ) {
                    Text(appState.sceneSemanticsScoringDiagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                RecognitionSignalSection(
                    title: "6. 화면 Overlay 라벨",
                    caption: "인식된 후보를 현재 화면 좌표에 표시합니다. Scene Semantics building 영역이 있으면 라벨 위치를 그쪽으로 보정합니다."
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
