import React, {useEffect, useMemo, useRef, useState} from 'react';
import {StyleSheet} from 'react-native';
import {
  ViroAmbientLight,
  ViroARScene,
  ViroBox,
  ViroCameraTransform,
  ViroMaterials,
  ViroNode,
  ViroText,
  ViroTrackingStateConstants,
} from '@reactvision/react-viro';
import {demoTarget} from '../config/appConfig';
import type {LocationSnapshot} from '../types/location';
import type {MapTarget} from '../types/target';

ViroMaterials.createMaterials({
  markerPanel: {
    diffuseColor: '#dbe362',
  },
});

type SceneProps = {
  sceneNavigator: {
    viroAppProps?: {
      onRecognitionStateChange?: (status: RecognitionState) => void;
      target?: MapTarget;
      userLocation?: LocationSnapshot | null;
    };
  };
};

type RecognitionState = 'tracking' | 'success' | 'failure';

export function ARMapScene({sceneNavigator}: SceneProps) {
  const [trackingReady, setTrackingReady] = useState(false);
  const [recognitionState, setRecognitionState] =
    useState<RecognitionState>('tracking');
  const target = sceneNavigator.viroAppProps?.target ?? demoTarget;
  const userLocation = sceneNavigator.viroAppProps?.userLocation ?? null;
  const reportRecognitionState =
    sceneNavigator.viroAppProps?.onRecognitionStateChange;
  const lastReportedState = useRef<RecognitionState>('tracking');

  const targetPosition = useMemo(() => {
    if (!userLocation) {
      return [0, 0, -1.25] as [number, number, number];
    }

    return getRelativeWorldPosition(userLocation, target);
  }, [target, userLocation]);

  const targetDistance = useMemo(() => {
    return Math.sqrt(
      targetPosition[0] * targetPosition[0] +
        targetPosition[1] * targetPosition[1] +
        targetPosition[2] * targetPosition[2],
    );
  }, [targetPosition]);

  const markerScale = useMemo(() => {
    const baseScale = Math.max(0.22, Math.min(targetDistance / 18, 1.2));
    return [baseScale, baseScale, baseScale] as [number, number, number];
  }, [targetDistance]);

  const subLabel = useMemo(() => {
    if (!trackingReady) {
      return '트래킹을 안정화하는 중입니다.';
    }

    if (!userLocation) {
      return '현재 위치를 확인하지 못했습니다.';
    }

    return recognitionState === 'success'
      ? `${target.categoryLabel} · 인식 완료`
      : `${target.categoryLabel} · 인식 실패`;
  }, [recognitionState, target.categoryLabel, trackingReady, userLocation]);

  useEffect(() => {
    if (lastReportedState.current !== recognitionState) {
      lastReportedState.current = recognitionState;
      reportRecognitionState?.(recognitionState);
    }
  }, [recognitionState, reportRecognitionState]);

  return (
    <ViroARScene
      onCameraTransformUpdate={cameraTransform => {
        if (!trackingReady || !userLocation) {
          setRecognitionState('tracking');
          return;
        }

        const nextState = isTargetInView(cameraTransform, targetPosition)
          ? 'success'
          : 'failure';

        setRecognitionState(currentState =>
          currentState === nextState ? currentState : nextState,
        );
      }}
      onTrackingUpdated={state => {
        setTrackingReady(state === ViroTrackingStateConstants.TRACKING_NORMAL);
      }}>
      <ViroAmbientLight color="#ffffff" intensity={900} />

      <ViroNode position={targetPosition}>
        <ViroBox
          height={0.08}
          length={0.08}
          materials={['markerPanel']}
          position={[0, 0.1, 0]}
          scale={markerScale}
          width={0.08}
        />
        <ViroText
          height={0.4}
          outerStroke={{color: '#07111f', width: 2}}
          position={[0, 0.28, 0]}
          scale={markerScale}
          style={styles.title}
          text={target.name}
          width={2.8}
        />
        <ViroText
          height={0.3}
          outerStroke={{color: '#07111f', width: 1}}
          position={[0, 0.08, 0]}
          scale={markerScale}
          style={styles.subtitle}
          text={subLabel}
          width={3.2}
        />
      </ViroNode>
    </ViroARScene>
  );
}

function getRelativeWorldPosition(
  userLocation: LocationSnapshot,
  target: MapTarget,
): [number, number, number] {
  const metersPerLat = 111320;
  const metersPerLon =
    111320 * Math.cos((userLocation.latitude * Math.PI) / 180);
  const deltaNorth = (target.latitude - userLocation.latitude) * metersPerLat;
  const deltaEast = (target.longitude - userLocation.longitude) * metersPerLon;
  const deltaAltitude = target.altitude - userLocation.altitude;

  return [deltaEast, deltaAltitude, -deltaNorth];
}

function isTargetInView(
  cameraTransform: ViroCameraTransform,
  targetPosition: [number, number, number],
) {
  const cameraPosition = cameraTransform.position;
  const targetVector = normalize([
    targetPosition[0] - cameraPosition[0],
    targetPosition[1] - cameraPosition[1],
    targetPosition[2] - cameraPosition[2],
  ]);
  const forward = normalize(cameraTransform.forward);
  const dotProduct = dot(forward, targetVector);
  const recognitionThreshold = Math.cos((18 * Math.PI) / 180);

  return dotProduct >= recognitionThreshold;
}

function normalize(vector: [number, number, number]) {
  const magnitude = Math.sqrt(
    vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2],
  );

  if (magnitude === 0) {
    return [0, 0, 0] as [number, number, number];
  }

  return [
    vector[0] / magnitude,
    vector[1] / magnitude,
    vector[2] / magnitude,
  ] as [number, number, number];
}

function dot(
  left: [number, number, number],
  right: [number, number, number],
) {
  return left[0] * right[0] + left[1] * right[1] + left[2] * right[2];
}

const styles = {
  title: StyleSheet.create({
    base: {
      color: '#ffffff',
      fontFamily: 'HelveticaNeue',
      fontSize: 24,
      fontWeight: '700',
      textAlign: 'center',
    },
  }).base,
  subtitle: StyleSheet.create({
    base: {
      color: '#dbe362',
      fontFamily: 'HelveticaNeue',
      fontSize: 18,
      textAlign: 'center',
    },
  }).base,
};
