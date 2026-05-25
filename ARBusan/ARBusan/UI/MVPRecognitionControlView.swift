import SwiftUI

struct MVPRecognitionControlView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("건물 인식 MVP 입력")
                .font(.subheadline.weight(.semibold))

            RecognitionSignalSection(
                title: "1. OCR 입력",
                caption: "카메라가 읽은 간판/상호 텍스트입니다. 자동 인식이 안 되면 직접 입력합니다."
            ) {
                TextField("예: 투썸플레이스, 올리브영, 후참잘, 더존 101", text: $appState.cameraTextInput)
                    .textFieldStyle(.roundedBorder)
            }

            RecognitionSignalSection(
                title: "2. 카메라 방향 후보",
                caption: "내 위치와 카메라 heading을 김해 목업 건물 좌표와 비교해 자동 계산한 후보입니다."
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

                Text(appState.spatialAlignmentDiagnostics)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(appState.polygonProjectionDiagnostics)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

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
                title: "5. Scene Semantics 점수 보정",
                caption: "목업과 TourAPI 후보 모두 VWorld Polygon이 확보되면 화면 투영 영역의 building 비율로 같은 방식의 점수 보정을 받습니다."
            ) {
                Text(appState.sceneSemanticsScoringDiagnostics)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
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
