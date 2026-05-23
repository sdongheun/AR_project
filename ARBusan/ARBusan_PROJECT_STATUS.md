# ARBusan 프로젝트 상태 요약

이 문서는 다음 작업자가 바로 이어서 작업할 수 있을 정도의 핵심 상태만 남긴다. 세부 변경 이력은 기록하지 않는다.

## 1. 현재 방향

- 프로젝트명: `ARBusan`
- 구현 방식: iOS Swift 네이티브
- 기존 `mobile` React Native 프로젝트는 참고용으로 보존
- 현재 MVP 목표: 지도/길찾기가 아니라 **카메라 기반 건물 인식**
- 최종 목표: TourAPI의 부산 관광지/랜드마크를 대상으로 건물 인식
- 현재 테스트 지역: 사용자의 현재 위치 문제로 김해 목업 건물 사용

인식 흐름:

```text
김해 목업 건물 후보 + 카메라 OCR + 카메라 방향 + 현재 위치/VPS + 브이월드 Polygon
-> 후보 점수화
-> 고신뢰 자동 인식
-> 애매하면 후보 선택
```

## 2. 핵심 결정

- 단순 카메라 방향 기반 인식은 사용하지 않는다.
- 카메라가 실제 건물/간판을 보고 OCR 및 추후 이미지 인식을 수행하는 방향이다.
- 지도 API는 현재 MVP에서 제외한다.
- 사용하는 키:
  - `TOUR_API_KEY`: TourAPI 관광지/랜드마크 데이터
  - `VWORLD_API_KEY`: 건물 Polygon/공간 검증
  - `GOOGLE_ARCORE_API_KEY`: ARCore Geospatial/VPS
- 실제 키는 `Config/Secrets.local.xcconfig`에만 둔다. 이 파일은 git에 포함하지 않는다.
- `Config/Base.xcconfig`에는 실제 키를 넣지 않는다.

## 3. 현재 구현 상태

완료된 기반:

- `ARBusan/` Swift 네이티브 프로젝트 생성
- XcodeGen 기반 `project.yml`
- CocoaPods 기반 `ARBusan.xcworkspace`
- `ARCore/Geospatial` Pod 연결
- `ARBusan.xcworkspace` 기준 빌드 성공
- SwiftUI + ARKit/RealityKit 기본 AR 카메라 화면
- Vision OCR을 AR 카메라 프레임에 연결
- TourAPI `LocgoHubTarService1/areaBasedList1` 김해 중심 관광지 조회 연결
- TourAPI 요청 기준: `baseYm=202504`, `areaCd=48`, `signguCd=48250`, `numOfRows=100`
- 부산광역시 16개 구/군 TourAPI 요청 파라미터 파일 추가
- 현재 실행 경로에서는 TourAPI 김해/부산 후보를 비활성화하고 김해 목업 건물 3개로 테스트
- ARCore `GARSession` 생성 및 Geospatial 모드 활성화
- ARKit `ARFrame`을 `GARSession.update`로 전달
- CoreLocation/VPS 결과를 `LocationSnapshot` 모델로 저장
- SwiftData 방문/수집 상태 모델
- 목업 후보/후보 선택/도감 화면

현재 MVP UI:

- API 키 상태 표시
- TourAPI 비활성화/목업 사용 상태 표시
- VPS/위치 상태 표시
- `OCR 입력`, `VPS/위치 후보`, `브이월드 Polygon 후보`를 명확히 구분 표시
- 카메라 OCR 결과를 `OCR 입력`에 자동 반영
- 내 위치와 AR 카메라 heading으로 `카메라 방향 후보` 자동 계산
- 기본 후보 데이터는 김해 목업 건물 3개
- TourAPI 김해/부산 요청 코드는 보존되어 있으나 현재 앱 시작 시 자동 호출하지 않음
- VPS 후보와 Polygon 후보는 현재 수동 목업 선택
- `건물 인식 실행`으로 점수화 결과 표시
- OCR과 VPS/Polygon이 서로 다른 건물을 가리키면 자동 확정하지 않고 후보 선택 상태로 전환
- OCR 없이 VPS/Polygon만 맞는 경우 `건물 인식됨`이 아니라 `근처 후보 감지`로 표시

현재 목업 건물:

| ID | 이름 | 주소 |
| --- | --- | --- |
| `mock-gimhae-twosome-inje-192` | 투썸플레이스 | 경남 김해시 인제로 192 |
| `mock-gimhae-oliveyoung-inje-190` | 올리브영 | 경남 김해시 인제로 190 |
| `mock-gimhae-hoochamjal-inje-191` | 후참잘 | 경남 김해시 인제로 191 |

## 4. 현재 한계

- OCR과 카메라 방향 후보는 자동 갱신된다.
- 카메라 방향 후보는 자동 계산되지만, 실제 현장에서 heading 방향이 맞는지 실기기 보정 테스트가 필요하다.
- TourAPI 김해/부산 후보 로딩은 현재 비활성화 상태다. 다시 켤 때는 응답 필드명과 좌표 파싱을 실응답 기준으로 확인해야 한다.
- VPS 후보와 Polygon 후보는 아직 자동으로 바뀌지 않는다.
- 후참잘 간판을 비춰 OCR이 후참잘로 바뀌고 VPS/Polygon 선택이 투썸으로 남아 있으면, 이제 투썸을 자동 인식하지 않고 후보 선택이 필요하다고 표시한다.
- VPS/Polygon을 특정 건물로 수동 세팅하면, 카메라가 그 건물을 바라보지 않아도 공간 신호만으로 `근처 후보 감지`가 뜰 수 있다. 이는 정상이며 실제 건물 인식 확정은 아니다.
- 실외에서는 위치 신뢰도가 `높음`, 실내에서는 `보통`으로 나오는 것이 확인됐다. 이는 정상 범위로 보되, 실내에서는 자동 확정 기준을 더 보수적으로 가져가야 한다.
- 실제 VPS 추적, `GARAPIKey` 인증, 위치 정확도, OCR 안정성은 실기기에서 계속 확인해야 한다.
- 브이월드 Polygon 실제 조회/자동 매칭은 아직 미구현이다.
- 부산 TourAPI 요청 파라미터는 준비되어 있으나 현재 비활성화 상태다.

## 5. 다음 작업

가장 먼저 할 일:

1. 실기기에서 카메라 방향 후보가 실제 바라보는 목업 후보와 일치하는지 확인한다.
   - UI의 `카메라 heading`과 `카메라 방향 후보`를 보며 후보별로 테스트한다.
   - 방향이 반대로 나오거나 각도 차이가 크면 heading 계산식을 보정한다.
2. OCR과 방향/VPS/Polygon이 다른 건물을 가리키는 충돌 케이스를 실기기에서 확인한다.

그 다음 구현:

1. 현재 위치/VPS 결과로 김해 목업 후보 중 가까운 후보 자동 선택.
2. 브이월드 API로 후보 주소/좌표의 Polygon 조회.
3. Polygon 자동 매칭 결과를 앱의 `Polygon 일치 건물`에 반영.
4. TourAPI 김해/부산 후보 로딩을 다시 켤지 결정하고, 켠다면 실응답 파싱을 보정.

## 6. 실행 기준

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

- ARCore 연결 후에는 `ARBusan.xcodeproj`가 아니라 `ARBusan.xcworkspace`를 열어야 한다.
- `project.yml`을 수정했을 때만 `xcodegen generate`가 필요하다.
- `Podfile`을 수정했으면 `pod install`이 필요하다.
- AR/카메라/VPS 검증은 시뮬레이터가 아니라 실제 iPhone에서 해야 한다.
