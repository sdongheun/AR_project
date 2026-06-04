# ARBusan 프로젝트 상태 요약

다음 작업자가 컨텍스트 없이 읽어도 이어서 작업할 수 있도록 현재 상태만 축약해 둔다. 세부 변경 이력은 기록하지 않는다.

문서 전체 목차는 `ARBusan/docs/00_INDEX.md`에서 관리한다.

## 1. 현재 목표

- 프로젝트: `ARBusan`
- 방식: iOS Swift 네이티브
- 현재 MVP 방향: **TourAPI 목적지 후보 + TMAP 보행자 도착점 + AR 3D 마커/화살표 안내**
- 최종 목표: TourAPI 부산 관광지/랜드마크 인식
- 현재 테스트 대상: 김해 목업 4개 + 용원 목업 4개
- 기존 React Native `mobile` 프로젝트는 참고용으로 보존

현재 인식 구조:

```text
김해/용원 목업 후보
+ 카메라 heading 기반 방향 후보
+ VPS/위치 정확도
+ projection matrix / 2D overlay
+ WGS84/RealityKit 3D 마커 실험
+ TMAP 보행자 경로 마지막 도착 좌표 검증
-> 목적지 후보 / 방향 안내 / 3D 도착점 표시
```

현재 UX 방향:

```text
3D 마커:
    TMAP 보행자 경로의 마지막 도착 지점 표시

길찾기 화살표:
    현재 위치에서 목적지까지 이동 방향 안내

edge marker:
    화면 밖 후보 방향 안내
```

기존 “건물 외벽에 3D 텍스트를 직접 붙이는 방식”과 “VWorld Polygon 기반 대표/정문 좌표 자동 계산”은 테스트 교훈만 남긴다. 새 기본 방향은 TMAP 보행자 길찾기의 마지막 도착 좌표에 3D 마커를 고정하고, 정확한 이동 방향은 경로 화살표로 제공하는 방식이다.

## 2. 현재 실행 상태

앱은 현재 TourAPI를 호출하지 않고 김해/용원 목업 건물로 실행된다.

| 이름 | 주소 | ID |
| --- | --- | --- |
| 투썸플레이스 | 경남 김해시 인제로 192 | `mock-gimhae-twosome-inje-192` |
| 올리브영 | 경남 김해시 인제로 190 | `mock-gimhae-oliveyoung-inje-190` |
| 후참잘 | 경남 김해시 인제로 191 | `mock-gimhae-hoochamjal-inje-191` |
| 더존 101 | 경상남도 김해시 인제로 266 | `mock-gimhae-thezone101-inje-266` |
| 맥도날드 진해 용원 | 진해 용원 테스트 좌표 | `mock-jinhae-yongwon-mcdonalds` |
| LG전자 용원점 | 진해 용원 테스트 좌표 | `mock-jinhae-yongwon-lg-electronics` |
| 다이소 용원점 | 진해 용원 테스트 좌표 | `mock-jinhae-yongwon-daiso` |
| 고기집 | 진해 용원 테스트 좌표 | `mock-jinhae-yongwon-meat-restaurant` |

목업 데이터 위치:

```text
ARBusan/ARBusan/Data/Mock/MockTourismSpots.swift
```

## 3. 구현된 것

- SwiftUI + ARKit/RealityKit AR 카메라 화면
- Vision OCR을 AR 카메라 프레임에 연결
- ARCore Geospatial 세션 생성 및 ARFrame 전달
- CoreLocation/VPS 결과를 `LocationSnapshot`으로 저장
- AR 카메라 heading 계산
- AR 카메라 pose 진단값 표시: pitch/yaw/roll, AR session position
- 현재 위치 + heading + 후보 좌표로 `카메라 방향 후보` 자동 계산
- heading 변화량이 크면 점수화에 쓰는 공간 신뢰도를 한 단계 낮춤
- 선택 Polygon 외곽점의 화면 투영/시야 교차 진단 로그 표시
- VPS는 건물 후보가 아니라 위치 정확도 신호로만 반영
- 수동 `VPS 후보 건물`, 수동 `Polygon 일치 건물` 선택 UI 제거
- 카메라 방향 후보가 바뀌면 브이월드 건물통합정보에서 해당 후보 주변 Polygon을 자동 조회
- 조회한 Polygon 외곽 좌표를 `BuildingPolygon`으로 저장
- 브이월드 후보 Polygon 중 POI 좌표가 내부에 포함되는 Polygon을 우선 선택
- 브이월드 Polygon properties를 로그로 남기고 건물명/높이/지상층수를 파싱
- 건물 높이 결정 정책 추가: 브이월드 HEIGHT, Streetscape Geometry 입력값, 층수 추정, 기본값 순서
- OCR, 카메라 방향, 위치 정확도, Polygon 신호를 점수화하는 인식 파이프라인
- OCR과 공간 후보가 충돌하면 자동 확정하지 않고 후보 선택으로 전환
- OCR 없이 VPS/Polygon만 맞으면 `건물 인식됨`이 아니라 `근처 후보 감지`로 표시
- Scene Semantics와 OCR은 발열/효과 대비 문제로 현재 메인 테스트 UI에서 제외
- projection matrix 기반 2D 라벨/edge marker 표시
- WGS84 Anchor + RealityKit Entity로 3D 구체/텍스트 표시 실험
- 여러 근처 POI의 WGS84 Anchor를 동시에 유지하는 구조
- stable origin 기반 3D 위치 안정화
- 기존 외벽 후보점 방식과 대표/정문 자동 계산 방식의 한계를 확인하고 TMAP 도착점 방식으로 전환 예정
- `preferredMarkerCoordinate`/`entranceCoordinate`가 있으면 기존 외벽 후보점보다 우선해 3D WGS84 후보로 사용하는 구조
- TMAP 보행자 경로 API로 더존101/투썸/후참잘/올리브영의 마지막 도착 좌표가 POI 중심에서 도로/접근 지점 쪽으로 보정되는 것을 확인
- SwiftData 방문/수집 상태 모델
- 후보 선택/도감 화면
- 테스트 기록 문서: `ARBusan/docs/testing/TEST_RESULTS.md`

## 4. 보존된 비활성 코드

TourAPI 코드는 삭제하지 않고 비활성화했다.

- 김해 TourAPI 요청 파라미터:
  - `baseYm=202504`
  - `areaCd=48`
  - `signguCd=48250`
- 부산광역시 16개 구/군 요청 파라미터 파일:
  - `ARBusan/ARBusan/Data/TourAPI/TourAPIAreaRequest.swift`
- TourAPI 클라이언트:
  - `ARBusan/ARBusan/Data/TourAPI/TourAPIClient.swift`

현재 앱 시작 시에는 `MockTourAPIClient`/목업 데이터를 사용한다. TourAPI를 다시 켤 때는 실제 응답 필드명과 좌표 파싱을 먼저 확인해야 한다.

## 5. Polygon 조회/선택 로직

현재 Polygon 흐름:

```text
카메라 heading + 현재 위치
-> 카메라 방향 후보 건물 선택
-> 해당 후보 POI 좌표 중심으로 브이월드 BOX 조회
-> BOX와 겹치는 브이월드 건물 feature 목록 수신
-> Polygon geometry 파싱
-> POI가 내부에 포함되는 Polygon 우선 선택
-> 없으면 POI와 Polygon 외곽 최단 거리로 보수적 fallback 또는 비건물형 처리
-> 선택된 Polygon을 공간 신호로 점수화
```

현재 브이월드 요청:

- 엔드포인트: `https://api.vworld.kr/req/data`
- 데이터 레이어: `LT_C_SPBD`
- 좌표계: `EPSG:4326`
- `geomFilter`: `BOX(minLon,minLat,maxLon,maxLat)`
- 검색 BOX: POI 중심 위도/경도 `±0.00025도`
- API 키는 UI 로그에서 `REDACTED`로 숨긴다.

현재 로그로 확인 가능한 것:

- 요청 대상 POI 좌표
- 실제 브이월드 요청 URL
- HTTP 상태와 브이월드 `response.status`
- BOX 안에서 반환된 `feature 개수`
- 앱이 파싱한 `Polygon 개수`
- 후보 Polygon별 외곽 좌표 수, centroid, POI 포함 여부, 전체 외곽 좌표
- 후보 Polygon별 properties 전체와 파싱된 건물명/높이/지상층수
- 선택 Polygon의 높이 결정 결과와 출처/신뢰도/사유
- POI 포함 Polygon 개수
- POI와 Polygon 외곽 최단 거리
- 최종 선택 기준: `POI 내부 포함`, `외곽 3m 이내 fallback`, `자동 선택 보류`, `비건물형/point 처리`

중요한 해석:

- `feature 개수 N`은 카메라 인식 결과가 아니라, 브이월드가 POI BOX와 겹친 건물 데이터를 N개 반환했다는 뜻이다.
- 후보 Polygon 좌표는 BOX 안에 있는 좌표만 자른 것이 아니라, 브이월드가 반환한 각 건물 외곽 좌표다.
- 현재 선택 기준은 `POI 포함 Polygon` 우선이다. TourAPI POI가 실제 건물 내부 좌표라면 이 방식이 centroid만 보는 방식보다 정확하다.
- 브이월드 속성은 건물마다 제공 수준이 다르다. 부산/김해 샘플에서는 정확한 `HEIGHT`는 거의 없고, 층수는 `gro_flo_co`로 제공되는 경우가 많았다.
- 현재 높이 결정은 `HEIGHT`가 있으면 사용하고, 이후 Streetscape Geometry mesh 높이 입력, `gro_flo_co * 3.3m`, 기본 5m 순서로 fallback한다.
- POI가 어떤 Polygon에도 포함되지 않으면 가까운 건물에 무조건 붙이지 않는다. 외곽 3m 이내만 fallback하고, 3~8m는 후보 로그만 남기며, 8m 초과는 비건물형/point 관광지로 처리한다.
- 실내에서는 VPS/위치/heading이 흔들릴 수 있으므로 Polygon 조회 성공과 “카메라가 실제 그 Polygon을 보고 있음”은 별개의 문제다.

## 6. API 키 관리

사용 예정 키:

- `TOUR_API_KEY`: TourAPI 관광지/랜드마크 데이터
- `VWORLD_API_KEY`: 브이월드 Polygon/공간 검증
- `GOOGLE_ARCORE_API_KEY`: ARCore Geospatial/VPS
- `TMAP_API_KEY`: 보행자 경로/마지막 도착 좌표/향후 길찾기 화살표

실제 키는 아래 파일에만 둔다.

```text
ARBusan/Config/Secrets.local.xcconfig
```

이 파일은 git에 포함하지 않는다. `Base.xcconfig`에는 실제 키를 넣지 않는다.

## 7. 현재 한계

- OCR과 Scene Semantics는 현재 주 로직에서 제외했다.
- VPS는 건물 후보로 쓰지 않고 위치 정확도 신호로만 쓴다.
- Polygon 후보는 브이월드 조회 결과가 있으면 실제 외곽 좌표 기반으로 반영한다.
- 브이월드 Polygon 선택은 POI 포함 여부까지 개선됐다.
- 3D 렌더링은 WGS84/RealityKit으로 확인했지만, 기존 외벽 부착형 배치는 가까운 건물/도심/위치 흔들림에서 안정성이 부족했다.
- 앞으로는 외벽점을 계속 따라가는 방식이 아니라 TMAP 보행자 길찾기 마지막 도착 좌표를 3D 마커 기준으로 사용한다.
- 카메라 heading은 실내에서 자기장/기기 자세/위치 오차 때문에 실제 시야와 어긋날 수 있다.
- 실내 VPS가 `보통`이면 위치 오차가 몇 m만 나도 가까운 건물 경계 판단이 크게 흔들릴 수 있다.
- TourAPI 김해/부산 로딩은 현재 비활성화 상태다.
- VPS 미지원 지역에서는 ARCore Geospatial 정밀 VPS를 기대하기 어렵고, CoreLocation + heading + Polygon/POI 중심으로 동작한다.

## 8. 정확도를 위해 개선해야 할 부분

세부 기술 후보와 단계별 적용 판단은 아래 자식 문서에 둔다.

```text
ARBusan/docs/planning/AR_TECH_ROADMAP.md
```

우선순위:

1. TMAP 도착 좌표 방식으로 3D 기본 좌표 교체
   - 방향 변경: TMAP 보행자 경로 마지막 도착 좌표를 3D 기본 좌표로 사용
   - 다음: `TMAP_API_KEY` 앱 연결, TMAP 클라이언트, 마지막 좌표 파싱, 캐시 구현
   - 기존 VWorld 외벽 ray/nearest facade/대표점은 fallback 또는 디버그로 낮춤
2. 3D 마커와 길찾기 역할 분리
   - 3D는 목적지 도착점
   - 경로 화살표는 현재 위치에서 목적지까지 이동 방향
   - 관광지 정보는 최종적으로 3D 마커 hit/tap 이벤트로 표시
   - edge marker는 화면 밖 방향 안내
3. 위치/heading 신뢰도 기반 보수적 갱신
   - stable origin이 흔들리면 3D 좌표를 새로 확정하지 않음
   - heading은 방향 문구와 edge marker에 주로 사용
4. TourAPI 재연결 전 확인
   - TourAPI POI를 목적지로 보고 TMAP 도착 좌표가 안정적으로 나오는지 샘플로 확인한다.
   - 관광지가 건물형이든 비건물형이든 MVP에서는 TMAP 도착점 기반으로 통일한다.
5. 건물형/비건물형 표시 검증
   - VWorld는 필수 경로가 아니라 이상 케이스 검증/보정에 사용한다.

## 9. 실행 기준

개발 실행:

```sh
cd /Users/shindongheun/Desktop/myProject/ar/ARBusan
pod install
open ARBusan.xcworkspace
```

빌드 검증:

```sh
xcodebuild -workspace ARBusan.xcworkspace -scheme ARBusan -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath ./.derivedData CODE_SIGNING_ALLOWED=NO build-for-testing
```

주의:

- `ARBusan.xcodeproj`가 아니라 `ARBusan.xcworkspace`를 연다.
- `project.yml` 수정 후에는 `xcodegen generate`를 실행하고, 필요하면 `pod install`도 다시 실행한다.
- AR/카메라/VPS 검증은 시뮬레이터가 아니라 실제 iPhone에서 한다.
