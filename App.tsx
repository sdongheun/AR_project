import React, {useEffect, useMemo, useRef, useState} from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import Geolocation from 'react-native-geolocation-service';
import {SafeAreaProvider, SafeAreaView} from 'react-native-safe-area-context';
// import {
//   isARSupportedOnDevice,
//   requestRequiredPermissions,
//   ViroARSceneNavigator,
// } from '@reactvision/react-viro';

// [VPS 준비] Viro 의존성 제거 및 Mock 처리 (향후 Native Module로 대체)
const isARSupportedOnDevice = async () => ({ isARSupported: true });
const requestRequiredPermissions = async (_permissions: string[]) => ({
  camera: true,
  location: true,
});
import Config from 'react-native-config';
import {VPSARView} from './src/ar/VPSARView';
import type {VPSTrackingEvent} from './src/ar/VPSARView';
import {appConfig, demoTarget} from './src/config/appConfig';
import {
  selectLookedAtBuilding,
  type BuildingRecognitionCandidate,
  type BuildingRecognitionResult,
} from './src/services/buildingRecognition';
import {
  type GisBuildingInfoResult,
  VWorldApiError,
  VWorldBuildingService,
  type VWorldDebugInfo,
} from './src/services/vworldBuildingService';
import type {LocationSnapshot} from './src/types/location';
import type {MapTarget} from './src/types/target';

// const initialArScene = ARMapScene as unknown as () => React.JSX.Element;
type RecognitionStatus = 'tracking' | 'success' | 'failure';
type ARRecognitionDebugState = {
  candidateCount: number;
  detail: string;
  headingDegrees: number | null;
  resultType: BuildingRecognitionResult['type'] | 'waiting';
  selectedName: string | null;
};
type TargetFormState = {
  address: string;
  altitude: string;
  latitude: string;
  longitude: string;
  name: string;
};
type BuildingBoundaryCheckState = {
  buildingNumber: string;
  checkedAddress: string;
  isInside: boolean;
  resolvedRoadAddress: string;
  vertexCount: number;
} | null;
type BuildingBoundaryDebugState = VWorldDebugInfo | null;
type GisBuildingInfoState = GisBuildingInfoResult | null;

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
  const [arRecognitionDebug, setArRecognitionDebug] =
    useState<ARRecognitionDebugState>({
      candidateCount: 0,
      detail: 'VPS 트래킹과 카메라 방향을 기다리는 중',
      headingDegrees: null,
      resultType: 'waiting',
      selectedName: null,
    });
  const [isCheckingBoundary, setIsCheckingBoundary] = useState(false);
  const [boundaryCheckError, setBoundaryCheckError] = useState<string | null>(null);
  const [boundaryCheckResult, setBoundaryCheckResult] =
    useState<BuildingBoundaryCheckState>(null);
  const [boundaryCheckDebug, setBoundaryCheckDebug] =
    useState<BuildingBoundaryDebugState>(null);
  const [gisBuildingInfo, setGisBuildingInfo] =
    useState<GisBuildingInfoState>(null);
  const [gisBuildingError, setGisBuildingError] = useState<string | null>(null);
  const [gisBuildingDebug, setGisBuildingDebug] =
    useState<BuildingBoundaryDebugState>(null);
  const [isFetchingGisBuilding, setIsFetchingGisBuilding] = useState(false);
  const [activeTarget, setActiveTarget] = useState<MapTarget>(demoTarget);
  const buildingCandidatesRef = useRef<BuildingRecognitionCandidate[]>([]);
  const isFetchingRecognitionCandidatesRef = useRef(false);
  const lastCandidateFetchRef = useRef<{
    latitude: number;
    longitude: number;
    timestampMs: number;
  } | null>(null);
  const lastRecognitionRunMsRef = useRef(0);
  const lastVpsLocationStateMsRef = useRef(0);
  const [targetForm, setTargetForm] = useState<TargetFormState>({
    address: demoTarget.address,
    altitude: String(demoTarget.altitude),
    latitude: String(demoTarget.latitude),
    longitude: String(demoTarget.longitude),
    name: demoTarget.name,
  });

  useEffect(() => {
    bootstrapSupport().catch(() => {
      setArSupported(false);
      setIsCheckingSupport(false);
    });
  }, []);

  const distanceToActiveTarget = useMemo(() => {
    if (!location) {
      return null;
    }

    return getDistanceMeters(
      location.latitude,
      location.longitude,
      activeTarget.latitude,
      activeTarget.longitude,
    );
  }, [activeTarget.latitude, activeTarget.longitude, location]);

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

  function applyTargetInput() {
    const latitude = Number(targetForm.latitude);
    const longitude = Number(targetForm.longitude);
    const altitude = Number(targetForm.altitude || '0');

    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      Alert.alert('입력 오류', '위도와 경도는 숫자로 입력해야 합니다.');
      return;
    }

    if (!targetForm.address.trim()) {
      Alert.alert('입력 오류', '건물 주소를 입력해야 합니다.');
      return;
    }

    setActiveTarget({
      id: `custom-${Date.now()}`,
      name: targetForm.name.trim() || targetForm.address.trim(),
      category: 'building',
      categoryLabel: '건물',
      address: targetForm.address.trim(),
      latitude,
      longitude,
      altitude: Number.isFinite(altitude) ? altitude : 0,
    });
  }

  async function checkCurrentLocationAgainstBuilding() {
    if (!permissions.location) {
      Alert.alert('권한 필요', '먼저 위치 권한을 허용해야 합니다.');
      return;
    }

    if (!targetForm.address.trim()) {
      Alert.alert('입력 오류', '건물 주소를 입력해야 합니다.');
      return;
    }

    if (!Config.VWORLD_API_KEY) {
      Alert.alert(
        '설정 오류',
        '브이월드 API 키를 앱에서 읽지 못했습니다. 네이티브 재빌드가 필요할 수 있습니다.',
      );
      return;
    }

    setIsCheckingBoundary(true);
    setBoundaryCheckError(null);
    setBoundaryCheckDebug(null);

    try {
      const currentLocation = location ?? (await getCurrentLocation());
      setLocation(currentLocation);

      const service = new VWorldBuildingService(Config.VWORLD_API_KEY);
      const result = await service.getBuildingContainmentForPoint(
        targetForm.address.trim(),
        {
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude,
        },
      );

      const nextTarget: MapTarget = {
        id: `resolved-${Date.now()}`,
        name: targetForm.name.trim() || result.buildingResult.queryAddress,
        category: 'building',
        categoryLabel: '건물',
        address: result.buildingResult.resolvedRoadAddress,
        latitude: result.buildingResult.geocodedPoint.latitude,
        longitude: result.buildingResult.geocodedPoint.longitude,
        altitude: Number(targetForm.altitude || '0') || 0,
      };

      setTargetForm(currentState => ({
        ...currentState,
        address: result.buildingResult.resolvedRoadAddress,
        latitude: String(result.buildingResult.geocodedPoint.latitude),
        longitude: String(result.buildingResult.geocodedPoint.longitude),
        name: currentState.name.trim() || nextTarget.name,
      }));
      setActiveTarget(nextTarget);
      setBoundaryCheckResult({
        buildingNumber: result.buildingResult.building.buildingNumber,
        checkedAddress: result.buildingResult.queryAddress,
        isInside: result.isInside,
        resolvedRoadAddress: result.buildingResult.resolvedRoadAddress,
        vertexCount: result.buildingResult.building.outerRingVertices.length,
      });
    } catch (error) {
      setBoundaryCheckResult(null);
      if (error instanceof VWorldApiError) {
        setBoundaryCheckDebug(error.debugInfo);
        setBoundaryCheckError(error.message);
      } else {
        setBoundaryCheckError(
          error instanceof Error ? error.message : '건물 외벽 조회에 실패했습니다.',
        );
      }
    } finally {
      setIsCheckingBoundary(false);
    }
  }

  async function fetchGisBuildingInfo() {
    if (!targetForm.address.trim()) {
      Alert.alert('입력 오류', '건물 주소를 입력해야 합니다.');
      return;
    }

    if (!Config.VWORLD_API_KEY) {
      Alert.alert(
        '설정 오류',
        '브이월드 API 키를 앱에서 읽지 못했습니다. 네이티브 재빌드가 필요할 수 있습니다.',
      );
      return;
    }

    setIsFetchingGisBuilding(true);
    setGisBuildingError(null);
    setGisBuildingDebug(null);

    try {
      const service = new VWorldBuildingService(Config.VWORLD_API_KEY);
      const result = await service.getIntegratedBuildingInfo(
        targetForm.address.trim(),
      );

      setGisBuildingInfo(result);
      setTargetForm(currentState => ({
        ...currentState,
        address: result.resolvedRoadAddress,
        latitude: String(result.geocodedPoint.latitude),
        longitude: String(result.geocodedPoint.longitude),
        name:
          currentState.name.trim() ||
          result.building.buildingName ||
          result.resolvedRoadAddress,
      }));
      setActiveTarget({
        id: `gis-${Date.now()}`,
        name:
          targetForm.name.trim() ||
          result.building.buildingName ||
          result.resolvedRoadAddress,
        category: 'building',
        categoryLabel: '건물',
        address: result.resolvedRoadAddress,
        latitude: result.geocodedPoint.latitude,
        longitude: result.geocodedPoint.longitude,
        altitude: Number(targetForm.altitude || '0') || 0,
      });
    } catch (error) {
      setGisBuildingInfo(null);
      if (error instanceof VWorldApiError) {
        setGisBuildingDebug(error.debugInfo);
        setGisBuildingError(error.message);
      } else {
        setGisBuildingError(
          error instanceof Error
            ? error.message
            : 'GIS건물통합정보 조회에 실패했습니다.',
        );
      }
    } finally {
      setIsFetchingGisBuilding(false);
    }
  }

  async function handleVpsTrackingEvent(event: VPSTrackingEvent) {
    if (event.status === 'engine_initialized') {
      setRecognitionStatus('tracking');
      setArRecognitionDebug(current => ({
        ...current,
        detail: 'VPS 엔진 초기화 완료, 위치 정밀화 중',
        resultType: 'waiting',
      }));
      return;
    }

    if (event.status !== 'tracking_success') {
      setRecognitionStatus('tracking');
      return;
    }

    const latitude = Number(event.latitude);
    const longitude = Number(event.longitude);
    const altitude = Number(event.altitude ?? 0);
    const horizontalAccuracy = Number(event.horizontalAccuracy ?? 999);
    const headingDegrees = getHeadingDegreesFromVpsEvent(event);
    const nowMs = Date.now();

    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      setRecognitionStatus('failure');
      setArRecognitionDebug(current => ({
        ...current,
        detail: 'VPS 위치 좌표를 아직 받지 못했습니다.',
        resultType: 'none',
      }));
      return;
    }

    if (nowMs - lastVpsLocationStateMsRef.current >= 1000) {
      lastVpsLocationStateMsRef.current = nowMs;
      const vpsLocation: LocationSnapshot = {
        accuracy: horizontalAccuracy,
        altitude,
        capturedAt: new Date(nowMs).toLocaleTimeString(),
        latitude,
        longitude,
      };
      setLocation(vpsLocation);
    }

    if (Config.VWORLD_API_KEY) {
      refreshRecognitionCandidatesIfNeeded({
        latitude,
        longitude,
        timestampMs: nowMs,
      }).catch(error => {
        setArRecognitionDebug(current => ({
          ...current,
          detail:
            error instanceof Error
              ? error.message
              : '주변 건물 후보 조회에 실패했습니다.',
        }));
      });
    }

    if (!Number.isFinite(headingDegrees)) {
      setRecognitionStatus('tracking');
      setArRecognitionDebug(current => ({
        ...current,
        candidateCount: buildingCandidatesRef.current.length,
        detail: `카메라 heading 값을 기다리는 중 · event keys: ${Object.keys(
          event,
        ).join(', ')}`,
        headingDegrees: null,
        resultType: 'waiting',
      }));
      return;
    }

    if (nowMs - lastRecognitionRunMsRef.current < 200) {
      return;
    }
    lastRecognitionRunMsRef.current = nowMs;

    const result = selectLookedAtBuilding(
      {
        altitude,
        horizontalAccuracyMeters: horizontalAccuracy,
        latitude,
        longitude,
        source: 'vps',
        timestampMs: nowMs,
        verticalAccuracyMeters: Number(event.verticalAccuracy ?? 0),
      },
      {
        headingDegrees,
        orientationAccuracyDegrees: Number(event.orientationYawAccuracy ?? 0),
        timestampMs: nowMs,
      },
      buildingCandidatesRef.current,
      {nowMs},
    );

    applyRecognitionResult(result, headingDegrees);
  }

  async function refreshRecognitionCandidatesIfNeeded(params: {
    latitude: number;
    longitude: number;
    timestampMs: number;
  }) {
    if (isFetchingRecognitionCandidatesRef.current) {
      return;
    }

    const lastFetch = lastCandidateFetchRef.current;
    if (lastFetch) {
      const movedMeters = getDistanceMeters(
        lastFetch.latitude,
        lastFetch.longitude,
        params.latitude,
        params.longitude,
      );
      const elapsedMs = params.timestampMs - lastFetch.timestampMs;

      if (movedMeters < 30 && elapsedMs < 10000) {
        return;
      }
    }

    isFetchingRecognitionCandidatesRef.current = true;

    try {
      const apiKey = Config.VWORLD_API_KEY;
      if (!apiKey) {
        return;
      }

      const service = new VWorldBuildingService(apiKey);
      const candidates =
        await service.getBuildingRecognitionCandidatesNearPoint({
          latitude: params.latitude,
          longitude: params.longitude,
        });

      buildingCandidatesRef.current = candidates;
      lastCandidateFetchRef.current = params;
      setArRecognitionDebug(current => ({
        ...current,
        candidateCount: candidates.length,
        detail:
          candidates.length > 0
            ? `주변 건물 후보 ${candidates.length}개 준비`
            : '주변 건물 후보를 찾지 못했습니다.',
      }));
    } finally {
      isFetchingRecognitionCandidatesRef.current = false;
    }
  }

  function applyRecognitionResult(
    result: BuildingRecognitionResult,
    headingDegrees: number,
  ) {
    if (result.type === 'recognized') {
      const isVisible =
        result.confidence === 'high' || result.confidence === 'medium';

      setRecognitionStatus(isVisible ? 'success' : 'failure');
      setArRecognitionDebug({
        candidateCount: result.debug.candidateCount,
        detail: `${result.confidence} · 거리 ${Math.round(
          result.distanceMeters,
        )}m · 방향오차 ${Math.round(result.angleDeltaDegrees)}도`,
        headingDegrees,
        resultType: 'recognized',
        selectedName: result.building.name,
      });
      setActiveTarget(current => ({
        ...current,
        id: result.building.id,
        name: result.building.name,
      }));
      return;
    }

    if (result.type === 'ambiguous') {
      setRecognitionStatus('failure');
      setArRecognitionDebug({
        candidateCount: result.debug.candidateCount,
        detail: `상위 후보가 비슷합니다: ${result.candidates
          .map(candidate => candidate.building.name)
          .join(', ')}`,
        headingDegrees,
        resultType: 'ambiguous',
        selectedName: null,
      });
      return;
    }

    setRecognitionStatus('failure');
    setArRecognitionDebug({
      candidateCount: result.debug.candidateCount,
      detail: result.reason,
      headingDegrees,
      resultType: 'none',
      selectedName: null,
    });
  }

  function getHeadingDegreesFromVpsEvent(event: VPSTrackingEvent) {
    const candidates = [
      event.headingDegrees,
      event.cameraHeadingDegrees,
      event.heading,
    ];

    for (const candidate of candidates) {
      const value = Number(candidate);

      if (Number.isFinite(value)) {
        return value;
      }
    }

    return Number.NaN;
  }

  function updateTargetForm<Key extends keyof TargetFormState>(
    key: Key,
    value: TargetFormState[Key],
  ) {
    setTargetForm(currentState => ({
      ...currentState,
      [key]: value,
    }));
  }

  if (isArActive) {
    return (
      <View style={styles.container}>
        {/* <ViroARSceneNavigator
          autofocus
          initialScene={{scene: initialArScene}}
          style={styles.arNavigator}
          viroAppProps={{
            onRecognitionStateChange: setRecognitionStatus,
            target: activeTarget,
            userLocation: location,
          }}
          worldAlignment="GravityAndHeading"
        /> */}
        
        {/* 네이티브 VPS AR 뷰 브릿지 컴포넌트 호출 */}
        <VPSARView
          style={styles.arNavigator}
          apiKey={Config.GOOGLE_VPS_API_KEY} // .env의 구글 API 키를 네이티브로 전달!
          targetLatitude={activeTarget.latitude}
          targetLongitude={activeTarget.longitude}
          targetAltitude={activeTarget.altitude}
          onTrackingStatusChange={event => {
            handleVpsTrackingEvent(event.nativeEvent).catch(error => {
              setRecognitionStatus('failure');
              setArRecognitionDebug(current => ({
                ...current,
                detail:
                  error instanceof Error
                    ? error.message
                    : 'AR 건물 인식 처리 중 오류가 발생했습니다.',
                resultType: 'none',
              }));
            });
          }}
        />
        <SafeAreaView pointerEvents="box-none" style={styles.arOverlay}>
          <View style={styles.arOverlayHeader}>
            <View style={styles.arStatusBlock}>
              <Text style={styles.arOverlayTitle}>
                {arRecognitionDebug.selectedName ?? activeTarget.name}
              </Text>
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
              <Text style={styles.arDebugText}>
                후보 {arRecognitionDebug.candidateCount}개
                {arRecognitionDebug.headingDegrees !== null
                  ? ` · heading ${Math.round(arRecognitionDebug.headingDegrees)}도`
                  : ''}
              </Text>
              <Text style={styles.arDebugText}>
                {arRecognitionDebug.detail}
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
          <Text style={styles.cardTitle}>타깃 입력</Text>
          <InputField
            label="건물명"
            onChangeText={value => updateTargetForm('name', value)}
            placeholder="예: 김해 인제로230번길 50-17"
            value={targetForm.name}
          />
          <InputField
            label="건물 주소"
            onChangeText={value => updateTargetForm('address', value)}
            placeholder="예: 경남 김해시 인제로230번길 50-17"
            value={targetForm.address}
          />
          <View style={styles.inlineInputs}>
            <InputField
              keyboardType="decimal-pad"
              label="위도"
              onChangeText={value => updateTargetForm('latitude', value)}
              placeholder="35.247217005"
              value={targetForm.latitude}
            />
            <InputField
              keyboardType="decimal-pad"
              label="경도"
              onChangeText={value => updateTargetForm('longitude', value)}
              placeholder="128.906748565"
              value={targetForm.longitude}
            />
          </View>
          <InputField
            keyboardType="decimal-pad"
            label="고도"
            onChangeText={value => updateTargetForm('altitude', value)}
            placeholder="0"
            value={targetForm.altitude}
          />
          <PrimaryButton
            label={isCheckingBoundary ? '건물 외벽 조회 중...' : '주소로 외벽 조회 + 내 위치 판정'}
            onPress={() => {
              checkCurrentLocationAgainstBuilding().catch(() => {});
            }}
          />
          <PrimaryButton
            label={
              isFetchingGisBuilding
                ? 'GIS건물통합정보 조회 중...'
                : 'GIS건물통합정보 조회'
            }
            onPress={() => {
              fetchGisBuildingInfo().catch(() => {});
            }}
          />
          <SecondaryButton label="입력값 적용" onPress={applyTargetInput} />
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
          <Text style={styles.targetName}>{activeTarget.name}</Text>
          <Text style={styles.targetMeta}>{activeTarget.categoryLabel}</Text>
          <Text style={styles.targetMeta}>{activeTarget.address}</Text>
          <Text style={styles.coordinates}>
            {activeTarget.latitude.toFixed(6)}, {activeTarget.longitude.toFixed(6)}
          </Text>
          <Text style={styles.targetMeta}>고도 {activeTarget.altitude}m</Text>
          {distanceToActiveTarget !== null ? (
            <Text style={styles.distance}>
              현재 위치 기준 약 {Math.round(distanceToActiveTarget)}m
            </Text>
          ) : null}
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>현재 위치</Text>
          {isFetchingLocation ? <ActivityIndicator color="#dbe362" /> : null}
          {location ? (
            <>
              <Text style={styles.coordinates}>
                위경도: {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
              </Text>
              <Text style={styles.coordinates}>
                지면 높이(추정): 해발 {Math.round(location.altitude - 1.5)}m
              </Text>
              <Text style={styles.targetMeta}>
                기기 고도: {Math.round(location.altitude)}m · 정확도 {Math.round(location.accuracy)}m · {location.capturedAt}
              </Text>
            </>
          ) : (
            <Text style={styles.helperText}>
              위치를 아직 읽지 않았습니다. 권한 허용 후 현재 위치를 새로고침하십시오.
            </Text>
          )}
          {locationError ? <Text style={styles.errorText}>{locationError}</Text> : null}
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>건물 바운더리 판정</Text>
          {isCheckingBoundary ? <ActivityIndicator color="#dbe362" /> : null}
          {boundaryCheckResult ? (
            <>
              <Text style={styles.targetMeta}>
                조회 주소: {boundaryCheckResult.checkedAddress}
              </Text>
              <Text style={styles.targetMeta}>
                해석 주소: {boundaryCheckResult.resolvedRoadAddress}
              </Text>
              <Text style={styles.targetMeta}>
                건물 번호: {boundaryCheckResult.buildingNumber} · 꼭짓점 수{' '}
                {boundaryCheckResult.vertexCount}
              </Text>
              <Text
                style={[
                  styles.boundaryResult,
                  boundaryCheckResult.isInside
                    ? styles.boundaryTrue
                    : styles.boundaryFalse,
                ]}>
                {String(boundaryCheckResult.isInside)}
              </Text>
            </>
          ) : (
            <Text style={styles.helperText}>
              주소 입력 후 `주소로 외벽 조회 + 내 위치 판정` 버튼을 누르면 여기에서
              true/false를 확인할 수 있습니다.
            </Text>
          )}
          {boundaryCheckError ? (
            <Text style={styles.errorText}>{boundaryCheckError}</Text>
          ) : null}
          {boundaryCheckDebug ? (
            <View style={styles.debugCard}>
              <Text style={styles.debugTitle}>API 디버그 정보</Text>
              <Text style={styles.debugText}>
                엔드포인트: {boundaryCheckDebug.endpointName}
              </Text>
              {boundaryCheckDebug.status !== undefined ? (
                <Text style={styles.debugText}>
                  상태코드: {boundaryCheckDebug.status}
                </Text>
              ) : null}
              <Text style={styles.debugText}>
                요청 URL: {boundaryCheckDebug.requestUrl}
              </Text>
              <Text style={styles.debugText}>
                응답 본문: {truncateDebugText(boundaryCheckDebug.responseBody)}
              </Text>
            </View>
          ) : null}
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>GIS 건물통합정보</Text>
          {isFetchingGisBuilding ? <ActivityIndicator color="#dbe362" /> : null}
          {gisBuildingInfo ? (
            <>
              <Text style={styles.targetMeta}>
                조회 주소: {gisBuildingInfo.queryAddress}
              </Text>
              <Text style={styles.targetMeta}>
                해석 주소: {gisBuildingInfo.resolvedRoadAddress}
              </Text>
              <Text style={styles.targetMeta}>
                지번 주소: {gisBuildingInfo.parcelAddress}
              </Text>
              <Text style={styles.targetMeta}>
                높이: {gisBuildingInfo.building.heightMeters}m · 지상{' '}
                {gisBuildingInfo.building.aboveGroundFloorCount}층 · 지하{' '}
                {gisBuildingInfo.building.undergroundFloorCount}층
              </Text>
              <Text style={styles.targetMeta}>
                GIS ID: {gisBuildingInfo.building.gisBuildingId}
              </Text>
              <Text style={styles.targetMeta}>
                PNU: {gisBuildingInfo.building.parcelCode}
              </Text>
              <Text style={styles.targetMeta}>
                좌표 기준점: {gisBuildingInfo.geocodedPoint.latitude.toFixed(6)},{' '}
                {gisBuildingInfo.geocodedPoint.longitude.toFixed(6)}
              </Text>
              <Text style={styles.debugTitle}>폴리곤 좌표</Text>
              <Text style={styles.codeBlock}>
                {JSON.stringify(
                  gisBuildingInfo.building.polygonVertices.map(vertex => [
                    vertex.longitude,
                    vertex.latitude,
                  ]),
                  null,
                  2,
                )}
              </Text>
            </>
          ) : (
            <Text style={styles.helperText}>
              주소 입력 후 `GIS건물통합정보 조회` 버튼을 누르면 높이와 폴리곤 좌표가
              여기 표시됩니다.
            </Text>
          )}
          {gisBuildingError ? (
            <Text style={styles.errorText}>{gisBuildingError}</Text>
          ) : null}
          {gisBuildingDebug ? (
            <View style={styles.debugCard}>
              <Text style={styles.debugTitle}>API 디버그 정보</Text>
              <Text style={styles.debugText}>
                엔드포인트: {gisBuildingDebug.endpointName}
              </Text>
              {gisBuildingDebug.status !== undefined ? (
                <Text style={styles.debugText}>
                  상태코드: {gisBuildingDebug.status}
                </Text>
              ) : null}
              <Text style={styles.debugText}>
                요청 URL: {gisBuildingDebug.requestUrl}
              </Text>
              <Text style={styles.debugText}>
                응답 본문: {truncateDebugText(gisBuildingDebug.responseBody)}
              </Text>
            </View>
          ) : null}
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

function InputField({
  keyboardType,
  label,
  onChangeText,
  placeholder,
  value,
}: {
  keyboardType?: 'default' | 'decimal-pad';
  label: string;
  onChangeText: (value: string) => void;
  placeholder: string;
  value: string;
}) {
  return (
    <View style={styles.inputGroup}>
      <Text style={styles.inputLabel}>{label}</Text>
      <TextInput
        keyboardType={keyboardType}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor="#6f849d"
        style={styles.input}
        value={value}
      />
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

function truncateDebugText(value?: string) {
  if (!value) {
    return '없음';
  }

  return value.length > 800 ? `${value.slice(0, 800)}...` : value;
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
  inlineInputs: {
    flexDirection: 'row',
    gap: 12,
  },
  inputGroup: {
    flex: 1,
    gap: 6,
  },
  inputLabel: {
    color: '#b5c4d8',
    fontSize: 13,
    fontWeight: '600',
  },
  input: {
    backgroundColor: '#091423',
    borderColor: '#27405f',
    borderRadius: 14,
    borderWidth: 1,
    color: '#f4f7fb',
    fontSize: 15,
    paddingHorizontal: 14,
    paddingVertical: 12,
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
  boundaryResult: {
    alignSelf: 'flex-start',
    borderRadius: 999,
    color: '#07111f',
    fontSize: 16,
    fontWeight: '800',
    marginTop: 4,
    overflow: 'hidden',
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  boundaryTrue: {
    backgroundColor: '#dbe362',
  },
  boundaryFalse: {
    backgroundColor: '#ff8b8b',
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
  debugCard: {
    backgroundColor: '#091423',
    borderColor: '#27405f',
    borderRadius: 14,
    borderWidth: 1,
    gap: 6,
    marginTop: 8,
    padding: 12,
  },
  debugTitle: {
    color: '#f4f7fb',
    fontSize: 13,
    fontWeight: '700',
  },
  debugText: {
    color: '#b5c4d8',
    fontSize: 12,
    lineHeight: 18,
  },
  codeBlock: {
    backgroundColor: '#091423',
    borderColor: '#27405f',
    borderRadius: 14,
    borderWidth: 1,
    color: '#dbe362',
    fontSize: 12,
    lineHeight: 18,
    padding: 12,
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
  arDebugText: {
    backgroundColor: 'rgba(7, 17, 31, 0.64)',
    borderRadius: 8,
    color: '#dbe7f4',
    fontSize: 12,
    lineHeight: 17,
    maxWidth: 280,
    overflow: 'hidden',
    paddingHorizontal: 10,
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
