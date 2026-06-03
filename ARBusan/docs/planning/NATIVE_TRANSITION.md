# ARBusan Swift 네이티브 전환 기준

## 문서 목적

이 문서는 기존 React Native 프로토타입과 새 부산 AR 앱 개발 명세를 비교한 뒤 확정한 제품/기술 방향을 기록한다.

현재 React Native 작업물은 프로토타입으로 보존한다. 다음 구현 방향은 `ARBusan`이라는 새 iOS 네이티브 Swift 프로젝트다.

## 확정된 결정

- 프로젝트명: `ARBusan`
- 1차 플랫폼: iOS 네이티브
- 권장 기술 스택:
  - Swift 5.10+
  - iOS 17+
  - SwiftUI + 필요한 경우 UIKit
  - ARKit
  - RealityKit
  - ARCore Geospatial SDK for iOS
  - 카메라 프레임 인식을 위한 Vision / Core ML
  - 로컬 수집/방문 상태 저장을 위한 SwiftData
- 크로스플랫폼 지원은 현재 목표가 아니다.
- React Native 구현은 저장된 프로토타입/참고 자료로만 유지한다.

## 제품 방향

앱은 단순 카메라 방향만으로 대상을 추정하지 않는다. TourAPI에서 제공하는 관광지/랜드마크를 하이브리드 AR 인식 흐름으로 식별해야 한다.

최종 서비스 범위:

- TourAPI가 제공하는 부산 관광지 및 랜드마크.
- 해당 장소 주변의 AR 탐험 경험.
- 실제 랜드마크/관광지를 카메라 기반으로 인식하는 기능.
- 차별화 요소로 선택 적용할 참여형 수집 기능:
  - 캐릭터 수집
  - 로컬 가이드 보상
  - 구별 진행률
  - 수집 도감

부산 현장 테스트 전 검증 범위:

- 실기기 테스트를 위해 현재 위치 근처의 김해 목업 건물/랜드마크를 사용한다.
- 실제 프로덕션 로직은 부산/TourAPI 기준으로 유지한다.
- 테스트 데이터는 이후 부산 데이터로 교체하기 쉽도록 TourAPI 모델과 호환되는 형태로 만든다.

초기 김해 목업 건물:

| ID | 이름 | 주소 | 테스트 메모 | 인식 검증 가치 |
| --- | --- | --- | --- | --- |
| `mock-gimhae-twosome-inje-192` | 투썸플레이스 | 경남 김해시 인제로 192 | 간판이 잘 보인다. 입구가 명확하다. 1층짜리 건물이며 상가는 2개만 있다. | 첫 OCR 테스트와 고신뢰 자동 인식 대상으로 적합하다. |
| `mock-gimhae-oliveyoung-inje-190` | 올리브영 | 경남 김해시 인제로 190 | 간판이 잘 보인다. 약 5층 건물이다. 여러 상가가 존재한다. | 한 건물 안에 여러 상가 후보가 있어 모호 후보 선택 테스트에 적합하다. |
| `mock-gimhae-hoochamjal-inje-191` | 후참잘 | 경남 김해시 인제로 191 | 간판이 잘 보인다. 약 2층 건물이다. 간판들이 빼곡하게 있다. | OCR 스트레스 테스트와 후보 구분 테스트에 적합하다. |

첫 현장 테스트 세트를 확정하려면 목업 건물 2개가 더 필요하다.

## 인식 전략

목표 인식 방식은 하이브리드 구조다.

```text
VPS / 현재 위치
-> 주변 TourAPI 후보 관광지
-> 브이월드 polygon / 좌표 검증
-> 카메라 프레임 인식
-> 신뢰도 점수화
-> 확정 랜드마크 표시 또는 후보 선택 UI
```

카메라 인식은 아래 신호를 단계적으로 결합한다.

1. VPS와 GPS 위치로 후보를 좁힌다.
2. TourAPI 랜드마크/관광지 메타데이터를 후보 원천으로 사용한다.
3. 브이월드 polygon과 공간 데이터를 이용해 실제 공간상 위치를 검증한다.
4. 간판이나 보이는 텍스트가 있으면 OCR을 사용한다.
5. 가능한 경우 랜드마크/건물 외관 이미지 매칭을 사용한다.

앱은 단일 신호에 의존하지 않는다. VPS, 카메라 인식, 공간 지오메트리가 서로를 교차 검증해야 한다.

## 인식 UX

자동 인식과 후보 선택을 섞은 모델을 사용한다.

- 신뢰도가 높으면 인식된 관광지 1개를 바로 표시한다.
- 결과가 모호하면 가능성이 높은 후보 2-3개를 보여주고 사용자가 선택하게 한다.
- 신뢰도가 낮으면 잘못된 장소를 확정적으로 표시하지 않는다.
- MVP 시연에서는 fallback으로 수동 후보 선택을 허용할 수 있다.

권장 신뢰도 단계:

- `high`: VPS/위치, 카메라 인식, polygon 검증이 모두 일치한다.
- `medium`: 위치와 카메라 신호 하나가 일치하지만 시각적 근거가 충분하지 않다.
- `low`: 대략적인 위치/반경 정보만 있다.
- `ambiguous`: 여러 후보의 신뢰도가 비슷하다.
- `none`: 신뢰할 수 있는 후보가 없다.

## MVP 해석

MVP는 "카메라 방향에 라벨을 띄우는 기능"이 아니다. MVP는 앱이 아래 흐름을 증명하는 단계여야 한다.

1. TourAPI 호환 모델에서 후보 관광지를 불러온다.
2. VPS/현재 위치로 후보 목록을 좁힌다.
3. 가능한 경우 공간 데이터로 후보를 검증한다.
4. 카메라 프레임 인식으로 후보 신뢰도를 높이거나 후보를 제외한다.
5. 확정 인식 결과 또는 작은 후보 목록을 보여준다.
6. 선택 기능으로 방문/수집 상태를 로컬에 저장한다.

## 권장 네이티브 프로젝트 구조

```text
ARBusan/
  ARBusanApp.swift
  App/
    AppState.swift
    Permissions/
  AR/
    ARSessionViewController.swift
    GeospatialSessionManager.swift
    RealityAnchorRenderer.swift
  Recognition/
    RecognitionPipeline.swift
    CandidateScorer.swift
    OCRRecognizer.swift
    VisualLandmarkRecognizer.swift
  Data/
    TourAPI/
    VWorld/
    Mock/
  Domain/
    TourismSpot.swift
    RecognitionResult.swift
    VisitState.swift
  Persistence/
    TourismSpotEntity.swift
    VisitRepository.swift
  UI/
    ARExploreView.swift
    CandidateSelectionView.swift
    CollectionBookView.swift
```

## RN 프로토타입에서 가져갈 점

- RN 코드는 아래 항목의 참고 자료로 유지한다.
  - 브이월드 polygon 실험
  - TourAPI 호환 목업 타겟 구조
  - 인식 점수화 아이디어
  - 현장 테스트에서 얻은 학습 내용
- React Native 아키텍처를 네이티브 앱에 그대로 가져가지 않는다.
- JS/RN 브릿지 이벤트 throttle 문제는 네이티브 AR 세션과 Swift concurrency 설계로 대체한다.
- 테스트는 Swift 단위 테스트와 현장 테스트용 GPX 시나리오 중심으로 다시 구성한다.

## 남은 질문

- 실기기 테스트에 사용할 김해 목업 건물 2개를 무엇으로 추가할 것인가?
- 첫 프로덕션 유사 데이터셋으로 사용할 부산 TourAPI 관광지 묶음은 무엇인가?
- 첫 카메라 인식 구현은 OCR, 외관 매칭, 또는 둘의 최소 조합 중 무엇을 우선할 것인가?
- 네트워크가 없을 때 시연에서 허용할 동작은 무엇인가?
- 수집/도감 기능은 첫 네이티브 프로토타입에 포함할 것인가, 인식 안정화 이후 붙일 것인가?
