# 구현 지시서: VPS 위치 정교화와 카메라 기반 건물 인식

## 목적

프론트/테스트 구현 스레드에 전달할 작업 지시서다. 현재 구현 우선순위 1번인 "VPS로 내 위치를 정교화하고, 브이월드로 카메라가 바라보는 건물/관광지를 이해하는 기능"을 테스트 가능한 구조로 만든다.

## PM 스레드 제약

- 이 지시서는 PM 스레드에서 작성한다.
- 실제 코드 수정은 별도 구현 스레드에서 수행한다.
- 구현 스레드는 완료 후 변경 파일, 테스트 결과, 남은 실제 기기 검증 항목을 보고한다.

## 구현 목표

1. VPS 결과를 앱 내부 위치 모델로 정규화한다.
2. 사용자 위치, 카메라 방향, 브이월드 건물 polygon 후보를 이용해 사용자가 바라보는 건물을 선택한다.
3. 선택된 건물을 관광지 후보와 연결해 이름, 카테고리, 거리, 간단 정보를 표시할 수 있는 데이터 구조로 만든다.
4. 실제 기기 없이 검증 가능한 부분은 Jest 테스트와 fixture로 고정한다.

## 건물 인식 판정 규칙

### 1. 입력 계약

건물 선택 로직은 실제 카메라/외부 API에 직접 의존하지 않는 순수 함수로 만든다. 입력은 아래 네 종류로 제한한다.

- `userPose`: 정규화된 현재 위치. `latitude`, `longitude`, `altitude`, `horizontalAccuracyMeters`, `verticalAccuracyMeters`, `source`, `timestampMs`를 가진다.
- `cameraPose`: 카메라 방향. 우선 `headingDegrees`를 필수로 두고, 네이티브에서 제공 가능해지는 즉시 `pitchDegrees`, `orientationAccuracyDegrees`, `timestampMs`를 추가한다.
- `buildingCandidates`: 브이월드에서 가져온 주변 건물 후보. 각 후보는 `id`, `name`, `polygon`, `bbox`, `heightMeters`, `roadAddress`, `parcelCode`를 가진다.
- `recognitionOptions`: 시야각, 최대 거리, 정확도 임계값 같은 튜닝값. 테스트에서 고정값을 주입할 수 있어야 한다.

현재 iOS `VPSARView`는 RN 이벤트로 위경도/고도/정확도만 보내고 있으므로, 건물 인식 구현 전 네이티브 이벤트에 카메라 `headingDegrees` 또는 forward vector를 추가해야 한다.

### 2. 위치 정교화 및 선택 규칙 (Sensor Fusion & Smoothing)

단순히 오차 반경만으로 VPS와 GPS를 번갈아 쓰면 위치가 순간적으로 튀는(Jitter) 현상이 발생하여 건물 인식 정확도를 크게 떨어뜨립니다. 따라서 다음과 같은 정교화 기법을 도입하여 내 위치의 정확도를 극대화합니다.

- **VPS + AR 로컬 트래킹 결합 (Visual Odometry)**: VPS API 응답은 네트워크 지연으로 즉각적이지 않습니다. 마지막으로 성공한 고정밀 VPS 좌표를 '앵커(기준점)'로 삼고, 그 이후의 기기 이동량(ARKit/ARCore 센서 기반 상대 이동)을 더해 초당 60프레임 수준의 실시간 내 위치를 추정합니다.
- **아웃라이어 제거 및 위치 스무딩**: GPS나 VPS 값이 갑자기 수십 미터 튀는 경우, 기기의 이동 속도(보행자 기준)상 불가능한 거리라면 해당 데이터를 무시합니다. 또한 이전 위치와 현재 위치를 부드럽게 이어주는 스무딩(가중 평균 또는 보정 필터)을 적용합니다.
- **신뢰도 기반 가중 평균**: VPS가 `tracking_success`이고 오차가 적으면(예: `<= 8m`) VPS 비중을 극대화합니다. VPS 정확도가 떨어질 때는 GPS 좌표와 가중 평균을 내어 급격한 좌표 이동을 방지합니다.
- **Fallback 규칙**: 추적을 완전히 잃거나 위치 타임스탬프가 3초 이상 갱신되지 않으면 순수 GPS로 Fallback 처리하며 stale 상태로 간주합니다.
- **디버그 상태 세분화**: 최종 `userPose.source`는 `vps_fused`(VPS+AR결합), `vps_gps_blended`(가중평균), `gps_fallback` 등으로 세분화하여 테스트 시 명확히 추적합니다.

### 3. 후보 수집 규칙

- 사용자 위치 기준 반경 80m 안의 브이월드 건물 polygon을 후보로 가져온다.
- 초기 MVP의 최대 판정 거리는 100m로 제한한다. 100m 밖 후보는 AR 라벨 정확도가 떨어지므로 제외한다.
- 브이월드 호출은 위치가 30m 이상 이동했거나 마지막 조회 후 10초 이상 지났을 때만 다시 수행한다.
- 같은 `buildingManagementNumber`, `gisBuildingId`, `parcelCode`가 반복되면 하나로 병합한다.
- 건물명이 비어 있으면 도로명주소, 지번주소, `건물 정보 없음` 순서로 표시명을 만든다.

### 4. 기하 판정 규칙

건물 후보는 위경도를 사용자 위치 기준 동/북 미터 좌표계로 변환한 뒤 판정한다.

1. 카메라 `headingDegrees`에서 2D ray를 만든다.
2. 각 건물 polygon을 위치 정확도만큼 확장한 hit area로 본다. 확장값은 `clamp(horizontalAccuracyMeters + 2m, 5m, 15m)`이다.
3. 카메라 ray가 확장 polygon과 교차하면 `rayHit = true`로 둔다.
4. ray가 교차하지 않더라도 건물 중심점 방위각과 카메라 heading 차이가 시야각 안이면 보조 후보로 둔다.
5. 기본 수평 시야각은 45도이며, `abs(angleDelta) > 30도`인 후보는 hard reject한다.
6. pitch/고도 판정은 1차 MVP에서는 점수에 넣지 않는다. 고층 건물 라벨 높이는 별도 AR 앵커 배치 단계에서 처리한다.

중심점만으로 판정하지 않는다. 긴 건물, 사용자가 건물 모서리를 보는 상황, 가까운 건물의 중심점이 화면 밖에 있는 상황에서 오판이 생기기 때문이다.

### 5. 점수 규칙

필터를 통과한 후보는 낮은 점수가 더 좋은 방식으로 정렬한다.

```text
score =
  angleDeltaDegrees * 2.0
  + distanceMeters * 0.15
  + nearestRayDistanceMeters * 1.5
  + accuracyPenalty
  + metadataPenalty
  - rayHitBonus
```

- `angleDeltaDegrees`: 카메라 heading과 후보 기준점 방위각의 절대 차이.
- `distanceMeters`: 사용자 위치에서 polygon까지의 최단 거리. 중심점 거리보다 우선한다.
- `nearestRayDistanceMeters`: 카메라 ray와 polygon 사이의 최단 거리.
- `accuracyPenalty`: `horizontalAccuracyMeters > 8m`이면 `(accuracy - 8) * 1.5`.
- `metadataPenalty`: 건물명/주소가 모두 부실하면 `10`.
- `rayHitBonus`: ray가 polygon과 교차하면 `25`.

선택된 1등 후보와 2등 후보의 점수 차이가 8점 미만이면 `ambiguous`로 반환한다. 이때 UI는 단정 라벨 대신 후보 목록 또는 "주변 건물 확인 중" 상태를 보여준다.

### 6. 반환 규칙

`buildingRecognition.selectLookedAtBuilding()`은 아래 중 하나를 반환한다.

- `recognized`: 신뢰 가능한 단일 건물. `building`, `score`, `distanceMeters`, `angleDeltaDegrees`, `confidence`, `debug`를 포함한다.
- `ambiguous`: 후보가 2개 이상 비슷함. 상위 후보 3개와 점수 근거를 포함한다.
- `none`: 시야각/거리/정확도 조건을 통과한 후보가 없음. 실패 사유를 포함한다.

`confidence`는 MVP에서 `high`, `medium`, `low` 3단계로만 둔다. `rayHit = true`, `angleDelta <= 12도`, `distance <= 50m`, 위치 정확도 `<= 8m`이면 `high`로 본다.

### 7. API/AR 연결 규칙

- VPS 이벤트를 받을 때마다 바로 브이월드를 호출하지 않는다. 위치 캐시 갱신 조건을 만족할 때만 후보를 갱신한다.
- 카메라 방향 업데이트는 로컬 후보 목록에 대해 초당 5회 이하로 판정한다.
- AR 라벨은 `recognized/high` 또는 `recognized/medium`에서만 고정 표시한다.
- `low`, `ambiguous`, `none`은 디버그 패널에는 표시하되, 사용자용 라벨은 깜빡이지 않도록 1초 이상 같은 결과가 유지될 때만 갱신한다.
- 선택 결과의 `debug`에는 사용한 위치 source, 정확도, 후보 수, 상위 후보 점수, reject 사유를 남긴다.

## 범위

포함:

- 위치 정규화 mapper
- 카메라 heading/ray 기반 건물 후보 선택 로직
- 건물 polygon 중심점, 거리, 방위각 계산
- 브이월드 fixture 기반 테스트
- 카메라 방향 fixture 기반 테스트

제외:

- 실제 VPS SDK 현장 성능 판단
- 실제 카메라 프레임 처리 정확도 판단
- 최종 UI 디자인
- AR 길안내 기능
- Supabase 미션 기능

## 권장 구현 단위

- `src/services/geoMath.ts`
  - 거리 계산
  - 방위각 계산
  - 각도 차이 계산

- `src/services/arSpatialMath.ts`
  - 위경도/고도에서 AR 상대 좌표 계산
  - 카메라 forward vector와 target vector 비교

- `src/services/buildingRecognition.ts`
  - 현재 위치, heading, 건물 후보 목록을 입력받아 바라보는 건물 선택
  - 기준: 시야각 안에 있고, 거리가 가장 가깝거나 방향 오차가 가장 작은 후보

- `__fixtures__/vworld/`
  - 부산 샘플 건물 polygon fixture

- `__tests__/`
  - `geoMath.test.ts`
  - `arSpatialMath.test.ts`
  - `buildingRecognition.test.ts`

## 테스트 시나리오

- 사용자가 건물 정면을 바라볼 때 해당 건물이 선택된다.
- 사용자가 30도 이상 벗어난 방향을 바라보면 해당 건물이 선택되지 않는다.
- 여러 건물이 시야각 안에 있으면 방향 오차와 거리를 기준으로 가장 타당한 건물이 선택된다.
- VPS 위치가 GPS 위치보다 정확도 값이 좋으면 VPS 위치를 우선한다.
- VPS 결과가 없거나 신뢰도가 낮으면 GPS 위치로 fallback한다.
- ray가 긴 건물의 외곽 polygon을 통과하면 중심점이 화면 중앙에서 벗어나도 해당 건물이 선택된다.
- 가까운 건물과 먼 건물이 같은 heading 근처에 있으면 polygon 최단 거리와 ray 교차 여부로 가까운 건물이 우선된다.
- 1등/2등 후보 점수 차이가 8점 미만이면 단일 건물이 아니라 `ambiguous`로 반환된다.

## 실제 기기 검증으로 남길 항목

- 현재 위치에서 VPS가 정상 초기화되는지
- VPS 위치가 GPS보다 체감상 정교한지
- 카메라를 실제 건물에 향했을 때 선택 결과가 맞는지
- 고층 건물, 좁은 골목, 해변처럼 특징점이 다른 환경에서 안정적으로 동작하는지

## 완료 조건

- `pnpm exec jest --runInBand` 통과
- `pnpm exec tsc --noEmit` 통과
- 신규 순수 로직 테스트가 실제 API 키와 실제 카메라 없이 통과
- 구현 스레드가 실제 기기에서 확인해야 할 항목을 별도 체크리스트로 보고
