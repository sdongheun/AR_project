import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const DEFAULT_ADDRESS = '경남 김해시 인제로230번길 50-17';
const SEARCH_URL = 'https://api.vworld.kr/req/search';
const WFS_URL = 'https://api.vworld.kr/req/wfs';

type EnvMap = Record<string, string>;

type AddressPoint = {
  x: number;
  y: number;
};

type AddressPayload = {
  parcel: string;
  road: string;
};

type SearchResult = {
  address: AddressPayload;
  point: AddressPoint;
};

type BuildingFeatureProperties = {
  bd_mgt_sn: string;
  buld_no: string;
  pnu: string;
  rd_nm: string;
};

type BuildingFeature = {
  bbox: number[];
  geometry?: {
    coordinates?: number[][][][];
  };
  properties: BuildingFeatureProperties;
};

type BuildingSelectionCriteria = {
  buildingNo: string | null;
  point: AddressPoint;
  roadName: string;
};

type BuildingVerticesResult = {
  building: {
    bbox: number[];
    buildingManagementNumber: string;
    buildingNumber: string;
    outerRingVertices: Array<{
      index: number;
      latitude: number;
      longitude: number;
    }>;
    parcelCode: string;
    roadName: string;
  };
  geocodedPoint: {
    latitude: number;
    longitude: number;
  };
  parcelAddress: string;
  queryAddress: string;
  resolvedRoadAddress: string;
};

class EnvFileReader {
  public read(filePath: string): EnvMap {
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
}

class VWorldApiClient {
  public async geocodeRoadAddress(
    address: string,
    apiKey: string,
  ): Promise<SearchResult> {
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
      address: {
        parcel: String(item.address.parcel),
        road: String(item.address.road),
      },
      point: {
        x: Number(item.point.x),
        y: Number(item.point.y),
      },
    };
  }

  public async fetchBuildingFeatures(
    bbox: string,
    apiKey: string,
  ): Promise<BuildingFeature[]> {
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
    return (data.features ?? []) as BuildingFeature[];
  }
}

class BuildingFeatureSelector {
  public select(
    features: BuildingFeature[],
    criteria: BuildingSelectionCriteria,
  ): BuildingFeature | null {
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
      this.isPointInFeatureBBox(criteria.point, feature.bbox),
    );

    if (pointContained) {
      return pointContained;
    }

    return roadMatched[0] ?? features[0] ?? null;
  }

  private isPointInFeatureBBox(point: AddressPoint, bbox: number[]) {
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
}

class CoordinateFormatter {
  public createWfsBbox(latitude: number, longitude: number, delta: number) {
    const minLat = latitude - delta;
    const minLon = longitude - delta;
    const maxLat = latitude + delta;
    const maxLon = longitude + delta;

    return `${minLat},${minLon},${maxLat},${maxLon},EPSG:4326`;
  }

  public getOuterRing(feature: BuildingFeature): number[][] {
    const outerRing = feature.geometry?.coordinates?.[0]?.[0];

    if (!Array.isArray(outerRing)) {
      throw new Error('건물 폴리곤 outer ring을 읽지 못했습니다.');
    }

    return outerRing;
  }
}

class AddressParser {
  public extractBuildingNumber(value: string) {
    const match = value.match(/(\d+(?:-\d+)?)(?:\s*\(|$)/);
    return match ? match[1] : null;
  }

  public extractRoadName(roadAddress: string) {
    const withoutSuffix = roadAddress.replace(
      /\s+\d+(?:-\d+)?(?:\s*\(.+\))?$/,
      '',
    );
    const parts = withoutSuffix.split(/\s+/);
    return parts.at(-1) ?? withoutSuffix;
  }
}

class VWorldBuildingVerticesApp {
  private readonly addressParser = new AddressParser();
  private readonly apiClient = new VWorldApiClient();
  private readonly coordinateFormatter = new CoordinateFormatter();
  private readonly envReader = new EnvFileReader();
  private readonly featureSelector = new BuildingFeatureSelector();

  public async run(inputAddress: string): Promise<BuildingVerticesResult> {
    const env = this.envReader.read(path.resolve(process.cwd(), '.env.local'));
    const apiKey = env.VWORLD_API_KEY || process.env.VWORLD_API_KEY;

    if (!apiKey) {
      throw new Error(
        'VWORLD_API_KEY가 없습니다. .env.local 또는 환경변수에 설정하십시오.',
      );
    }

    const searchResult = await this.apiClient.geocodeRoadAddress(
      inputAddress,
      apiKey,
    );
    const queryBuildingNo =
      this.addressParser.extractBuildingNumber(searchResult.address.road) ??
      this.addressParser.extractBuildingNumber(inputAddress);
    const bbox = this.coordinateFormatter.createWfsBbox(
      searchResult.point.y,
      searchResult.point.x,
      0.00035,
    );
    const features = await this.apiClient.fetchBuildingFeatures(bbox, apiKey);

    if (features.length === 0) {
      throw new Error('주소 주변에서 도로명주소건물 폴리곤을 찾지 못했습니다.');
    }

    const selectedFeature = this.featureSelector.select(features, {
      roadName: this.addressParser.extractRoadName(searchResult.address.road),
      buildingNo: queryBuildingNo,
      point: searchResult.point,
    });

    if (!selectedFeature) {
      throw new Error('대상 건물을 특정하지 못했습니다.');
    }

    const outerRing = this.coordinateFormatter.getOuterRing(selectedFeature);

    return {
      queryAddress: inputAddress,
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
  }
}

async function main() {
  const address = process.argv
    .slice(2)
    .filter(argument => argument !== '--')
    .join(' ')
    .trim() || DEFAULT_ADDRESS;
  const app = new VWorldBuildingVerticesApp();
  const result = await app.run(address);
  console.log(JSON.stringify(result, null, 2));
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
