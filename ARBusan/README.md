# ARBusan

`ARBusan`은 TourAPI 기반 부산 관광지/랜드마크 중 건물형 대상을 VPS, 브이월드 공간 정보, 카메라 프레임 인식으로 식별하는 iOS 네이티브 앱이다.

## 현재 세팅

- Swift 5.10+
- iOS 17+
- SwiftUI + UIKit
- ARKit
- RealityKit
- Vision
- CoreLocation
- SwiftData
- ARCore Geospatial SDK for iOS는 CocoaPods로 연결 예정

## 프로젝트 생성

```sh
cd ARBusan
xcodegen generate
open ARBusan.xcodeproj
```

## API 키 설정

실제 키는 `Config/Secrets.local.xcconfig`에 넣는다. 이 파일은 git에 포함하지 않는다.

```sh
cd ARBusan
cp Config/Secrets.example.xcconfig Config/Secrets.local.xcconfig
```

`Config/Secrets.local.xcconfig`:

```xcconfig
TOUR_API_KEY = ...
VWORLD_API_KEY = ...
GOOGLE_ARCORE_API_KEY = ...
```

키를 수정한 뒤에는 프로젝트를 다시 생성한다.

```sh
xcodegen generate
```

ARCore Geospatial SDK를 실제로 연결할 때:

```sh
cd ARBusan
pod install
open ARBusan.xcworkspace
```

## 초기 목업 데이터

김해 실기기 테스트용 목업 건물은 `ARBusan/Data/Mock/MockTourismSpots.swift`에 둔다. 데이터 구조는 나중에 부산 TourAPI 응답으로 교체하기 쉽도록 `TourismSpot` 도메인 모델을 따른다.

현재 등록된 목업:

- 투썸플레이스, 경남 김해시 인제로 192
- 올리브영, 경남 김해시 인제로 190
- 후참잘, 경남 김해시 인제로 191

## 현재 건물 인식 MVP 동작

- AR 카메라 화면을 띄운다.
- 김해 목업 건물 후보 3개를 앱 상태에 로드한다.
- 텍스트 입력값을 카메라 OCR 결과처럼 사용해 건물 인식 파이프라인을 실행한다.
- 위치 신뢰도와 polygon 검증 후보를 선택할 수 있다.
- VPS 주변 후보와 브이월드 polygon 일치 후보를 선택할 수 있다.
- 카메라 OCR, VPS 후보, polygon 검증이 일치하면 자동 인식 결과를 보여준다.
- 후보가 모호하면 2-3개 건물 후보 중 사용자가 선택한다.
- 선택/인식 결과는 도감 화면에서 확인한다.

## 참고

ARCore Geospatial 공식 설정은 Google 문서 기준으로 `ARCore/Geospatial` CocoaPods 의존성과 Google Cloud의 ARCore API 활성화가 필요하다.
