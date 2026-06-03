# ARBusan 3D Label Refinement Plan

`ARBusan_EDGE_MARKER_RULES.md`의 하위 계획 문서다. 여기에는 3D 구체/라벨을 계속 개선하기 위해 다음 작업자가 꼭 알아야 할 결정과 순서만 남긴다.

## 1. 현재 상태

- 목업 POI + VWorld Polygon으로 건물 외곽 좌표를 가져온다.
- 카메라 시야 방향 기준으로 Polygon 외벽 후보점을 계산한다.
- RealityKit `AnchorEntity + ModelEntity`로 3D 구체와 텍스트 라벨을 표시한다.
- Terrain Anchor는 김해 테스트에서 `errorUnsupportedLocation`이 반복되어 현재는 보류한다.
- 현재 3D 고정 기준은 WGS84 Anchor를 메인으로 사용한다.
- 3D 라벨은 billboard 처리로 카메라를 향하게 한다.
- RealityKit Entity에 collision shape를 붙이고 `ARView.entity(at:)` hit-test로 구체/라벨 탭 처리를 한다.
- 구체/라벨 탭 시 선택 상태가 토글되고, 선택된 마커는 최대 크기 제한 안에서 확대된다.
- 구체/라벨은 거리감을 유지하되, 가까울 때 너무 크고 20~30m에서 너무 작아지는 문제를 줄이기 위해 거리 구간별 scale 보정을 적용한다.
- 같은 건물 안에서 외벽 후보점이 바뀌면 RealityKit anchor transform을 즉시 이동하지 않고 거리별 smoothing으로 따라가게 한다.
- 같은 건물의 외벽 후보점 이동은 WGS84 anchor를 재생성하지 않고, 기준 WGS84 anchor 아래 RealityKit child content offset을 이동시킨다.
- 현재 위치 기준 3D 표시 범위 안에 여러 건물이 있으면 건물별 WGS84 anchor를 동시에 유지한다.
- Scene Semantics와 OCR은 발열 감소를 위해 비활성화했다.

## 2. 확정 규칙

### 2.1 외벽 후보 선택

- 기본은 `카메라 ray가 Polygon 외벽과 교차하면 교차점, 아니면 ray에 가장 가까운 외벽점`이다.
- 대각선/모서리에서 후보가 흔들리면 이전 외벽을 유지하는 안정화가 필요하다.
- 주변 건물이 적으면 카메라 ray 기준이 자연스럽다.
- 도심처럼 건물이 붙어 있으면 옆면보다 정문/입구 쪽 외벽을 우선해야 할 수 있다.
- 현재 목업에는 정문 데이터가 없으므로 MVP는 ray 기준으로 시작하고, 추후 `frontHeading`, `entranceCoordinate`, `preferredFacade` 같은 메타데이터를 고려한다.

### 2.2 라벨 높이

```text
0~5m: 눈높이, 약 1.5~1.8m
5~30m: 중거리, 약 3~4m
30~120m: 장거리 시야, 약 5m
120m~1km: 원거리, 3D 숨김 + 2D 방향/거리 overlay
```

- 건물 높이가 있으면 위 값을 건물 높이의 약 60% 이내로 제한한다.
- 건물 높이가 없으면 거리별 fallback 높이를 사용한다.
- 건물형은 `내 위치 -> 가장 가까운 외벽 지점` 거리를 기준으로 한다.
- 비건물형은 Polygon이 없으므로 `내 위치 -> TourAPI POI 좌표점` 거리를 기준으로 한다.
- 3D 생성/삭제는 깜빡임 방지를 위해 hysteresis를 적용한다. 새 3D는 `120m 이내`에서 생성하고, 이미 생성된 3D는 `140m 밖`으로 벗어나기 전까지 유지한다.

### 2.3 크기 정책

- 기본은 실제 거리감을 유지한다.
- 다만 20~30m 거리에서 구체/텍스트가 너무 작아지지 않도록 구간별 scale 보정을 적용한다.
- 구체 기본 radius와 텍스트/배경판 크기를 1차 상향했다.
- 구체 scale: `0~5m 0.65x`, `5~15m 1.0x`, `15~30m 1.35x`, `30m+ 1.6x`
- 라벨 scale: `0~5m 0.9x`, `5~15m 1.1x`, `15~30m 1.5x`, `30m+ 1.85x`
- 탭 시 선택 마커만 확대한다.
- 탭 확대는 구체보다 텍스트/카드 중심으로 키운다.
- 확대 해제는 다시 탭하거나 화면 다른 곳을 탭하면 처리한다.
- 화면을 과하게 가리지 않도록 구체/라벨 최대 크기 제한을 적용한다.

### 2.4 Anchor 전략

- 현재 메인: WGS84 Anchor
- fallback: Local AR 임시 표시
- 보류: Terrain Anchor, Rooftop Anchor, Streetscape attached anchor
- Terrain Anchor는 안정화 이후 시간이 남으면 부산 현장 테스트에서 다시 검토한다.
- WGS84는 절대고도 오차가 있으므로 현장에서 실제 높이 차이를 계속 기록한다.
- 같은 건물의 WGS84 anchor가 갱신되어도 3D Entity는 유지하고 transform 위치만 부드럽게 보간한다.
- 거리별 transform smoothing: `0~5m 20%`, `5~30m 30%`, `30~120m 15%`, 큰 점프 12m 이상은 `55%`로 빠르게 따라간다.
- 현재 구조는 `건물별 WGS84 기준 anchor + 구체/라벨 child Entity offset 이동`이다.
- 같은 건물에서 외벽 후보점이 바뀌면 anchor를 새로 생성하지 않고 child position만 보간한다.
- 120m 생성/140m 삭제 hysteresis 범위 안에 여러 건물이 있으면 최대 5개까지 WGS84 anchor와 RealityKit 노드를 동시에 유지한다.

### 2.5 거리별 UX

```text
0~5m:
    눈높이 근처 3D 라벨
    구체/라벨이 화면을 가리지 않게 제한

5~30m:
    3D 외벽 라벨 메인
    2D overlay와 edge marker는 보조

30~120m:
    사람이 대상을 볼 수는 있지만 식별이 어려운 구간
    3D 외벽 라벨은 유지하되 약 5m 높이로 고정
    2D 방향/거리 overlay와 edge marker를 보조로 사용

120m~1km:
    3D 구체/라벨 숨김
    2D 방향/거리 overlay와 edge marker 메인
    단, 이미 생성된 3D는 140m 밖으로 벗어나기 전까지 유지

1km 이상:
    후보 표시 대상에서 제외하거나 방향 안내만 제한적으로 제공
```

### 2.6 건물형/비건물형

- POI 주변 VWorld Polygon이 있으면 건물형으로 보고 외벽 3D 라벨을 만든다.
- Polygon이 없으면 비건물형으로 보고 TourAPI POI 좌표점 하나에 3D 구체를 띄운다.
- 비건물형이 화면 밖이면 edge marker로 방향을 안내하고, 필요하면 2D overlay로 이름/거리를 보조한다.
- 카테고리 하드코딩은 최소화한다.

## 3. 구현 체크리스트

### 3.1 완료

- [x] 대각선/모서리 외벽 후보 안정화
- [x] 거리별 라벨 높이 보정
- [x] 기본 3D 구체/라벨 크기 재조정
- [x] RealityKit Entity 직접 탭 hit-test 적용
- [x] 탭 시 3D 마커 확대와 최대 크기 제한
- [x] WGS84 중심 anchor 로그 정리
- [x] 근거리/중거리/원거리 UX 분기 적용
- [x] 3D 구체/라벨 이동 smoothing 적용
- [x] 3D 생성/삭제 거리 hysteresis 적용
- [x] WGS84 기준 anchor와 RealityKit child offset 이동 구조 적용
- [x] 거리 안의 여러 건물 WGS84 anchor 동시 유지
- [x] 5m 이내 근거리에서 구체가 외벽 앞쪽으로 과하게 돌출되지 않도록 표시 좌표를 POI 내부 방향으로 소폭 보정

### 3.2 다음 작업

- [ ] 여러 3D 라벨이 동시에 보일 때 겹침/우선순위 현장 검증
- [ ] 2D overlay와 3D 라벨 역할 정리
- [ ] TourAPI 재연결 후 실제 후보 검증
- [ ] 비건물형 POI의 좌표점 3D 표시 검증
- [ ] 장기 안정화 테스트 시나리오 수행

각 단계는 한 번에 모두 구현하지 않는다. 한 단계 구현 후 실기 테스트 결과를 확인하고, 기대와 다르면 다음 단계로 넘어가기 전에 수정한다.

`ARBusan_3D_LABEL_REFINEMENT_PLAN.md` 완료 후의 장기 안정화 테스트는 `ARBusan_3D_LABEL_STABILITY_TESTS.md`에서 관리한다.

## 4. 다음 테스트에서 볼 것

- 모서리에서 구체가 양쪽 벽 사이를 빠르게 왕복하지 않는가?
- 0~5m에서 라벨이 눈높이 근처에 보이는가?
- 5~30m에서 라벨이 1층 중앙~끝 지점에 자연스럽게 보이는가?
- 20~30m에서 구체와 텍스트가 너무 작지 않은가?
- WGS84 Anchor가 안정적으로 생성되는가?
- 한 화면 또는 같은 반경 안의 여러 건물에서 WGS84 Anchor가 여러 개 유지되는가?
- WGS84 후보 로그와 앵커 상태 로그의 활성 개수가 실제 표시되는 구체/라벨 개수와 맞는가?
- 비건물형 POI도 좌표점 기준 3D 구체로 표현 가능한가?
