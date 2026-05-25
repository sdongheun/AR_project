# ARBusan AR 기술 로드맵

이 문서는 `ARBusan_PROJECT_STATUS.md`의 자식 문서다. 상태 파일에는 현재 프로젝트 상태를 짧게 두고, 여기에는 AR 건물 인식과 라벨 표시를 완성하기 위한 기술 판단만 정리한다.

## 1. 목표 시나리오

사용자는 카메라로 부산 관광지/랜드마크를 본다.

- 가까운 건물형 관광지: 건물 외벽이나 입구 근처에 정보 라벨이 자연스럽게 뜬다.
- 먼 관광지: 약 1km 거리여도 화면 방향과 거리감으로 위치를 이해할 수 있다.
- 바다, 공원, 도로, 하늘처럼 비건물형 대상은 억지로 근처 건물에 붙이지 않는다.
- 단순 heading 하나가 아니라 POI, Polygon, pose, Scene Semantics, 필요 시 Streetscape/Anchor를 조합한다.

## 2. 핵심 결론

현재 방향은 아래처럼 정리한다.

```text
대상 판단:
TourAPI/목업 POI + 브이월드 Polygon + camera pose/heading

화면 라벨 위치:
Scene Semantics building 영역을 1순위로 사용

3D 높이/Anchor 보조:
브이월드 HEIGHT -> Streetscape Geometry mesh -> 층수 추정 -> 기본값
```

중요한 해석:

- Scene Semantics는 높이 미터값을 주지 않는다. 대신 화면에서 `building`, `sky`, `tree`, `road`, `vehicle` 같은 픽셀 영역을 알려준다.
- Scene Semantics는 VPS에 직접 의존하지 않는다. ARCore/Scene Semantics 지원 기기와 실외/세로 화면 조건의 영향을 더 크게 받는다.
- Streetscape Geometry는 화면 분류가 아니라 건물/지형 3D mesh다. 다만 Google Street View/VPS 지원 지역에서 기대해야 한다.
- 정확한 건물 높이는 브이월드와 건축물대장 모두 모든 건물에 보장되지 않는다. 높이는 필수 조건이 아니라 라벨/Anchor 보정값으로 둔다.

## 3. 현재 구현 요약

이미 구현된 기반:

- Swift 네이티브 ARKit 카메라 화면
- Vision OCR
- ARCore Geospatial 세션 생성 및 ARFrame 전달
- CoreLocation 좌표와 ARCore Geospatial/VPS 좌표 분리 표시
- camera heading, pitch/yaw/roll, AR camera pose 진단
- heading 변화량이 크면 공간 신뢰도 downgrade
- 현재 위치 + heading + POI 좌표 기반 카메라 방향 후보 자동 계산
- 수동 VPS/Polygon 후보 선택 UI 제거
- 브이월드 `LT_C_SPBD` Polygon 자동 조회
- POI가 포함된 Polygon 우선 선택
- POI 미포함 시 외곽 최단 거리 fallback
  - `0~3m`: 근접 오차로 선택 가능
  - `3~8m`: 후보 로그만 남기고 자동 선택 보류
  - `8m 초과`: 비건물형/point 관광지 처리
- 브이월드 properties 로그 및 `buld_nm`, `buld_nm_dc`, `gro_flo_co`, `HEIGHT` 계열 파싱
- 부산 TourAPI POI 1322개 대상 터미널 검증 스크립트
- `ResolvedBuildingHeight` 높이 결정 정책

현재 높이 결정 정책:

```text
if 브이월드 HEIGHT 있음:
    HEIGHT 사용
else if Streetscape Geometry mesh 높이 입력 있음:
    mesh 높이 사용
else if 브이월드 gro_flo_co 있음:
    gro_flo_co * 평균층고 3.3m
else:
    기본 높이 5m
```

부산/김해 샘플 검증 결과:

- 브이월드 `HEIGHT`는 거의 제공되지 않았다.
- 층수는 `gro_flo_co`로 제공되는 경우가 있었다.
- 따라서 층수 추정은 fallback으로 유지하되, 화면 라벨 위치의 주 경로로 쓰면 안 된다.

## 4. 최종 처리 흐름

```text
1. TourAPI 또는 목업 POI 로드
2. POI 주변 브이월드 Polygon 조회
3. POI가 Polygon 내부에 있으면 대상 건물 Polygon 선택
4. 포함 Polygon이 없으면 외곽 최단 거리로 보수적 fallback
5. 현재 위치, camera pose, heading으로 대상 Polygon/POI를 화면에 투영
6. Scene Semantics로 화면의 building 영역을 찾음
7. 투영된 대상 영역과 building 픽셀 영역이 충분히 겹치면 인식 신뢰도 상승
8. 라벨은 Scene Semantics building 영역 중심/상단 근처에 우선 표시
9. 3D Anchor가 필요하면 높이 결정 정책과 Terrain/WGS84/Rooftop/Streetscape Anchor를 사용
10. 가까운 대상은 외벽/입구 근처 라벨, 먼 대상은 방향/거리 중심 overlay 라벨로 표현
```

## 5. 기술별 역할

| 기술 | 역할 | 현재 판단 |
| --- | --- | --- |
| TourAPI | 관광지/랜드마크 POI 좌표와 이름 제공 | 최종 데이터 원천 |
| 브이월드 Polygon | POI가 어떤 건물/공간에 속하는지 판단 | 건물형 대상 선택의 핵심 |
| CoreLocation | 기본 현재 위치 | VPS 미지원 지역 fallback |
| ARCore Geospatial/VPS | 현재 위치/방향 보정 | 지원 지역에서 신뢰도 향상 |
| ARKit camera pose | 카메라 자세, pitch/yaw/roll, 투영 계산 | 필수 |
| Scene Semantics | 화면에서 building 영역 찾기 | 다음 핵심 작업 |
| Streetscape Geometry | 지원 지역에서 3D 건물 mesh와 높이 보정 | Scene Semantics 이후 |
| Depth/Geospatial Depth | 표면 거리, occlusion, hit-test 보정 | 근거리 자연스러움 개선 |
| Terrain/WGS84/Rooftop Anchor | 실제 공간에 라벨 고정 | 라벨 후보 위치 계산 후 |

## 6. 다음 작업 순서

### 6.1 Scene Semantics building 영역 검증

목표:

- 화면에서 실제 건물 영역이 어디인지 찾는다.
- 사용자가 하늘/도로/나무를 보고 있을 때 건물 인식을 확정하지 않는다.
- 높이값이 없어도 화면상 건물 영역에 정보 라벨을 붙일 수 있게 한다.

구현 방향:

```text
ARCore Scene Semantics 활성화
-> semantic image/confidence 수신
-> building 픽셀 비율 계산
-> 선택 Polygon 투영 영역과 building 영역의 겹침 계산
-> building 비율/겹침이 낮으면 확정 방지
-> building 영역 중심 또는 상단 1/3 지점을 라벨 후보 화면 좌표로 사용
```

우선 UI 로그:

- Scene Semantics 지원 여부
- building 픽셀 비율
- sky/tree/road 비율
- 선택 Polygon 투영 영역과 building 영역 겹침 여부
- 라벨 후보 화면 좌표

### 6.2 Polygon 투영 결과를 점수에 반영

현재는 Polygon 외곽점 화면 투영이 진단 로그 중심이다. 다음에는 실제 점수에 반영한다.

```text
선택 Polygon이 화면 안에 있음 + building semantic 겹침 높음:
    공간 점수 상승
선택 Polygon이 화면 밖이거나 building 비율 낮음:
    인식 확정 방지
```

### 6.3 화면 overlay 라벨 MVP

처음부터 3D Anchor에 고정하지 않는다. 먼저 화면 overlay로 사용자가 이해 가능한 라벨을 띄운다.

```text
근거리/중거리 건물:
    Scene Semantics building 영역 중심 또는 상단 근처에 라벨

원거리 관광지:
    POI/Polygon 투영 좌표 기반 라벨
    거리, 방향, 신뢰도 표시
```

### 6.4 Streetscape Geometry 높이/mesh 보정

VPS/Street View 지원 지역에서만 기대한다.

목표:

- ARCore Streetscape Geometry building mesh를 가져온다.
- mesh가 선택 브이월드 Polygon/POI와 매칭되는지 확인한다.
- 매칭되면 mesh vertex 높이 범위를 `ResolvedBuildingHeight`의 Streetscape 입력으로 넣는다.
- 가능하면 Streetscape geometry attached anchor 또는 Geospatial Depth hit-test를 검토한다.

주의:

- LOD1 mesh 높이는 부정확할 수 있다.
- mesh가 있다고 해서 자동으로 대상 건물이라고 보면 안 된다. POI/Polygon/화면 투영과 매칭해야 한다.

### 6.5 Anchor 기반 라벨 고정

overlay가 충분히 동작한 뒤 진행한다.

후보:

- WGS84 Anchor: 위도/경도/절대고도 필요
- Terrain Anchor: 지면 기준 상대 높이에 유리
- Rooftop Anchor: 옥상/상단 라벨에 유리
- Streetscape Geometry attached anchor: 지원 지역에서 건물 표면 부착에 유리

건물 외벽 라벨 후보 위치:

```text
1. 선택 Polygon에서 카메라와 마주보는 외벽 선분 선택
2. 선분 중점의 위도/경도 계산
3. Scene Semantics building 영역으로 화면상 위치 보정
4. 높이 결정 정책으로 대략 높이 선택
5. Anchor 또는 overlay 라벨 생성
```

## 7. 거리별 UX 원칙

```text
근거리 건물형:
    Scene Semantics building 영역 + Polygon 투영 + Depth/Anchor 중심

중거리:
    Polygon/POI 화면 투영 + building semantic 검증

원거리:
    POI 좌표 + pose/heading 기반 방향/거리 라벨
    Polygon/Depth 의존도 낮춤

비건물형 관광지:
    Polygon 필수 매칭을 요구하지 않음
    area/point 관광지로 처리
```

라벨 안정화는 별도 단계로 둔다.

- 화면 좌표 smoothing
- 신뢰도 threshold
- 거리 기반 크기/투명도
- Depth occlusion
- 후보 선택 UI 유지

## 8. 보류 또는 장기 후보

- 건축물대장 표제부 API: 정확 높이 원천 후보지만 모든 건물 보장 없음. TourAPI/브이월드와 매칭 난도가 있어 후순위.
- Google Photorealistic 3D Tiles: 높이/mesh 후보지만 모바일 MVP에는 비용과 처리 부담이 큼.
- 이미지/랜드마크 인식: 특정 관광지 외형 인식 가능성이 있지만 학습/레퍼런스 데이터가 필요해 MVP 이후.
- Apple ARGeoAnchor/LiDAR: iOS 네이티브 장점은 있으나 지역/기기 의존성 검토 후 적용.
