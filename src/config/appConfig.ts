import type {MapTarget} from '../types/target';

export const appConfig = {
  appName: 'AR Map',
  arLibrary: '@reactvision/react-viro',
  platformPriority: 'iPhone 우선',
  vworld: {
    apiKind: '3D Map / Building Data',
    keySource: '.env.local',
  },
} as const;

export const demoTarget: MapTarget = {
  id: 'gimhae-sambang-169-4',
  name: '김해 삼방동 169-4',
  category: 'building',
  categoryLabel: '건물',
  address: '경상남도 김해시 삼방동 169-4',
  latitude: 35.24723621623184,
  longitude: 128.90656491699258,
  altitude: 0,
};
