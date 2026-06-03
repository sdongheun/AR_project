# ARBusan 3D Label Optimization Plan

이 문서는 3D 구체/라벨이 흔들리거나 건물 밖으로 벗어나는 문제를 줄이기 위한 구조 개선 계획이다. `ARBusan_3D_LABEL_REFINEMENT_PLAN.md`의 후속 최적화 문서로 사용한다.

## 1. 현재 문제

- 근처에 여러 건물이 있어도 앱 시작 직후 모든 3D anchor가 바로 생성되지 않을 수 있다.
- 현재 카메라 heading 기반 외벽 후보 계산에 anchor 생성이 묶여 있어, 특정 방향을 봐야 anchor가 하나씩 늘어나는 것처럼 보일 수 있다.
- 사용자가 걷거나 앱을 다시 켰을 때 위치/VPS/heading이 불안정하면 구체와 텍스트가 이리저리 움직인다.
- 3D 구체/라벨은 건물 Polygon 외곽 또는 내부 기준을 벗어나면 안 되지만, 현재는 heading 후보가 흔들릴 때 시각적으로 불안정해질 수 있다.

## 2. 최종 원칙

- `내 위치 기준 120m 이내 + VWorld Polygon 있음`은 주변 모든 건물을 수집한다는 뜻이 아니다.
- 대상은 앱이 이미 알고 있는 POI 후보 목록이다. 현재는 목업 건물, 추후에는 TourAPI POI가 기준이다.
- 각 POI에 대해 VWorld에서 해당 POI 좌표를 감싸는 Polygon을 찾고, Polygon이 확보된 POI만 3D anchor 후보가 된다.
- anchor 생성은 카메라 방향과 분리한다.
- 3D 구체/라벨 위치는 항상 해당 건물 Polygon 기준 안에서만 결정한다.
- heading은 "어느 외벽을 보여줄지"를 보정하는 용도이며, 마커를 건물 밖으로 이동시키는 권한을 갖지 않는다.
- 위치/VPS/heading/AR tracking 품질이 나쁠 때는 마지막 안정 위치를 유지한다.
- 2D edge marker는 3D anchor와 별개로 방향 안내를 계속 제공한다.

## 3. 위치/방향 안정화 개념

### 3.1 POI 후보와 Polygon 범위

```text
앱 후보 POI 목록
→ 각 POI의 VWorld Polygon 조회
→ 내 위치 기준 120m 이내 POI 필터
→ Polygon이 확보된 POI
→ 3D anchor 선생성 대상
```

- VWorld에서 주변 모든 건물 Polygon을 무차별로 가져오는 구조가 아니다.
- 최종 서비스에서는 TourAPI에서 받은 관광지/POI 목록이 후보 목록이 된다.
- POI에 Polygon이 없으면 건물형 3D 외벽 라벨이 아니라 비건물형 POI 처리로 넘긴다.

### 3.2 raw location과 stable origin 분리

- `raw location`: CoreLocation/ARCore에서 매 순간 들어오는 위치값이다.
- `stable origin`: 3D 계산에 실제 사용하는 안정화된 기준 위치다.
- 3D anchor 생성, 외벽점 계산, POI bearing 계산은 raw location이 아니라 stable origin을 기준으로 해야 한다.
- 앱 시작 직후 또는 실내에서 밖으로 나가는 상황처럼 위치가 불안정하면 3D 위치를 바로 확정하지 않는다.

처리 방향:

```text
초기 상태:
    위치/VPS/heading 안정 대기
    2D edge marker는 표시 가능
    3D anchor는 생성 준비 또는 낮은 신뢰도 상태

위치가 안정됨:
    stable origin 확정
    근처 POI anchor 선생성
    기본 외벽점 계산

이후 위치가 튐:
    기존 구체/라벨은 마지막 안정 위치 유지
    새 위치로 바로 이동하지 않음
    일정 시간 비슷한 값이 반복될 때만 갱신
```

### 3.3 위치 튐과 heading/bearing 관계

- 위치가 튄다고 휴대폰 heading 값 자체가 반드시 같이 튀는 것은 아니다.
- 다만 `내 위치에서 POI를 향한 bearing`은 위치 기준점이 바뀌면 크게 흔들릴 수 있다.
- 따라서 사용자가 건물을 정면으로 보고 있어도 위치가 오른쪽/왼쪽으로 튀면 `heading - bearing` 차이가 갑자기 커질 수 있다.

예시:

```text
실제 위치:
    건물 bearing = 0도
    카메라 heading = 0도
    정면 일치

위치가 오른쪽으로 튐:
    건물 bearing = 340도 또는 20도 등으로 변경 가능
    카메라 heading = 0도 유지
    앱은 정면이 아니라고 오판 가능
```

결론:

- heading smoothing만으로는 부족하다.
- 위치 stable origin, heading smoothing, stable origin 기준 bearing 계산을 함께 적용해야 한다.
- raw 위치가 튀는 동안에는 heading/bearing 기반 외벽 갱신을 중단하고 마지막 안정 위치를 유지한다.

## 4. 구현 순서

### 4.1 [x] 근처 건물 anchor 선생성

- 기준: `내 위치 기준 120m 이내 + VWorld Polygon 있음`
- 카메라가 해당 건물을 바라보는지는 생성 조건에서 제외한다.
- 앱 시작 후 투썸/올리브영/후참잘이 모두 범위 안이면 활성 지리 anchor가 3개가 되는 것이 목표다.
- 생성은 최대 5개까지 유지한다.
- 구현: 3D anchor 준비용 Polygon prefetch를 추가해, 카메라 방향 후보와 무관하게 근처 POI의 Polygon을 미리 확보한다.
- 구현: WGS84 anchor 생성 후보는 heading 기반 외벽점이 아니라 `내 위치 기준 가장 가까운 외벽점`을 기본으로 사용한다.

테스트:
- 앱 시작 직후 WGS84 후보 로그에 근처 건물 수가 표시되는가?
- `활성 지리 앵커 N개`가 실제 근처 건물 수와 맞는가?
- 카메라를 특정 방향으로 돌리지 않아도 anchor가 먼저 생성되는가?

### 4.2 [x] 기본 위치를 가장 가까운 외벽점으로 고정

- heading이 없어도 계산 가능한 기본 위치를 둔다.
- 건물형 POI는 `내 위치에서 가장 가까운 Polygon 외벽점`을 기본 3D 위치로 사용한다.
- 비건물형 POI는 추후 `TourAPI POI 좌표점`을 기본 위치로 사용한다.
- 기본 위치는 Polygon 외곽선 위 또는 Polygon 내부로 clamp된 좌표만 허용한다.
- 구현: WGS84 후보 좌표와 라벨 높이/거리 기준을 모두 `nearestFacadeCandidate` 기준으로 맞췄다.
- 구현: WGS84 후보 로그에 `기본 위치는 각 건물의 가장 가까운 외벽점으로 고정`과 `내 위치 기준 가장 가까운 외벽점`이 표시되게 했다.

테스트:
- 앱 시작 직후 구체가 건물 좌표 밖으로 나가지 않는가?
- 카메라를 돌리지 않아도 건물 근처의 합리적인 위치에 구체가 생기는가?
- WGS84 후보 로그에 `내 위치 기준 가장 가까운 외벽점`이 표시되는가?

### 4.3 [x] stable origin 기반 위치 안정화

- raw location을 바로 3D 계산에 사용하지 않는다.
- 위치 샘플이 일정 시간 안정될 때 stable origin을 갱신한다.
- 갑자기 튄 위치는 후보로만 저장하고 즉시 반영하지 않는다.
- stable origin이 없거나 낮은 신뢰도이면 3D 위치 갱신을 보류하고 2D edge marker 중심으로 안내한다.
- 구현: 3D anchor 기준 위치는 CoreLocation이 아니라 ARCore Geospatial 샘플만 사용한다.
- 구현: ARCore Geospatial 정확도 10m 이내 위치 샘플이 1.2초 이상 유지될 때 `3D stable origin`을 확정한다.
- 구현: heading/AR camera tracking은 stable origin 확정 조건에서 제외하고, 외벽점 이동/화면 표시 안정화 단계에서만 사용한다.
- 구현: 기존 stable origin에서 12m 이상 튄 위치는 바로 반영하지 않고 후보 상태로 대기한다.
- 구현: 3D Polygon prefetch, 라벨 높이 계산, WGS84 anchor 요청은 현재 사용 가능한 stable origin 기준으로만 실행한다.
- 구현: stable origin이 없거나 3초 이상 안정 샘플을 받지 못하면 새 WGS84 anchor 후보 생성을 보류하고 기존 anchor를 일시 제거한다.
- 구현: 로그의 `유지`는 방향까지 안정됐다는 뜻이 아니라 `위치 기준 stable origin 유지`라는 뜻으로 명시한다.

테스트:
- 앱 시작 직후 위치가 잡히는 동안 구체가 여기저기 튀지 않는가?
- 실내에서 켜고 밖으로 나갔을 때 위치가 안정된 뒤 3D anchor가 자연스럽게 갱신되는가?
- 위치/VPS 상태 로그에 `3D stable origin 후보 시작`, `후보 확인 중`, `확정(위치 기준)`, `유지(위치 기준)`, `3D anchor 갱신 일시정지` 중 하나가 표시되는가?

### 4.4 [] heading 기반 외벽 보정 조건 추가

- 카메라 heading 기반 위치 이동은 안정 조건을 통과할 때만 적용한다.
- 예시 안정 조건:
  - AR camera tracking이 `normal`
  - 위치 정확도가 임계값 이내
  - heading 변화량이 짧은 시간에 과도하지 않음
  - stable origin 기준 bearing이 급격히 튀지 않음
  - 새 후보점이 Polygon boundary 위에 있음
- 조건을 통과하지 못하면 마지막 안정 위치를 유지한다.

테스트:
- 실내에서 켜고 밖으로 나가도 구체가 과하게 튀지 않는가?
- 걸어 다닐 때 위치가 불안정하면 새 위치로 점프하지 않고 유지되는가?

### 4.5 [] Polygon boundary 제한

- 최종 3D 표시 좌표는 항상 Polygon 기준으로 검증한다.
- ray 교차점이 있으면 외곽선 위 교차점을 사용한다.
- 교차점이 없으면 ray에 가장 가까운 외벽점 또는 내 위치에서 가장 가까운 외벽점을 사용한다.
- 계산 결과가 Polygon과 무관한 지점이면 폐기하고 마지막 안정 위치를 유지한다.

테스트:
- 건물 정면, 측면, 모서리에서 구체가 건물 외곽을 벗어나지 않는가?
- heading이 틀어져도 구체가 도로/다른 건물 쪽으로 밀려나지 않는가?

### 4.6 [] 외벽 전환 hysteresis

- 같은 건물에서 한 외벽에서 다른 외벽으로 바로 전환하지 않는다.
- 새 외벽 후보가 일정 시간 유지되거나, 기존 후보보다 명확히 좋은 경우에만 전환한다.
- 모서리 근처에서는 마지막 안정 외벽을 우선 유지한다.

테스트:
- 건물 모서리를 살짝 흔들며 바라볼 때 구체가 양쪽 변 사이를 빠르게 왕복하지 않는가?
- 사용자가 건물을 따라 이동할 때 외벽 전환이 순간이동처럼 느껴지지 않는가?

### 4.7 [] 이동 smoothing과 최대 이동 속도 제한

- child content offset 이동에 smoothing을 유지한다.
- 한 프레임 또는 짧은 시간에 이동할 수 있는 최대 거리를 제한한다.
- 갑작스러운 큰 이동은 위치/heading 오류로 보고 바로 반영하지 않는다.

테스트:
- 후참잘에서 투썸/올리브영을 훑을 때 구체가 툭툭 끊기지 않고 따라가는가?
- 앱을 나갔다 들어오거나 걷는 중에도 구체가 깜빡이거나 순간이동하지 않는가?

## 5. 우선순위

1. 4.1 근처 건물 anchor 선생성
2. 4.2 기본 위치를 가장 가까운 외벽점으로 고정
3. 4.3 stable origin 기반 위치 안정화
4. 4.4 heading 기반 외벽 보정 조건 추가
5. 4.5 Polygon boundary 제한
6. 4.6 외벽 전환 hysteresis
7. 4.7 이동 smoothing과 최대 이동 속도 제한

## 6. 완료 기준

- 앱 시작 직후 근처 Polygon 건물 anchor가 먼저 생성된다.
- 3D 구체/라벨은 건물 Polygon 기준 위치를 벗어나지 않는다.
- raw location이 튀어도 stable origin이 바로 흔들리지 않는다.
- heading 자체보다 `stable origin 기준 bearing`을 사용해 방향 판단이 안정된다.
- 위치/VPS/heading이 불안정할 때는 새 위치로 튀지 않고 마지막 안정 위치를 유지한다.
- 여러 건물이 한 화면 또는 가까운 반경 안에 있을 때 동시에 3D 표시가 유지된다.
- 사용자가 건물 앞에서 이동하거나 방향을 돌려도 구체/라벨 흐름이 자연스럽다.
