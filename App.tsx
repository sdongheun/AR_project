import React, {useEffect, useMemo, useState} from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import Geolocation from 'react-native-geolocation-service';
import {SafeAreaProvider, SafeAreaView} from 'react-native-safe-area-context';
import {
  isARSupportedOnDevice,
  requestRequiredPermissions,
  ViroARSceneNavigator,
} from '@reactvision/react-viro';
import {ARMapScene} from './src/ar/ARMapScene';
import {appConfig, demoTarget} from './src/config/appConfig';
import type {LocationSnapshot} from './src/types/location';

const initialArScene = ARMapScene as unknown as () => React.JSX.Element;
type RecognitionStatus = 'tracking' | 'success' | 'failure';

function App(): React.JSX.Element {
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="light-content" />
      <AppContent />
    </SafeAreaProvider>
  );
}

function AppContent() {
  const [arSupported, setArSupported] = useState<boolean | null>(null);
  const [isCheckingSupport, setIsCheckingSupport] = useState(true);
  const [isRequestingPermissions, setIsRequestingPermissions] = useState(false);
  const [permissions, setPermissions] = useState({
    camera: false,
    location: false,
  });
  const [location, setLocation] = useState<LocationSnapshot | null>(null);
  const [locationError, setLocationError] = useState<string | null>(null);
  const [isFetchingLocation, setIsFetchingLocation] = useState(false);
  const [isArActive, setIsArActive] = useState(false);
  const [recognitionStatus, setRecognitionStatus] =
    useState<RecognitionStatus>('tracking');

  useEffect(() => {
    bootstrapSupport().catch(() => {
      setArSupported(false);
      setIsCheckingSupport(false);
    });
  }, []);

  const distanceToDemoTarget = useMemo(() => {
    if (!location) {
      return null;
    }

    return getDistanceMeters(
      location.latitude,
      location.longitude,
      demoTarget.latitude,
      demoTarget.longitude,
    );
  }, [location]);

  async function bootstrapSupport() {
    try {
      const support = await isARSupportedOnDevice();
      setArSupported(support.isARSupported);
    } catch (error) {
      setArSupported(false);
      setLocationError(
        error instanceof Error ? error.message : 'AR 지원 상태를 확인하지 못했습니다.',
      );
    } finally {
      setIsCheckingSupport(false);
    }
  }

  async function requestPermissions() {
    setIsRequestingPermissions(true);

    try {
      const result = await requestRequiredPermissions(['camera', 'location']);
      const nextPermissions = {
        camera: Boolean(result.camera),
        location: Boolean(result.location),
      };

      setPermissions(nextPermissions);

      if (nextPermissions.location) {
        await refreshLocation();
      }

      if (!nextPermissions.camera || !nextPermissions.location) {
        Alert.alert(
          '권한 필요',
          'AR 카메라와 현재 위치를 쓰려면 카메라 및 위치 권한이 모두 필요합니다.',
        );
      }
    } catch (error) {
      Alert.alert(
        '권한 요청 실패',
        error instanceof Error ? error.message : '권한 요청 중 오류가 발생했습니다.',
      );
    } finally {
      setIsRequestingPermissions(false);
    }
  }

  async function refreshLocation() {
    setIsFetchingLocation(true);
    setLocationError(null);

    try {
      const snapshot = await getCurrentLocation();
      setLocation(snapshot);
    } catch (error) {
      setLocationError(
        error instanceof Error ? error.message : '현재 위치를 가져오지 못했습니다.',
      );
    } finally {
      setIsFetchingLocation(false);
    }
  }

  function launchAr() {
    if (!permissions.camera || !permissions.location) {
      Alert.alert('권한 필요', '먼저 카메라와 위치 권한을 허용해야 합니다.');
      return;
    }

    if (!arSupported) {
      Alert.alert(
        '실행 불가',
        '이 기기는 현재 ARKit/ARCore 기반 실행 조건을 충족하지 않습니다.',
      );
      return;
    }

    setRecognitionStatus('tracking');
    setIsArActive(true);
  }

  if (isArActive) {
    return (
      <View style={styles.container}>
        <ViroARSceneNavigator
          autofocus
          initialScene={{scene: initialArScene}}
          style={styles.arNavigator}
          viroAppProps={{
            onRecognitionStateChange: setRecognitionStatus,
            target: demoTarget,
            userLocation: location,
          }}
          worldAlignment="GravityAndHeading"
        />
        <SafeAreaView pointerEvents="box-none" style={styles.arOverlay}>
          <View style={styles.arOverlayHeader}>
            <View style={styles.arStatusBlock}>
              <Text style={styles.arOverlayTitle}>{demoTarget.name}</Text>
              <Text
                style={[
                  styles.arStatusBadge,
                  recognitionStatus === 'success'
                    ? styles.statusSuccess
                    : recognitionStatus === 'failure'
                      ? styles.statusFailure
                      : styles.statusTracking,
                ]}>
                {getRecognitionStatusLabel(recognitionStatus)}
              </Text>
            </View>
            <Pressable
              onPress={() => setIsArActive(false)}
              style={styles.exitButton}>
              <Text style={styles.exitButtonLabel}>AR 종료</Text>
            </Pressable>
          </View>
        </SafeAreaView>
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.content}>
        <View style={styles.hero}>
          <Text style={styles.kicker}>AR + React Native Bootstrap</Text>
          <Text style={styles.title}>AR Map MVP</Text>
          <Text style={styles.description}>
            카메라 기반 첫 화면, 위치/방향 센서 사용, VWorld 연동 준비 상태를 한 번에 점검하는
            초기 부트스트랩입니다.
          </Text>
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>현재 부트스트랩 상태</Text>
          <StatusRow
            label="AR 지원 확인"
            value={
              isCheckingSupport ? '확인 중' : arSupported ? '지원됨' : '지원되지 않음'
            }
          />
          <StatusRow
            label="카메라 권한"
            value={permissions.camera ? '허용됨' : '미허용'}
          />
          <StatusRow
            label="위치 권한"
            value={permissions.location ? '허용됨' : '미허용'}
          />
          <StatusRow
            label="VWorld 키 관리"
            value={appConfig.vworld.keySource}
          />
          <StatusRow label="타깃 플랫폼" value={appConfig.platformPriority} />
          <StatusRow label="AR 라이브러리" value={appConfig.arLibrary} />
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>시연 타깃</Text>
          <Text style={styles.targetName}>{demoTarget.name}</Text>
          <Text style={styles.targetMeta}>{demoTarget.categoryLabel}</Text>
          <Text style={styles.targetMeta}>{demoTarget.address}</Text>
          <Text style={styles.coordinates}>
            {demoTarget.latitude.toFixed(6)}, {demoTarget.longitude.toFixed(6)}
          </Text>
          {distanceToDemoTarget !== null ? (
            <Text style={styles.distance}>
              현재 위치 기준 약 {Math.round(distanceToDemoTarget)}m
            </Text>
          ) : null}
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>현재 위치</Text>
          {isFetchingLocation ? <ActivityIndicator color="#dbe362" /> : null}
          {location ? (
            <>
              <Text style={styles.coordinates}>
                {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
              </Text>
              <Text style={styles.targetMeta}>
                정확도 {Math.round(location.accuracy)}m · {location.capturedAt}
              </Text>
            </>
          ) : (
            <Text style={styles.helperText}>
              위치를 아직 읽지 않았습니다. 권한 허용 후 현재 위치를 새로고침하십시오.
            </Text>
          )}
          {locationError ? <Text style={styles.errorText}>{locationError}</Text> : null}
        </View>

        <View style={styles.actions}>
          <PrimaryButton
            label={isRequestingPermissions ? '권한 요청 중...' : '권한 요청'}
            onPress={() => {
              requestPermissions().catch(() => {});
            }}
          />
          <SecondaryButton
            label={isFetchingLocation ? '위치 갱신 중...' : '현재 위치 갱신'}
            onPress={() => {
              refreshLocation().catch(() => {});
            }}
          />
          <PrimaryButton label="AR 실행" onPress={launchAr} />
        </View>

        <View style={styles.noteCard}>
          <Text style={styles.noteTitle}>다음 구현 포인트</Text>
          <Text style={styles.noteText}>
            1. VWorld 3D 데이터 응답 구조를 확정하고 대상 좌표를 실제 API로 교체
          </Text>
          <Text style={styles.noteText}>
            2. 단일 건물 우선으로 GPS 좌표와 AR 마커 위치 보정
          </Text>
          <Text style={styles.noteText}>
            3. 이후 관광지/다중 타깃/길찾기 순으로 확장
          </Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

function PrimaryButton({
  label,
  onPress,
}: {
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.button, styles.primaryButton]}>
      <Text style={styles.primaryButtonLabel}>{label}</Text>
    </Pressable>
  );
}

function SecondaryButton({
  label,
  onPress,
}: {
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.button, styles.secondaryButton]}>
      <Text style={styles.secondaryButtonLabel}>{label}</Text>
    </Pressable>
  );
}

function StatusRow({label, value}: {label: string; value: string}) {
  return (
    <View style={styles.statusRow}>
      <Text style={styles.statusLabel}>{label}</Text>
      <Text style={styles.statusValue}>{value}</Text>
    </View>
  );
}

function getCurrentLocation(): Promise<LocationSnapshot> {
  return new Promise((resolve, reject) => {
    Geolocation.getCurrentPosition(
      position => {
        resolve({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
          altitude: position.coords.altitude ?? 0,
          capturedAt: new Date(position.timestamp).toLocaleTimeString(),
        });
      },
      error => {
        reject(new Error(error.message));
      },
      {
        enableHighAccuracy: true,
        timeout: 15000,
        maximumAge: 5000,
      },
    );
  });
}

function getDistanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
) {
  const earthRadiusMeters = 6371000;
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const latitudeA = toRadians(lat1);
  const latitudeB = toRadians(lat2);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.sin(dLon / 2) *
      Math.sin(dLon / 2) *
      Math.cos(latitudeA) *
      Math.cos(latitudeB);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

function toRadians(value: number) {
  return (value * Math.PI) / 180;
}

function getRecognitionStatusLabel(status: RecognitionStatus) {
  switch (status) {
    case 'success':
      return '인식 완료';
    case 'failure':
      return '인식 실패';
    default:
      return '트래킹 중';
  }
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#07111f',
  },
  content: {
    padding: 20,
    paddingBottom: 48,
    gap: 16,
  },
  hero: {
    backgroundColor: '#12243c',
    borderRadius: 24,
    padding: 24,
    gap: 10,
  },
  kicker: {
    color: '#dbe362',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  title: {
    color: '#f4f7fb',
    fontSize: 34,
    fontWeight: '800',
  },
  description: {
    color: '#c3d0e2',
    fontSize: 15,
    lineHeight: 22,
  },
  card: {
    backgroundColor: '#0d1a2c',
    borderColor: '#1c3557',
    borderRadius: 20,
    borderWidth: 1,
    padding: 18,
    gap: 10,
  },
  cardTitle: {
    color: '#f4f7fb',
    fontSize: 18,
    fontWeight: '700',
  },
  statusRow: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  statusLabel: {
    color: '#9db1c8',
    fontSize: 14,
  },
  statusValue: {
    color: '#f4f7fb',
    fontSize: 14,
    fontWeight: '600',
  },
  targetName: {
    color: '#f4f7fb',
    fontSize: 24,
    fontWeight: '800',
  },
  targetMeta: {
    color: '#b5c4d8',
    fontSize: 14,
    lineHeight: 20,
  },
  coordinates: {
    color: '#dbe362',
    fontSize: 14,
    fontWeight: '700',
  },
  distance: {
    color: '#f4f7fb',
    fontSize: 14,
    fontWeight: '600',
  },
  helperText: {
    color: '#9db1c8',
    fontSize: 14,
    lineHeight: 20,
  },
  errorText: {
    color: '#ff8b8b',
    fontSize: 13,
    lineHeight: 18,
  },
  actions: {
    gap: 10,
  },
  button: {
    alignItems: 'center',
    borderRadius: 16,
    paddingHorizontal: 18,
    paddingVertical: 16,
  },
  primaryButton: {
    backgroundColor: '#dbe362',
  },
  primaryButtonLabel: {
    color: '#07111f',
    fontSize: 15,
    fontWeight: '800',
  },
  secondaryButton: {
    backgroundColor: '#17304d',
    borderColor: '#2d4c70',
    borderWidth: 1,
  },
  secondaryButtonLabel: {
    color: '#f4f7fb',
    fontSize: 15,
    fontWeight: '700',
  },
  noteCard: {
    backgroundColor: '#091423',
    borderRadius: 20,
    padding: 18,
    gap: 8,
  },
  noteTitle: {
    color: '#f4f7fb',
    fontSize: 17,
    fontWeight: '700',
  },
  noteText: {
    color: '#c3d0e2',
    fontSize: 14,
    lineHeight: 20,
  },
  arNavigator: {
    flex: 1,
  },
  arOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'space-between',
    padding: 16,
  },
  arOverlayHeader: {
    alignItems: 'flex-start',
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  arStatusBlock: {
    gap: 8,
  },
  arOverlayTitle: {
    backgroundColor: 'rgba(7, 17, 31, 0.7)',
    borderRadius: 12,
    color: '#f4f7fb',
    overflow: 'hidden',
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 15,
    fontWeight: '700',
  },
  arStatusBadge: {
    alignSelf: 'flex-start',
    borderRadius: 999,
    color: '#07111f',
    fontSize: 13,
    fontWeight: '800',
    overflow: 'hidden',
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  statusSuccess: {
    backgroundColor: '#dbe362',
  },
  statusFailure: {
    backgroundColor: '#ff8b8b',
  },
  statusTracking: {
    backgroundColor: '#9db1c8',
  },
  exitButton: {
    backgroundColor: 'rgba(7, 17, 31, 0.78)',
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  exitButtonLabel: {
    color: '#f4f7fb',
    fontSize: 14,
    fontWeight: '700',
  },
});

export default App;
