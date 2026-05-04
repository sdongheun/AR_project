# AR Map Mobile

React Native 0.83 + `@reactvision/react-viro` 기반의 AR Map MVP 부트스트랩 프로젝트다.

## 현재 포함된 것

- iPhone 우선 React Native bare 앱
- Viro AR 수동 네이티브 링크 설정
- 카메라/위치 권한 요청 플로우
- 현재 위치 확인 UI
- AR 실행용 기본 `ViroARSceneNavigator`
- VWorld 연동용 설정 골격

## 실행

```sh
pnpm install
cd ios && pod install && cd ..
pnpm start
```

다른 터미널에서:

```sh
pnpm ios
```

```sh
pnpm android
```

## 주의

- Viro AR은 iOS 시뮬레이터와 Android 에뮬레이터에서 정상 동작하지 않는다.
- 실제 AR 확인은 실기기에서 진행해야 한다.
- VWorld 키 같은 민감값은 `mobile/.env.local`에만 둔다.

## 다음 작업

1. VWorld 3D 응답 스펙을 확정한다.
2. 단일 건물 좌표를 실제 API 응답으로 바꾼다.
3. GPS 좌표와 AR 마커 오차 보정 로직을 붙인다.

## 건물 꼭짓점 테스트

브이월드 검색 API와 WFS를 이용해 특정 주소의 건물 외곽 꼭짓점 좌표를 출력할 수 있다.

```sh
pnpm print:building-vertices
```

다른 주소로 테스트하려면:

```sh
pnpm print:building-vertices -- "경남 김해시 인제로230번길 50-17"
```
