# ARBusan AR 기술 로드맵

이 문서는 `../../ARBusan_PROJECT_STATUS.md`의 자식 문서다. 프로젝트 상태 파일에는 현재 상태를 짧게 두고, 여기에는 AR 인식/라벨 기술 판단과 다음 순서를 정리한다.

## 1. 목표 시나리오

사용자는 카메라로 부산 관광지/랜드마크를 본다.

- 가까운 건물형 관광지: 3D 마커로 위치감을 느끼고, 2D 카드로 이름/거리/방향을 읽는다.
- 먼 관광지: 약 1km 거리여도 edge marker와 2D 방향/거리 안내로 위치를 이해한다.
- 바다/공원/광장 같은 비건물형 대상은 억지로 근처 건물에 붙이지 않는다.
- 단순 heading 하나가 아니라 TourAPI POI, TMAP 보행자 경로, pose/heading, VPS 위치 정확도, WGS84/RealityKit Anchor를 조합한다.

## 2. 핵심 결론

```text
대상 데이터:
    TourAPI 또는 목업 POI

건물형 판단:
    MVP에서는 건물형/비건물형을 3D 높이 계산에 쓰지 않는다.
    VWorld Polygon은 필요 시 검증/보정용으로만 사용한다.

3D 표시:
    TMAP 보행자 경로의 마지막 도착 좌표
    WGS84 Anchor + RealityKit Entity

길찾기:
    현재 위치 -> 목적지까지 TMAP 보행자 경로
    경로 화살표로 정확한 진행 방향 안내

정보 표시:
    최종 방향은 3D 마커 hit/tap으로 관광지 정보 표시
    전환 전까지는 2D 정보 카드와 edge marker 유지
    화면 밖 대상은 edge marker
```

기존 외벽 부착형 3D 라벨과 VWorld 대표/정문 좌표 방식은 테스트 교훈만 남긴다. 앞으로 기본 3D 마커 좌표는 TMAP 보행자 길찾기의 마지막 도착 좌표다.

## 3. 완료된 주요 기반

- Swift 네이티브 ARKit/RealityKit 카메라 화면
- ARCore Geospatial 세션과 VPS/위치 정확도 표시
- CoreLocation 좌표와 ARCore Geospatial 좌표 분리
- heading, pitch/yaw/roll, AR camera pose 진단
- 현재 위치 + heading + POI 좌표 기반 카메라 방향 후보 계산
- 수동 VPS/Polygon 후보 선택 UI 제거
- VWorld `LT_C_SPBD` Polygon 자동 조회
- POI 포함 Polygon 우선 선택
- POI 미포함 시 외곽 최단 거리 fallback 또는 비건물형 처리
- VWorld 속성에서 건물명/높이/지상층수 파싱
- 높이 결정 정책: VWorld HEIGHT -> Streetscape 입력 -> 층수 추정 -> 기본값
- projection matrix 기반 2D 라벨/마커 검증
- 화면 안 후보 마커와 화면 밖 edge marker 검증
- WGS84 Anchor + RealityKit 구체/텍스트 표시 실험
- 여러 근처 POI의 WGS84 Anchor 동시 유지
- stable origin 기반 3D 위치 안정화
- Haeundae TourAPI 실내 디버그 구조

현재 제외한 것:

- OCR: 발열/효과 대비 문제로 메인 테스트 UI에서 제외
- Scene Semantics: 건물 보조 신호로 실험했지만 현재 메인 로직에서 제외
- Terrain Anchor: 김해 테스트에서 `errorUnsupportedLocation`이 반복되어 보류

## 4. VWorld Polygon 역할

VWorld는 “카메라가 본 건물을 자동 인식하는 AI”가 아니다. TMAP 도착점 기반으로 전환하면서 MVP 핵심에서는 빠지고, 필요할 때만 검증/보정용으로 사용한다.

```text
POI 좌표
-> 주변 BOX로 VWorld 건물 Polygon 조회
-> POI가 내부에 있는 Polygon 선택
-> 건물형 여부/공간 검증/디버그에 사용
```

중요 규칙:

- POI가 Polygon 안에 있으면 건물형으로 볼 수 있지만, 3D 마커 위치의 필수 조건은 아니다.
- 어떤 Polygon에도 포함되지 않으면 가까운 건물에 무조건 붙이지 않는다.
- 기존 외벽 ray/nearest facade/대표점 계산은 fallback 또는 디버그로만 둔다.
- TMAP 도착점이 이상하거나 API 사용이 불가능한 경우에만 VWorld/POI fallback을 검토한다.

## 5. 2D/3D 표시 역할

```text
3D 마커:
    대상 위치감을 주는 공간 기준점

2D 정보 카드:
    이름, 거리, 방향, 상태를 읽기 쉽게 표시

edge marker:
    화면 밖 대상 방향 안내

디버그 마커:
    matrix, 핑크/주황 후보, Polygon 로그 검증용
```

거리 기준:

```text
0~120m:
    3D 마커 + 2D 카드

120m~1km:
    3D 숨김
    2D 방향/거리 + edge marker

1km 이상:
    기본 후보에서 제외하거나 제한적 안내
```

## 6. 3D 마커 전략

기본 POI:

```text
TourAPI/목업 POI
-> 현재 위치에서 TMAP 보행자 길찾기 요청
-> 응답 경로의 마지막 도착 좌표 추출
-> WGS84 Anchor 생성
-> RealityKit 3D 마커 표시
-> 3D 마커 hit/tap 시 관광지 정보 표시
-> 경로 화살표로 정확한 방향 안내
```

좌표 우선순위:

1. TMAP 보행자 경로 마지막 도착 좌표
2. 캐시된 TMAP 도착 좌표
3. 수동 `preferredMarkerCoordinate`/`entranceCoordinate`
4. TourAPI/목업 POI 좌표 fallback

비건물형 POI도 같은 흐름을 사용한다.

```text
TourAPI POI
-> TMAP 마지막 도착 좌표
-> 3D 마커 또는 원거리 2D/edge 표시
```

## 7. 하위 문서 연결

- `../ar-label/EDGE_MARKER_RULES.md`
  - 2D 정보 카드, 화면 안 후보, 화면 밖 edge marker 규칙
- `../ar-label/3D_LABEL_REFINEMENT_PLAN.md`
  - 새 3D 마커 배치 전략
- `../ar-label/3D_LABEL_OPTIMIZATION_PLAN.md`
  - 3D 마커 흔들림/재생성/좌표 안정화 계획
- `../testing/HAEUNDAE_TOURAPI_INDOOR_DEBUG_PLAN.md`
  - 해운대 TourAPI 실내 디버그 테스트 구조
- `../testing/3D_LABEL_STABILITY_TESTS.md`
  - 장기 안정화 테스트 시나리오

## 8. 다음 진행 순서

1. TMAP 도착 좌표 방식으로 3D 좌표 교체
   - 방향 변경: 대표/정문 자동 계산이 아니라 TMAP 보행자 마지막 도착 좌표를 기본으로 한다.
   - 기존 외벽 후보점/Polygon 대표점은 fallback/디버그로 낮춘다.
   - TMAP 키 로딩, 클라이언트, 경로 마지막 좌표 파싱, 캐시를 추가한다.

2. 3D 마커와 2D 정보 카드 역할 분리
   - 3D 구체/마커는 공간 위치감만 제공한다.
   - 이름/거리/방향은 2D 카드로 표시한다.

3. 방향 문구와 edge marker 안정화
   - `정면`, `왼쪽 앞`, `오른쪽`, `뒤쪽` 같은 방향 문구를 만든다.
   - heading이 흔들릴 때 문구가 깜빡이지 않도록 smoothing을 적용한다.

4. TourAPI 재연결
   - 목업에서 검증한 `POI -> TMAP 도착점 -> 3D 마커/경로 화살표` 흐름을 TourAPI 후보에 적용한다.
   - 김해/부산/해운대 테스트 전환을 유지한다.

5. 건물형/비건물형 분기 검증
   - MVP에서는 둘 다 TMAP 도착점 기반으로 통일한다.
   - VWorld는 이상 케이스 검증/보정에만 사용한다.

6. AR 라벨 UX 개선
   - 탭 상세
   - 다중 후보 우선순위
   - 디버그 UI 축소
   - 발열/배터리 최적화

## 9. 보류 항목

- Terrain Anchor: 부산 현장 VPS/terrain 지원 여부를 다시 확인한 뒤 재검토
- Streetscape Geometry: VPS 지원 지역에서 mesh/높이 보정 후보로 검토
- Rooftop Anchor: 옥상/상단 라벨이 필요할 때 검토
- Scene Semantics: 현재 제외. 나중에 화면 영역 보조가 다시 필요할 때만 재검토
- OCR: 현재 제외. 간판 기반 보조가 다시 필요할 때만 재검토
