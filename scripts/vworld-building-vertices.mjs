import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const DEFAULT_ADDRESS = '경남 김해시 인제로230번길 50-17';
const SEARCH_URL = 'https://api.vworld.kr/req/search';
const WFS_URL = 'https://api.vworld.kr/req/wfs';

async function main() {
  const address = process.argv.slice(2).join(' ').trim() || DEFAULT_ADDRESS;
  const env = loadEnvFile(path.resolve(process.cwd(), '.env.local'));
  const apiKey = env.VWORLD_API_KEY || process.env.VWORLD_API_KEY;

  if (!apiKey) {
    throw new Error('VWORLD_API_KEY가 없습니다. .env.local 또는 환경변수에 설정하십시오.');
  }

  const searchResult = await geocodeRoadAddress(address, apiKey);
  const queryBuildingNo = extractBuildingNumber(searchResult.address.road) ?? extractBuildingNumber(address);
  const bbox = createWfsBbox(searchResult.point.y, searchResult.point.x, 0.00035);
  const features = await fetchBuildingFeatures(bbox, apiKey);

  if (features.length === 0) {
    throw new Error('주소 주변에서 도로명주소건물 폴리곤을 찾지 못했습니다.');
  }

  const selectedFeature = selectBuildingFeature(features, {
    roadName: extractRoadName(searchResult.address.road),
    buildingNo: queryBuildingNo,
    point: searchResult.point,
  });

  if (!selectedFeature) {
    throw new Error('대상 건물을 특정하지 못했습니다.');
  }

  const outerRing = getOuterRing(selectedFeature);

  const result = {
    queryAddress: address,
    resolvedRoadAddress: searchResult.address.road,
    parcelAddress: searchResult.address.parcel,
    geocodedPoint: {
      longitude: searchResult.point.x,
      latitude: searchResult.point.y,
    },
    building: {
      roadName: selectedFeature.properties.rd_nm,
      buildingNumber: selectedFeature.properties.buld_no,
      buildingManagementNumber: selectedFeature.properties.bd_mgt_sn,
      parcelCode: selectedFeature.properties.pnu,
      bbox: selectedFeature.bbox,
      outerRingVertices: outerRing.map(([longitude, latitude], index) => ({
        index,
        longitude,
        latitude,
      })),
    },
  };

  console.log(JSON.stringify(result, null, 2));
}

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }

  return Object.fromEntries(
    fs
      .readFileSync(filePath, 'utf8')
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(line => line && !line.startsWith('#') && line.includes('='))
      .map(line => {
        const separatorIndex = line.indexOf('=');
        const key = line.slice(0, separatorIndex).trim();
        const value = line.slice(separatorIndex + 1).trim();
        return [key, value];
      }),
  );
}

async function geocodeRoadAddress(address, apiKey) {
  const url = new URL(SEARCH_URL);
  url.search = new URLSearchParams({
    service: 'search',
    request: 'search',
    version: '2.0',
    format: 'json',
    errorformat: 'json',
    type: 'address',
    category: 'road',
    crs: 'EPSG:4326',
    size: '10',
    query: address,
    key: apiKey,
  }).toString();

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`검색 API 호출 실패: ${response.status}`);
  }

  const data = await response.json();
  const item = data?.response?.result?.items?.[0];

  if (data?.response?.status !== 'OK' || !item) {
    throw new Error(`검색 API 응답 이상: ${JSON.stringify(data)}`);
  }

  return {
    address: item.address,
    point: {
      x: Number(item.point.x),
      y: Number(item.point.y),
    },
  };
}

async function fetchBuildingFeatures(bbox, apiKey) {
  const url = new URL(WFS_URL);
  url.search = new URLSearchParams({
    SERVICE: 'WFS',
    REQUEST: 'GetFeature',
    VERSION: '1.1.0',
    TYPENAME: 'lt_c_spbd',
    SRSNAME: 'EPSG:4326',
    BBOX: bbox,
    MAXFEATURES: '50',
    OUTPUTFORMAT: 'application/json',
    key: apiKey,
  }).toString();

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`WFS API 호출 실패: ${response.status}`);
  }

  const data = await response.json();
  return data.features ?? [];
}

function createWfsBbox(latitude, longitude, delta) {
  const minLat = latitude - delta;
  const minLon = longitude - delta;
  const maxLat = latitude + delta;
  const maxLon = longitude + delta;

  return `${minLat},${minLon},${maxLat},${maxLon},EPSG:4326`;
}

function extractBuildingNumber(value) {
  const match = value.match(/(\d+(?:-\d+)?)(?:\s*\(|$)/);
  return match ? match[1] : null;
}

function extractRoadName(roadAddress) {
  const withoutSuffix = roadAddress.replace(/\s+\d+(?:-\d+)?(?:\s*\(.+\))?$/, '');
  const parts = withoutSuffix.split(/\s+/);
  return parts.at(-1) ?? withoutSuffix;
}

function selectBuildingFeature(features, criteria) {
  const roadMatched = features.filter(
    feature => feature.properties.rd_nm === criteria.roadName,
  );

  const exactNumberMatch = roadMatched.find(
    feature => feature.properties.buld_no === criteria.buildingNo,
  );

  if (exactNumberMatch) {
    return exactNumberMatch;
  }

  const pointContained = roadMatched.find(feature =>
    isPointInFeatureBBox(criteria.point, feature.bbox),
  );

  if (pointContained) {
    return pointContained;
  }

  return roadMatched[0] ?? features[0] ?? null;
}

function isPointInFeatureBBox(point, bbox) {
  if (!Array.isArray(bbox) || bbox.length !== 4) {
    return false;
  }

  const [minLon, minLat, maxLon, maxLat] = bbox;
  return (
    point.x >= minLon &&
    point.x <= maxLon &&
    point.y >= minLat &&
    point.y <= maxLat
  );
}

function getOuterRing(feature) {
  const coordinates = feature?.geometry?.coordinates;
  const outerRing = coordinates?.[0]?.[0];

  if (!Array.isArray(outerRing)) {
    throw new Error('건물 폴리곤 outer ring을 읽지 못했습니다.');
  }

  return outerRing;
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
