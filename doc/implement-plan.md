# 구현 계획

## 문서 목적

컨텍스트 압축 이후에도 구현 방향을 잃지 않기 위한 실행 계획이다. 작업을 시작하거나 이어갈 때 이 파일과 `doc/ar-busan-tourism-current-state-and-harness.md`를 먼저 확인한다.

## 운영 규칙

- 이 스레드는 PM 스레드이며 `.md` 파일만 수정한다.
- 실제 코드 구현은 프론트엔드/백엔드/네이티브/테스트 등 별도 구현 스레드에서 수행한다.
- 별도 구현 스레드에 전달할 작업은 이 문서의 체크리스트와 필요한 지시 문서로 정리한다.
- 큰 로직 수정 후에는 이 파일의 작업 상태를 갱신한다.
- 완료한 항목은 `[x]`, 진행 중인 항목은 `[~]`, 남은 항목은 `[ ]`로 표시한다.
- 구현 세부가 길어지면 코드와 테스트에 남기고, 이 문서는 다음 행동을 결정할 정도로만 유지한다.
- 현재 상태 문서는 200줄 미만으로 유지하고, 상세 실행 계획은 이 파일에 둔다.

## 현재 기준점

- 앱 디렉터리: `mobile`
- 현재 검증 명령:
  - `pnpm exec jest --runInBand`
  - `pnpm exec tsc --noEmit`
  - `pnpm exec eslint src/services/vworldBuildingService.ts __tests__/vworldBuildingService.test.ts`
- 현재 통과 상태:
  - Jest 통과
  - TypeScript 통과
  - ESLint 대상 파일 통과

## 1단계: 테스트 가능한 공간 계산 코어

목표: 실제 기기에서만 확인 가능한 VPS 원천 동작을 제외하고, "내 위치 + 카메라 방향 + 브이월드 건물 후보"가 올바른 건물 정보로 이어지는지 테스트 코드로 검증한다.

- [x] Jest 설정 추가
- [x] 브이월드 순수 로직 테스트 추가
- [x] bbox 부동소수점 문자열 정규화
- [ ] VPS 응답을 앱 내부 위치 모델로 정규화하는 mapper 정의
- [ ] 카메라 heading/ray와 건물 polygon 후보를 이용한 "바라보는 건물" 선택 로직 정의
- [ ] 바라보는 건물 선택 로직의 fixture 기반 테스트 추가
- [ ] `ARMapScene.tsx`의 `getRelativeWorldPosition`, `isTargetInView`, `normalize`, `dot`을 순수 모듈로 이동
- [ ] AR 공간 계산 테스트 추가
- [ ] 거리/방위각 계산 유틸 추가
- [ ] 부산 샘플 좌표 기반 테스트 fixture 추가

권장 파일:

- `src/services/arSpatialMath.ts`
- `__tests__/arSpatialMath.test.ts`
- `src/services/geoMath.ts`
- `__tests__/geoMath.test.ts`

## 2단계: 관광지 도메인 모델 고정

- [ ] `TourismTarget` 타입 정의
- [ ] 건물형 관광지와 비실체화 관광지를 같은 모델로 표현
- [ ] 부산 주요 POI 샘플 10개 fixture 작성
- [ ] fixture를 앱 초기 데이터로 불러오는 mapper 작성
- [ ] 샘플 데이터 검증 테스트 추가

권장 모델 필드:

- `id`
- `name`
- `category`
- `shapeType: "point" | "building" | "area"`
- `center`
- `address`
- `description`
- `buildingPolygon`
- `heightMeters`
- `source`

## 3단계: 외부 API 계약 하네스

- [ ] 브이월드 검색 응답 fixture 저장
- [ ] 브이월드 WFS GeoJSON fixture 저장
- [ ] GIS건물통합정보 XML fixture 저장
- [ ] 한국관광공사 API 응답 fixture 저장
- [ ] 티맵 경로 응답 fixture 저장
- [ ] 각 API 응답을 앱 내부 모델로 바꾸는 mapper 테스트 작성

구현 원칙:

- 외부 API 호출부와 응답 mapper를 분리한다.
- mapper는 fixture 기반으로 네트워크 없이 테스트한다.
- 실제 API 호출 테스트는 별도 스크립트 또는 수동 검증으로 분리한다.

## 4단계: 위치/VPS 통합

- [ ] GPS 위치와 VPS 결과를 하나의 `LocationSnapshot`으로 정규화
- [ ] 위치 정확도, heading, timestamp를 포함한 상태 모델 정의
- [ ] VPS 실패 시 GPS fallback 정책 정의
- [ ] 개발자용 위치 시뮬레이션 입력 추가

권장 파일:

- `src/services/locationProvider.ts`
- `src/types/location.ts`
- `src/dev/locationFixtures.ts`

## 5단계: AR 마커와 길찾기

- [ ] 관광지 target을 AR anchor로 변환
- [ ] 건물 polygon vertex를 AR 마커 후보로 변환
- [ ] 비실체화 공간은 중심점/반경 기반 anchor로 변환
- [ ] 티맵 polyline을 AR 화살표 segment로 변환
- [ ] 경로 segment 테스트 추가

주의점:

- AR 렌더링보다 좌표 변환 테스트를 먼저 고정한다.
- 카메라/VPS가 없어도 route-to-anchor 변환은 테스트 가능해야 한다.

## 6단계: 미션과 저장소

- [ ] 부산 캐릭터 수집 모델 정의
- [ ] 방문 판정 기준 정의
- [ ] 로컬 저장 우선 구현
- [ ] Supabase는 계정/동기화가 필요해지는 시점에 도입

## 다음 작업

1. 프론트/테스트 구현 스레드에 `doc/implementation-brief-vps-building-recognition.md`를 전달한다.
2. 구현 스레드는 VPS 위치 정규화와 "카메라가 바라보는 건물" 선택 로직을 테스트 우선으로 만든다.
3. 실제 기기에서만 가능한 검증 항목은 수동 체크리스트로 남기고, 나머지는 fixture 기반 테스트로 고정한다.
4. 구현 결과를 받은 뒤 이 PM 스레드에서는 `.md` 문서만 갱신한다.
