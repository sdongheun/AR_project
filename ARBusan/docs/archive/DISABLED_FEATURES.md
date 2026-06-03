# ARBusan 비활성화 기능 정리

현재 목표는 3D 지리 앵커와 라벨 위치 검증이다. 발열과 배터리 부담을 줄이기 위해 아래 기능은 일시적으로 꺼둔다.

## 비활성화 중

- Scene Semantics
  - 이유: 건물/하늘/도로 분할 결과가 현재 라벨 정확도에 크게 기여하지 않았고, 프레임별 추론 비용이 크다.
  - 위치: `GeospatialSessionManager`
  - 현재 상태: ARCore semantic mode를 켜지 않음.

- Scene Semantics overlay
  - 이유: Scene Semantics를 끈 상태에서는 화면 컬러 오버레이도 필요 없다.
  - 위치: `ARExploreView`
  - 현재 상태: semantic overlay image를 화면에 그리지 않음.

- ARKit scene reconstruction mesh
  - 이유: 현재 3D 라벨 MVP는 WGS84/Terrain anchor 기반이며 mesh를 직접 사용하지 않는다.
  - 위치: `ARSessionViewController`
  - 현재 상태: `configuration.sceneReconstruction = .mesh` 설정 제거.

- 실시간 OCR
  - 이유: 현재 단계는 3D 라벨 위치 검증이며, OCR은 프레임 기반 Vision 처리로 발열 부담이 크다.
  - 위치: `ARSessionViewController`
  - 현재 상태: `shouldRunLiveOCR = false`로 프레임별 OCR 실행 차단.

## 다시 켤 때 기준

- Scene Semantics: 라벨을 건물 영역에만 붙이는 보조 로직을 다시 검증할 때.
- Scene reconstruction mesh: 근거리 건물 표면 또는 깊이 기반 보정이 필요할 때.
- OCR: 간판 기반 자동 후보 선택을 다시 테스트할 때.

