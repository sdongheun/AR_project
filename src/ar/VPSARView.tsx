import React from 'react';
import { requireNativeComponent, ViewProps } from 'react-native';

// 네이티브에서 전달받을 props 정의
interface VPSARViewProps extends ViewProps {
  apiKey?: string; // 구글 API 키 추가
  // 예: target 핀의 위도, 경도, 고도 등
  targetLatitude?: number;
  targetLongitude?: number;
  targetAltitude?: number;
  // 네이티브에서 AR 상태가 변할 때 호출될 콜백
  onTrackingStatusChange?: (event: { nativeEvent: { status: string } }) => void;
}

// 'VPSARView'라는 이름의 네이티브 모듈(Android/iOS 컴포넌트)을 연결합니다.
// 앱 실행 시 이 이름과 동일한 Native ViewManager가 없으면 에러가 발생합니다.
const NativeVPSARView = requireNativeComponent<VPSARViewProps>('VPSARView');

export function VPSARView(props: VPSARViewProps) {
  return <NativeVPSARView {...props} />;
}
