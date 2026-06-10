# ARBusan Docs Index

이 문서는 ARBusan 문서의 진입점이다. 다음 작업자는 먼저 루트의 `ARBusan_PROJECT_STATUS.md`를 읽고, 세부 판단이 필요할 때 이 인덱스에서 필요한 문서만 찾아 읽는다.

## 1. 먼저 읽을 문서

| 순서 | 문서 | 역할 |
| --- | --- | --- |
| 1 | [`../ARBusan_PROJECT_STATUS.md`](../ARBusan_PROJECT_STATUS.md) | 현재 프로젝트 상태와 다음 작업 요약 |
| 2 | [`planning/AR_MVP_DIRECTION.md`](planning/AR_MVP_DIRECTION.md) | 현재 공모전 MVP 방향: 지도/레이더 + 카메라 AR 방향 안내 |
| 3 | [`planning/AR_TECH_ROADMAP.md`](planning/AR_TECH_ROADMAP.md) | 이전 AR 인식/라벨 기술 실험과 보류 판단 |

## 2. Planning

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| [`planning/AR_MVP_DIRECTION.md`](planning/AR_MVP_DIRECTION.md) | 공모전 MVP 기준과 새 구현 순서 | 활성 |
| [`planning/AR_TECH_ROADMAP.md`](planning/AR_TECH_ROADMAP.md) | AR 기술 판단, 처리 흐름, 작업 순서 | 참고/보류 판단 |
| [`planning/NATIVE_TRANSITION.md`](planning/NATIVE_TRANSITION.md) | React Native에서 Swift 네이티브로 전환한 배경과 초기 세팅 기록 | 보관/참고 |

## 3. Map

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| [`map/MAIN_2D_MAP_PLAN.md`](map/MAIN_2D_MAP_PLAN.md) | 메인 화면 2D 지도, 현재 위치, 관광지 마커, 하단 카드 작업 체크리스트 | 활성 |

## 4. Navigation

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| [`navigation/AR_NAVIGATION_LOGIC_PLAN.md`](navigation/AR_NAVIGATION_LOGIC_PLAN.md) | AR 길찾기 로직: TMAP 경로, 2D 방향 안내, turn boundary 3D 화살표, 도착 핀 체크리스트 | 활성 |
| [`navigation/turn-arrow-logic.html`](navigation/turn-arrow-logic.html) | 회전 지점 3D 화살표 표시 로직 시각화(판단 흐름·다이어그램·상수) | 보조/시각화 |

## 5. AR Label

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| [`ar-label/3D_LABEL_REFINEMENT_PLAN.md`](ar-label/3D_LABEL_REFINEMENT_PLAN.md) | 3D 구체/라벨의 기존 규칙과 실험 기록 | 보류/참고 |
| [`ar-label/3D_LABEL_OPTIMIZATION_PLAN.md`](ar-label/3D_LABEL_OPTIMIZATION_PLAN.md) | 3D 라벨 흔들림, stable origin, WGS84 anchor 최적화 | 보류/참고 |
| [`ar-label/EDGE_MARKER_RULES.md`](ar-label/EDGE_MARKER_RULES.md) | 화면 안/밖 2D marker, edge marker 규칙 | 참고 |

## 6. Testing

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| [`testing/HAEUNDAE_TOURAPI_INDOOR_DEBUG_PLAN.md`](testing/HAEUNDAE_TOURAPI_INDOOR_DEBUG_PLAN.md) | TourAPI 해운대구 샘플로 실내 계산 검증 | 보류/필요 시 |
| [`testing/TEST_RESULTS.md`](testing/TEST_RESULTS.md) | 사용자가 현장에서 확인한 테스트 결과 기록 | 활성 |
| [`testing/3D_LABEL_STABILITY_TESTS.md`](testing/3D_LABEL_STABILITY_TESTS.md) | 3D 라벨 장기 안정화 테스트 시나리오 | 후속 |

## 7. Archive

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| [`archive/DISABLED_FEATURES.md`](archive/DISABLED_FEATURES.md) | 발열/성능 문제로 현재 꺼둔 기능 기록 | 참고 |

## 8. 문서 관리 규칙

- 새 작업을 시작할 때는 `ARBusan_PROJECT_STATUS.md`와 이 문서만 먼저 읽는다.
- 구현 방향이 바뀌면 해당 세부 문서와 `ARBusan_PROJECT_STATUS.md`의 다음 작업만 갱신한다.
- 테스트 결과는 `testing/TEST_RESULTS.md`에만 남긴다.
- 새 문서는 `planning`, `map`, `navigation`, `ar-label`, `testing`, `archive` 중 하나에만 만든다.
- 한 파일은 가능한 200줄 내외를 목표로 한다.
- 200줄을 넘는 파일은 바로 삭제/축약하지 않고, 줄일 후보와 이유를 사용자에게 먼저 설명한다.
- 오래된 내용도 임의 삭제하지 않는다. 필요하면 `archive` 이동을 먼저 제안한다.

## 9. 줄 수 점검 기준

- 200줄 이하: 유지
- 200~260줄: 당장 문제는 아니지만 다음 정리 때 축약 후보
- 260줄 초과: 분할 또는 archive 이동 후보. 삭제 전 사용자 확인 필수
