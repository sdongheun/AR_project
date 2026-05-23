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
                TextField("예: 투썸플레이스, 올리브영, 후참잘", text: $appState.cameraTextInput)
                    .textFieldStyle(.roundedBorder)
            }

            RecognitionSignalSection(
                title: "2. VPS/위치 후보",
                caption: "현재 위치와 ARCore VPS가 근처라고 판단한 건물 후보입니다."
            ) {
                Picker("위치 신뢰도", selection: $appState.locationConfidence) {
                    ForEach(RecognitionConfidence.allCases) { confidence in
                        Text(confidence.displayName).tag(confidence)
                    }
                }
                .pickerStyle(.segmented)

                Picker("VPS 후보 건물", selection: $appState.vpsNearbySpotID) {
                    Text("VPS 후보 없음").tag(Optional<TourismSpot.ID>.none)
                    ForEach(appState.spots) { spot in
                        Text(spot.name).tag(Optional(spot.id))
                    }
                }
                .pickerStyle(.menu)
            }

            RecognitionSignalSection(
                title: "3. 브이월드 Polygon 후보",
                caption: "건물 주소/공간 범위가 일치한다고 보는 후보입니다. 현재는 수동 목업 선택입니다."
            ) {
                Picker("Polygon 일치 건물", selection: $appState.polygonValidatedSpotID) {
                    Text("Polygon 후보 없음").tag(Optional<TourismSpot.ID>.none)
                    ForEach(appState.spots) { spot in
                        Text(spot.name).tag(Optional(spot.id))
                    }
                }
                .pickerStyle(.menu)
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
