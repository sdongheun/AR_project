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
TourAPI/목업 POI + 브이월드 Polygon + camera pose/heading + OCR

화면 라벨 위치:
Polygon/POI 화면 투영 좌표를 기본으로 사용하고, Scene Semantics building 영역은 보조 보정으로만 사용

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
- ARCore Scene Semantics 활성화
- Scene Semantics 디버그 overlay
  - `building`: 파란색
  - `sky`: 빨간색
  - `tree`: 노란색
  - `road`: 회색
  - `water`: 하늘색
  - 그 외: 투명
- Scene Semantics label 데이터를 보존하고 building/sky/tree/road/water 비율 계산
- 투영된 Polygon 주변 semantic label 샘플링
- Scene Semantics는 인식 점수에 반영하지 않고 라벨 위치 보정/디버그에만 사용
  - building 영역이 있으면 라벨 위치를 그쪽으로 보정
  - building 영역이 없어도 인식 점수를 낮추거나 라벨을 강제로 숨기지 않음

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
7. 투영된 대상 영역 주변의 building 픽셀을 라벨 위치 보정에만 사용
8. 라벨은 Polygon/POI 투영 좌표를 기본으로 하고, 가능하면 Scene Semantics building 영역 중심 근처로 보정
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
| Scene Semantics | 화면에서 building 영역 찾기, 라벨 위치 보정, 디버그 overlay | 보조 기능으로 유지 |
| Streetscape Geometry | 지원 지역에서 3D 건물 mesh와 높이 보정 | Scene Semantics 이후 |
| Depth/Geospatial Depth | 표면 거리, occlusion, hit-test 보정 | 근거리 자연스러움 개선 |
| Terrain/WGS84/Rooftop Anchor | 실제 공간에 라벨 고정 | 라벨 후보 위치 계산 후 |

## 6. 다음 작업 순서

### 6.1 Scene Semantics building 영역 검증 - 1차 완료

목표:

- 화면에서 실제 건물 영역이 어디인지 찾는다.
- 사용자가 하늘/도로/나무를 보고 있을 때 건물 인식을 확정하지 않는다.
- 높이값이 없어도 화면상 건물 영역에 정보 라벨을 붙일 수 있게 한다.

반영된 내용:

```text
ARCore Scene Semantics 활성화
-> semantic image/confidence 수신
-> building 픽셀 비율 계산
-> 선택 Polygon 투영 영역 주변의 building 영역 확인
-> building 영역이 있으면 라벨 위치 보정
```

현재 UI 로그:

- Scene Semantics 지원 여부
- building 픽셀 비율
- sky/tree/road 비율
- 투영된 Polygon 주변 semantic 샘플링 결과
- Scene Semantics 라벨 보정 참고값

아직 남은 부분:

- 라벨 후보 화면 좌표 산출
- building 영역 중심 또는 상단 1/3 지점을 실제 overlay 라벨 위치로 사용

### 6.2 Polygon 투영 결과와 Scene Semantics 관계 정리 - 완료

Scene Semantics를 인식 점수에 직접 반영하는 방식은 제거했다. 이유는 사용자와 건물 사이에 나무/차량/사람/간판 등이 있으면 실제로는 건물을 보고 있어도 화면 semantic은 `tree`, `road`, 기타 객체로 잡힐 수 있기 때문이다.

```text
인식 판단:
    OCR + POI/Polygon + 위치 + heading/pose

Scene Semantics:
    점수 가점/감점 없음
    building 영역이 있으면 라벨 위치 보정
    없으면 Polygon/POI 투영 좌표 fallback
```

주의:

- Scene Semantics는 “이 건물이 맞다/아니다”를 결정하지 않는다.
- Scene Semantics는 라벨이 더 자연스럽게 building 영역 근처에 뜨도록 돕는 보조 신호다.
- 정확도 핵심은 Polygon/POI 투영과 projection matrix 개선에 둔다.

### 6.3 화면 overlay 라벨 MVP - 1차 완료

처음부터 3D Anchor에 고정하지 않는다. 먼저 화면 overlay로 사용자가 이해 가능한 라벨을 띄운다.

```text
근거리/중거리 건물:
    Scene Semantics building 영역 중심 또는 상단 근처에 라벨

원거리 관광지:
    POI/Polygon 투영 좌표 기반 라벨
    거리, 방향, 신뢰도 표시
```

구현 우선순위:

```text
완료:
1. 현재 선택/인식 후보의 화면 좌표 계산
2. Scene Semantics building 영역 안쪽으로 라벨 좌표 보정
3. 라벨 위치 smoothing 1차 적용
4. Scene Semantics가 없거나 building 영역이 약하면 Polygon/POI 투영 좌표 fallback

남음:
1. 근거리/중거리/원거리 라벨 스타일 분리
2. 라벨 겹침 회피
3. projection matrix 기반 좌표로 교체
4. 라벨 위치 품질 현장 튜닝
```

### 6.4 Projection Matrix 기반 화면 투영 개선

현재 `heading + pitch + FOV` 방식은 빠른 검증용이다. 정확도를 높이려면 ARKit 카메라의 view/projection matrix를 사용해 현실 3D 좌표를 실제 화면 2D 좌표로 변환해야 한다.

목표:

- VWorld Polygon의 위도/경도를 AR world 좌표로 변환한다.
- 높이가 있으면 외벽 상단/하단 3D 점을 만든다.
- ARKit camera pose와 projection matrix로 화면 좌표를 얻는다.
- Scene Semantics building 영역과 더 정확하게 overlap을 계산한다.
- 이후 overlay 라벨과 anchor 위치 계산의 공통 기반으로 사용한다.

예상 효과:

- heading 흔들림만으로 좌우 위치가 크게 튀는 문제 감소
- 화면 비율/렌즈/FOV를 더 정확히 반영
- 건물 외벽 라벨 위치가 더 자연스러워짐

진행 원칙:

- 아래 체크리스트는 한 번에 모두 진행하지 않는다.
- 각 단계 구현 후 사용자가 실기 테스트 결과를 알려준다.
- 테스트 결과가 기대와 다르면 다음 단계로 넘어가지 않고 해당 단계의 가정부터 수정한다.
- 기존 `heading + pitch + FOV` 방식은 바로 제거하지 않고, projection matrix 방식과 병렬 로그로 비교한다.

체크리스트:

```text
[x] 6.4.1 ARFrame camera matrix 디버그 로그 추가
    목적:
        ARFrame에서 view/projection matrix, camera transform, viewport size, orientation을 안정적으로 읽는지 확인한다.
    구현:
        - ARSessionViewController에서 ARFrame.camera projection/view/transform 값 수집
        - UI 로그에 matrix 수신 여부, 화면 크기, orientation, tracking 상태 표시
        - 구현 완료. 실기 테스트 결과 확인 전까지 다음 단계로 넘어가지 않는다.
    사용자 테스트 확인:
        - 기기 실행 시 matrix 로그가 실시간으로 갱신되는가?
        - 세로 화면에서 orientation/viewport 값이 예상대로 나오는가?
        - 카메라를 움직일 때 transform 값이 변하는가?

[x] 6.4.2 좌표계 기준점 설정 및 local ENU 변환 로그
    목적:
        TourAPI/목업/VWorld 위도경도를 AR world에 넣기 전, 현재 위치 기준 동/북/상대좌표로 안정적으로 바꾸는지 확인한다.
    구현:
        - 현재 위치를 origin으로 설정
        - POI/Polygon 좌표를 east/north/up 로 변환
        - 기존 bearing/distance 값과 ENU 거리/방향이 비슷한지 로그 비교
        - 구현 완료. 실기 테스트 결과 확인 전까지 다음 단계로 넘어가지 않는다.
    사용자 테스트 확인:
        - 내가 바라보는 목업 건물의 east/north 방향이 상식적으로 맞는가?
        - 거리값이 기존 거리 로그와 크게 다르지 않은가?

[x] 6.4.3 기존 FOV 투영과 projection matrix 투영 병렬 비교
    목적:
        새 projection 좌표가 실제 화면에서 기존 방식보다 나은지 비교한다.
    구현:
        - 기존 heading/FOV 라벨 좌표 유지
        - projection matrix 기반 후보 좌표를 별도 로그로 출력
        - UI에 두 좌표의 x/y 차이 표시
        - 구현 완료. 실기 테스트 결과 확인 전까지 다음 단계로 넘어가지 않는다.
    사용자 테스트 확인:
        - 실제 건물을 볼 때 projection 좌표가 라벨 위치에 더 가까운가?
        - 좌우/상하 중 어느 축이 더 틀어지는가?
        - 실내/실외에서 차이가 커지는가?

[x] 6.4.4 projection matrix 좌표를 임시 라벨로 표시
    목적:
        로그만으로 판단하기 어려운 좌표 차이를 화면에서 직접 비교한다.
    구현:
        - 기존 라벨은 유지
        - projection matrix 좌표에는 작은 디버그 마커 또는 보조 라벨 표시
        - 두 좌표가 겹치면 하나로 보이도록 단순 처리
        - 구현 완료. 실기 테스트 결과 확인 전까지 다음 단계로 넘어가지 않는다.
    사용자 테스트 확인:
        - 디버그 마커가 실제 건물 위치에 더 자연스럽게 붙는가?
        - 기기 회전/움직임에서 마커가 과하게 튀지 않는가?

[x] 6.4.5 라벨 좌표 계산을 projection matrix 방식으로 전환
    목적:
        6.4.3~6.4.4에서 projection 방식이 더 낫다는 테스트 결과가 확인된 뒤 실제 라벨 기준을 교체한다.
    구현:
        - 기본 라벨 좌표를 projection matrix 방식으로 변경
        - 기존 heading/FOV 방식은 fallback으로 유지
        - Scene Semantics는 계속 라벨 위치 보정용으로만 사용
        - 구현 완료. 실기 테스트 결과 확인 전까지 다음 단계로 넘어가지 않는다.
    사용자 테스트 확인:
        - 기존보다 라벨이 건물 근처에 안정적으로 뜨는가?
        - Scene Semantics가 없어도 fallback 라벨이 표시되는가?

[ ] 6.4.6 projection 기반 라벨 안정화
    목적:
        실제 사용감을 위해 위치 흔들림과 표시 조건을 정리한다.
    구현:
        - 완료: matrix가 화면 밖일 때 FOV fallback은 대상 방향각 차이 75도 이내에서만 허용
        - 완료: 180도 반대 방향에서 FOV fallback + Scene Semantics로 라벨이 재생성되는 현상 방지
        - smoothing 계수 조정
        - 화면 밖/가장자리 처리: 세부 규칙은 `ARBusan_EDGE_MARKER_RULES.md`에 별도 정리
        - 근거리/중거리/원거리별 라벨 위치와 크기 조정
    사용자 테스트 확인:
        - 걷거나 손을 조금 흔들어도 라벨이 과하게 튀지 않는가?
        - 가까운 건물과 먼 관광지 모두 위치감이 자연스러운가?
```

### 6.4 후속 진행 순서

현재는 기능 완성을 우선한다. 카메라 상시 사용에 따른 발열/배터리 최적화는 추후 별도 단계에서 다룬다.

현재 판단:

- `6.4.6 projection 기반 라벨 안정화`는 2D overlay 기준 최소 동작까지 완료했다.
- 세부 smoothing, 최종 edge marker UX, 다중 후보 탭 승격은 3D 라벨 기준이 잡힌 뒤 다시 조정한다.
- 이유는 현재 라벨이 2D overlay라서, 3D anchor/외벽 라벨로 넘어가면 안정화 기준과 UX 규칙이 다시 바뀔 가능성이 높기 때문이다.
- `ARBusan_EDGE_MARKER_RULES.md`는 이 문서의 6.4.6 자식 문서로 유지하며, 현재 2D 표시 기준선과 3D 전환 전 임시 규칙을 기록한다.

최신 진행 순서:

```text
1. 3D 라벨 배치 MVP
   - 목업 POI + VWorld Polygon 기준으로 외벽 후보점을 계산
   - ARKit/ARCore 좌표계에 3D 라벨 후보 위치를 만든다
   - 2D overlay 라벨과 3D 라벨을 디버그 토글로 비교한다

2. 3D 라벨 기준 안정화
   - 3D 라벨이 실제 건물 근처에 고정되는지 확인
   - 근거리/중거리/원거리에서 라벨이 자연스러운지 확인
   - 2D overlay fallback과 edge marker 전환 조건을 다시 정리

3. TourAPI 다시 연결
   - 목업에서 검증한 POI -> VWorld Polygon -> projection 라벨 흐름을 TourAPI 후보에 적용
   - 김해/부산 후보 전환 가능하게 정리

4. 건물형/비건물형 분기
   - VWorld Polygon이 있으면 건물형
   - Polygon이 없으면 point/area 관광지로 처리
   - 바다/공원/광장 등 비건물형 관광지 대응

5. AR 라벨 UX 개선
   - 탭 상세
   - 거리/신뢰도/간단 설명 구성
   - 선택 상태와 다중 후보 표시 개선

6. 6.4.6 세부 안정화 재개
   - 3D 기준 smoothing 계수 확정
   - edge marker 최종 UI 조정
   - 화면 안 짧은 이름 마커 탭 승격
   - 120m 방향 후보 제한 재검토
```

### 6.5 Streetscape Geometry 높이/mesh 보정

VPS/Street View 지원 지역에서만 기대한다.

목표:

- ARCore Streetscape Geometry building mesh를 가져온다.
- mesh가 선택 브이월드 Polygon/POI와 매칭되는지 확인한다.
- 매칭되면 mesh vertex 높이 범위를 `ResolvedBuildingHeight`의 Streetscape 입력으로 넣는다.
- 가능하면 Streetscape geometry attached anchor 또는 Geospatial Depth hit-test를 검토한다.

주의:

- LOD1 mesh 높이는 부정확할 수 있다.
- mesh가 있다고 해서 자동으로 대상 건물이라고 보면 안 된다. POI/Polygon/화면 투영과 매칭해야 한다.

### 6.6 Anchor 기반 라벨 고정

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

3D 라벨 MVP 진행 순서:

```text
1. 외벽 후보점 계산
   - 선택 Polygon의 각 외곽 선분을 만든다.
   - 현재 사용자 위치와 가장 마주보는 선분을 우선 후보로 고른다.
   - 선분 중점 또는 POI에 가까운 외벽점을 라벨 기준점으로 둔다.

2. 높이 기준값 결정
   - 브이월드 HEIGHT가 있으면 사용한다.
   - 없으면 Streetscape Geometry 높이 입력을 받을 수 있는 구조를 둔다.
   - 없으면 층수 * 3.3m를 사용한다.
   - 그래도 없으면 기본 높이를 사용한다.

3. 3D 월드 좌표 생성
   - 외벽 기준점 위도/경도를 현재 origin 기준 ENU 좌표로 변환한다.
   - 라벨 높이는 건물 중간 높이 또는 사용자 눈높이보다 약간 위로 둔다.
   - 초기 MVP에서는 anchor 생성 전, AR world 좌표에 임시 3D 노드를 표시해 좌표가 맞는지 본다.

4. 2D overlay와 3D 후보 동시 표시
   - 기존 2D 라벨은 유지한다.
   - 3D 후보 라벨은 개발용 토글로 켜고 끈다.
   - 두 위치가 실제 건물 기준으로 얼마나 차이 나는지 현장 테스트한다.

5. Anchor 후보 적용
   - WGS84/Terrain/Rooftop/Streetscape attached anchor 중 현재 테스트 환경에서 가능한 방식을 붙인다.
   - VPS가 약한 지역에서는 CoreLocation 기반 fallback을 유지한다.

6. 3D 기준 UX 재정리
   - 3D 라벨이 안정되면 2D 라벨은 fallback 또는 원거리용으로 역할을 줄인다.
   - edge marker, smoothing, 다중 후보 탭 승격은 이 단계에서 다시 확정한다.
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
