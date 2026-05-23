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
카메라 OCR + 현재 위치/VPS + 브이월드 Polygon
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
- ARCore `GARSession` 생성 및 Geospatial 모드 활성화
- ARKit `ARFrame`을 `GARSession.update`로 전달
- CoreLocation/VPS 결과를 `LocationSnapshot` 모델로 저장
- SwiftData 방문/수집 상태 모델
- 목업 후보/후보 선택/도감 화면

현재 MVP UI:

- API 키 상태 표시
- VPS/위치 상태 표시
- `OCR 입력`, `VPS/위치 후보`, `브이월드 Polygon 후보`를 명확히 구분 표시
- 카메라 OCR 결과를 `OCR 입력`에 자동 반영
- VPS 후보와 Polygon 후보는 현재 수동 목업 선택
- `건물 인식 실행`으로 점수화 결과 표시

현재 목업 건물:

| ID | 이름 | 주소 |
| --- | --- | --- |
| `mock-gimhae-twosome-inje-192` | 투썸플레이스 | 경남 김해시 인제로 192 |
| `mock-gimhae-oliveyoung-inje-190` | 올리브영 | 경남 김해시 인제로 190 |
| `mock-gimhae-hoochamjal-inje-191` | 후참잘 | 경남 김해시 인제로 191 |

## 4. 현재 한계

- OCR만 자동 갱신된다.
- VPS 후보와 Polygon 후보는 아직 자동으로 바뀌지 않는다.
- 그래서 후참잘 간판을 비춰 OCR이 후참잘로 바뀌어도, VPS/Polygon 선택이 투썸으로 남아 있으면 투썸이 `보통`으로 인식될 수 있다.
- 실제 VPS 추적, `GARAPIKey` 인증, 위치 정확도, OCR 안정성은 실기기에서 계속 확인해야 한다.
- 브이월드 Polygon 실제 조회/자동 매칭은 아직 미구현이다.
- 부산 TourAPI 데이터셋 연결은 아직 미구현이다.

## 5. 다음 작업

가장 먼저 할 일:

1. OCR/VPS/Polygon 신호가 서로 충돌할 때 잘못된 건물로 자동 확정하지 않도록 점수 정책 수정.
2. OCR은 후참잘인데 VPS/Polygon이 투썸이면 `투썸 인식됨`이 아니라 `신호 불일치: 확인 필요` 또는 후보 선택으로 보내기.
3. 실기기에서 OCR 자동 입력, VPS 상태, 위치 정확도 표시 확인.

그 다음 구현:

1. 현재 위치/VPS 결과로 김해 목업 후보 3개 중 가까운 후보 자동 선택.
2. 브이월드 API로 목업 건물 주소의 Polygon 조회.
3. Polygon 자동 매칭 결과를 앱의 `Polygon 일치 건물`에 반영.
4. 목업 건물 2개 추가.
5. 부산 TourAPI 데이터셋 연결 준비.

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
