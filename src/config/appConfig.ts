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
  id: 'gimhae-inje230-50-17',
  name: '김해 인제로230번길 50-17',
  category: 'building',
  categoryLabel: '건물',
  address: '경상남도 김해시 인제로230번길 50-17',
  latitude: 35.247217005,
  longitude: 128.906748565,
  altitude: 0,
};
