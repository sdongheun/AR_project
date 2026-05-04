/**
 * @format
 */

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';

jest.mock('@reactvision/react-viro', () => ({
  ViroAmbientLight: 'ViroAmbientLight',
  ViroARSceneNavigator: 'ViroARSceneNavigator',
  ViroARScene: 'ViroARScene',
  ViroBox: 'ViroBox',
  ViroMaterials: {
    createMaterials: jest.fn(),
  },
  ViroNode: 'ViroNode',
  ViroText: 'ViroText',
  ViroTrackingStateConstants: {
    TRACKING_NORMAL: 3,
  },
  isARSupportedOnDevice: jest.fn().mockResolvedValue({isARSupported: true}),
  requestRequiredPermissions: jest
    .fn()
    .mockResolvedValue({camera: true, location: true}),
}));

jest.mock('react-native-geolocation-service', () => ({
  getCurrentPosition: jest.fn(),
}));

import App from '../App';

test('renders correctly', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });
});
