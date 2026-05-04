import {appConfig} from '../config/appConfig';
import type {MapTarget} from '../types/target';

export type VWorldBootstrapState = {
  apiKind: string;
  configured: boolean;
};

export function getVWorldBootstrapState(): VWorldBootstrapState {
  return {
    apiKind: appConfig.vworld.apiKind,
    configured: Boolean(appConfig.vworld.keySource),
  };
}

export async function fetchNearbyTargets(): Promise<MapTarget[]> {
  throw new Error(
    'VWorld 3D 조회 계약은 아직 확정되지 않았습니다. 실제 요청 파라미터와 응답 매핑이 정해지면 이 함수에 연결하십시오.',
  );
}
