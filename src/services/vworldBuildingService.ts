import type {BuildingRecognitionCandidate} from './buildingRecognition';

const SEARCH_URL = 'https://api.vworld.kr/req/search';
const WFS_URL = 'https://api.vworld.kr/req/wfs';
const GIS_BUILDING_WFS_URL = 'https://api.vworld.kr/ned/wfs/getBldgisSpceWFS';

export type VWorldDebugInfo = {
  endpointName: 'search' | 'wfs' | 'gis-wfs';
  requestUrl: string;
  responseBody?: string;
  status?: number;
};

export type AddressPoint = {
  x: number;
  y: number;
};

export type AddressPayload = {
  parcel: string;
  road: string;
};

export type SearchResult = {
  address: AddressPayload;
  parcelCode?: string;
  point: AddressPoint;
};

type VWorldSearchResponse = {
  response?: {
    result?: {
      items?: Array<{
        address: {
          parcel: unknown;
          road: unknown;
        };
        id?: unknown;
        point: {
          x: unknown;
          y: unknown;
        };
      }>;
    };
    status?: string;
  };
};

export type BuildingFeatureProperties = {
  bd_mgt_sn: string;
  buld_no: string;
  pnu: string;
  rd_nm: string;
};

export type BuildingFeature = {
  bbox: number[];
  geometry?: {
    coordinates?: number[][][][];
  };
  properties: BuildingFeatureProperties;
};

type VWorldFeatureCollection = {
  features?: BuildingFeature[];
};

export type BuildingSelectionCriteria = {
  buildingNo: string | null;
  point: AddressPoint;
  roadName: string;
};

export type BuildingVerticesResult = {
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

export type BuildingContainmentResult = {
  buildingResult: BuildingVerticesResult;
  isInside: boolean;
};

export type GeoPoint = {
  latitude: number;
  longitude: number;
};

export type GisBuildingInfoResult = {
  building: {
    aboveGroundFloorCount: number;
    buildingName: string | null;
    gisBuildingId: string;
    heightMeters: number;
    parcelCode: string;
    polygonVertices: Array<{
      index: number;
      latitude: number;
      longitude: number;
    }>;
    totalFloorAreaSquareMeters: number;
    totalPlotAreaSquareMeters: number;
    undergroundFloorCount: number;
    useApprovalDate: string | null;
    violationBuildingYn: string | null;
  };
  geocodedPoint: {
    latitude: number;
    longitude: number;
  };
  parcelAddress: string;
  queryAddress: string;
  resolvedRoadAddress: string;
};

export class VWorldApiError extends Error {
  public constructor(
    message: string,
    public readonly debugInfo: VWorldDebugInfo,
  ) {
    super(message);
    this.name = 'VWorldApiError';
  }
}

export class VWorldApiClient {
  public async geocodeAddress(
    address: string,
    apiKey: string,
    categoryPriority: Array<'road' | 'parcel'> = ['road', 'parcel'],
  ): Promise<SearchResult> {
    for (const category of categoryPriority) {
      const result = await this.fetchGeocodeAddress(address, category, apiKey);

      if (result) {
        return result;
      }
    }

    throw new Error('주소를 좌표로 변환하지 못했습니다.');
  }

  public async geocodeRoadAddress(
    address: string,
    apiKey: string,
  ): Promise<SearchResult> {
    return this.fetchGeocodeAddress(address, 'road', apiKey).then(result => {
      if (!result) {
        throw new Error('도로명 주소를 좌표로 변환하지 못했습니다.');
      }

      return result;
    });
  }

  public async fetchIntegratedBuilding(
    params: {
      bbox?: string;
      parcelCode?: string;
    },
    apiKey: string,
  ): Promise<string> {
    const requestUrl = this.buildRequestUrl(GIS_BUILDING_WFS_URL, {
      typename: 'dt_d010',
      ...(params.bbox ? {bbox: params.bbox} : {}),
      ...(params.parcelCode ? {pnu: params.parcelCode} : {}),
      srsName: 'EPSG:4326',
      key: apiKey,
      domain: 'api.vworld.kr',
    });
    console.info('[VWorld][gis-wfs] request', requestUrl);

    const response = await fetch(requestUrl);
    console.info('[VWorld][gis-wfs] response', response.status, requestUrl);

    if (!response.ok) {
      const responseBody = await this.readResponseBody(response);
      throw new VWorldApiError(`GIS건물통합정보 호출 실패: ${response.status}`, {
        endpointName: 'gis-wfs',
        requestUrl,
        responseBody,
        status: response.status,
      });
    }

    return response.text();
  }

  private async fetchGeocodeAddress(
    address: string,
    category: 'road' | 'parcel',
    apiKey: string,
  ): Promise<SearchResult | null> {
    const requestUrl = this.buildRequestUrl(SEARCH_URL, {
      service: 'search',
      request: 'search',
      version: '2.0',
      format: 'json',
      errorformat: 'json',
      type: 'address',
      category,
      crs: 'EPSG:4326',
      size: '10',
      query: address,
      key: apiKey,
    });
    console.info('[VWorld][search] request', requestUrl);

    const response = await fetch(requestUrl);
    console.info('[VWorld][search] response', response.status, requestUrl);

    if (!response.ok) {
      const responseBody = await this.readResponseBody(response);
      throw new VWorldApiError(`검색 API 호출 실패: ${response.status}`, {
        endpointName: 'search',
        requestUrl,
        responseBody,
        status: response.status,
      });
    }

    const data = (await response.json()) as VWorldSearchResponse;
    const item = data?.response?.result?.items?.[0];

    if (data?.response?.status !== 'OK' || !item) {
      if (data?.response?.status === 'NOT_FOUND') {
        return null;
      }

      throw new VWorldApiError('검색 API 응답 이상', {
        endpointName: 'search',
        requestUrl,
        responseBody: JSON.stringify(data),
        status: response.status,
      });
    }

    return {
      address: {
        parcel: String(item.address.parcel),
        road: String(item.address.road),
      },
      parcelCode: typeof item.id === 'string' ? item.id : undefined,
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
    const requestUrl = this.buildRequestUrl(WFS_URL, {
      SERVICE: 'WFS',
      REQUEST: 'GetFeature',
      VERSION: '1.1.0',
      TYPENAME: 'lt_c_spbd',
      SRSNAME: 'EPSG:4326',
      BBOX: bbox,
      MAXFEATURES: '50',
      OUTPUTFORMAT: 'application/json',
      key: apiKey,
    });
    console.info('[VWorld][wfs] request', requestUrl);

    const response = await fetch(requestUrl);
    console.info('[VWorld][wfs] response', response.status, requestUrl);

    if (!response.ok) {
      const responseBody = await this.readResponseBody(response);
      throw new VWorldApiError(`WFS API 호출 실패: ${response.status}`, {
        endpointName: 'wfs',
        requestUrl,
        responseBody,
        status: response.status,
      });
    }

    const data = (await response.json()) as VWorldFeatureCollection;
    return (data.features ?? []) as BuildingFeature[];
  }

  private async readResponseBody(response: Response) {
    try {
      return await response.text();
    } catch {
      return undefined;
    }
  }

  private buildRequestUrl(
    baseUrl: string,
    params: Record<string, string>,
  ): string {
    const queryString = Object.entries(params)
      .map(([key, value]) => {
        return `${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
      })
      .join('&');

    return `${baseUrl}?${queryString}`;
  }
}

export class BuildingFeatureSelector {
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

export class CoordinateFormatter {
  public createWfsBbox(latitude: number, longitude: number, delta: number) {
    const minLat = latitude - delta;
    const minLon = longitude - delta;
    const maxLat = latitude + delta;
    const maxLon = longitude + delta;

    return `${this.formatCoordinate(minLat)},${this.formatCoordinate(
      minLon,
    )},${this.formatCoordinate(maxLat)},${this.formatCoordinate(
      maxLon,
    )},EPSG:4326`;
  }

  public getOuterRing(feature: BuildingFeature): number[][] {
    const outerRing = feature.geometry?.coordinates?.[0]?.[0];

    if (!Array.isArray(outerRing)) {
      throw new Error('건물 폴리곤 outer ring을 읽지 못했습니다.');
    }

    return outerRing;
  }

  private formatCoordinate(value: number) {
    return Number(value.toFixed(12)).toString();
  }
}

export class AddressParser {
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

export class PolygonContainmentChecker {
  public containsPoint(point: GeoPoint, polygon: number[][]) {
    if (polygon.length < 3) {
      return false;
    }

    for (let index = 0; index < polygon.length - 1; index += 1) {
      if (this.isPointOnSegment(point, polygon[index], polygon[index + 1])) {
        return true;
      }
    }

    let isInside = false;

    for (
      let current = 0, previous = polygon.length - 1;
      current < polygon.length;
      previous = current, current += 1
    ) {
      const [currentLon, currentLat] = polygon[current];
      const [previousLon, previousLat] = polygon[previous];

      const intersects =
        currentLat > point.latitude !== previousLat > point.latitude &&
        point.longitude <
          ((previousLon - currentLon) * (point.latitude - currentLat)) /
            (previousLat - currentLat) +
            currentLon;

      if (intersects) {
        isInside = !isInside;
      }
    }

    return isInside;
  }

  private isPointOnSegment(
    point: GeoPoint,
    segmentStart: number[],
    segmentEnd: number[],
  ) {
    const epsilon = 1e-10;
    const [startLon, startLat] = segmentStart;
    const [endLon, endLat] = segmentEnd;

    const crossProduct =
      (point.latitude - startLat) * (endLon - startLon) -
      (point.longitude - startLon) * (endLat - startLat);

    if (Math.abs(crossProduct) > epsilon) {
      return false;
    }

    const dotProduct =
      (point.longitude - startLon) * (endLon - startLon) +
      (point.latitude - startLat) * (endLat - startLat);

    if (dotProduct < 0) {
      return false;
    }

    const squaredLength =
      (endLon - startLon) * (endLon - startLon) +
      (endLat - startLat) * (endLat - startLat);

    return dotProduct <= squaredLength;
  }
}

export class VWorldBuildingService {
  public constructor(private readonly apiKey: string) {}

  private readonly addressParser = new AddressParser();
  private readonly apiClient = new VWorldApiClient();
  private readonly containmentChecker = new PolygonContainmentChecker();
  private readonly coordinateFormatter = new CoordinateFormatter();
  private readonly featureSelector = new BuildingFeatureSelector();

  public async resolveBuildingByAddress(inputAddress: string) {
    const searchResult = await this.apiClient.geocodeAddress(
      inputAddress,
      this.apiKey,
      ['road', 'parcel'],
    );
    const queryBuildingNo =
      this.addressParser.extractBuildingNumber(searchResult.address.road) ??
      this.addressParser.extractBuildingNumber(inputAddress);
    const bbox = this.coordinateFormatter.createWfsBbox(
      searchResult.point.y,
      searchResult.point.x,
      0.00035,
    );
    const features = await this.apiClient.fetchBuildingFeatures(
      bbox,
      this.apiKey,
    );

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
      outerRing,
      searchResult,
      selectedFeature,
    };
  }

  public async getBuildingVertices(
    inputAddress: string,
  ): Promise<BuildingVerticesResult> {
    const {outerRing, searchResult, selectedFeature} =
      await this.resolveBuildingByAddress(inputAddress);

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

  public async getBuildingContainmentForPoint(
    inputAddress: string,
    point: GeoPoint,
  ): Promise<BuildingContainmentResult> {
    const {outerRing, searchResult, selectedFeature} =
      await this.resolveBuildingByAddress(inputAddress);

    return {
      buildingResult: {
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
      },
      isInside: this.containmentChecker.containsPoint(point, outerRing),
    };
  }

  public async isPointInsideBuilding(
    inputAddress: string,
    point: GeoPoint,
  ): Promise<boolean> {
    const result = await this.getBuildingContainmentForPoint(inputAddress, point);
    return result.isInside;
  }

  public async getIntegratedBuildingInfo(
    inputAddress: string,
  ): Promise<GisBuildingInfoResult> {
    const searchResult = await this.apiClient.geocodeAddress(
      inputAddress,
      this.apiKey,
      ['parcel', 'road'],
    );

    const bbox = this.coordinateFormatter.createWfsBbox(
      searchResult.point.y,
      searchResult.point.x,
      0.00035,
    );
    const xml = await this.apiClient.fetchIntegratedBuilding(
      {
        bbox,
        parcelCode: searchResult.parcelCode,
      },
      this.apiKey,
    );
    const parsedFeature = new GisBuildingFeatureParser().parse(xml);

    return {
      queryAddress: inputAddress,
      resolvedRoadAddress: searchResult.address.road,
      parcelAddress: searchResult.address.parcel,
      geocodedPoint: {
        longitude: searchResult.point.x,
        latitude: searchResult.point.y,
      },
      building: {
        buildingName: parsedFeature.buildingName,
        aboveGroundFloorCount: parsedFeature.aboveGroundFloorCount,
        gisBuildingId: parsedFeature.gisBuildingId,
        heightMeters: parsedFeature.heightMeters,
        parcelCode: parsedFeature.parcelCode,
        polygonVertices: parsedFeature.polygon.map(
          ([longitude, latitude], index) => ({
            index,
            longitude,
            latitude,
          }),
        ),
        totalFloorAreaSquareMeters: parsedFeature.totalFloorAreaSquareMeters,
        totalPlotAreaSquareMeters: parsedFeature.totalPlotAreaSquareMeters,
        undergroundFloorCount: parsedFeature.undergroundFloorCount,
        useApprovalDate: parsedFeature.useApprovalDate,
        violationBuildingYn: parsedFeature.violationBuildingYn,
      },
    };
  }

  public async getBuildingRecognitionCandidatesNearPoint(point: GeoPoint) {
    const bbox = this.coordinateFormatter.createWfsBbox(
      point.latitude,
      point.longitude,
      0.00075,
    );
    const features = await this.apiClient.fetchBuildingFeatures(
      bbox,
      this.apiKey,
    );

    return features
      .map(feature => this.toRecognitionCandidate(feature))
      .filter(
        (
          candidate,
        ): candidate is BuildingRecognitionCandidate => candidate !== null,
      );
  }

  private toRecognitionCandidate(
    feature: BuildingFeature,
  ): BuildingRecognitionCandidate | null {
    let outerRing: number[][];

    try {
      outerRing = this.coordinateFormatter.getOuterRing(feature);
    } catch {
      return null;
    }

    if (outerRing.length < 3) {
      return null;
    }

    const nameParts = [
      feature.properties.rd_nm,
      feature.properties.buld_no,
    ].filter(Boolean);

    return {
      id:
        feature.properties.bd_mgt_sn ||
        feature.properties.pnu ||
        `${feature.properties.rd_nm}-${feature.properties.buld_no}`,
      name: nameParts.length > 0 ? nameParts.join(' ') : '건물 정보 없음',
      parcelCode: feature.properties.pnu,
      polygon: outerRing.map(([longitude, latitude]) => ({
        latitude,
        longitude,
      })),
      roadAddress: nameParts.join(' '),
    };
  }
}

type ParsedGisBuildingFeature = {
  aboveGroundFloorCount: number;
  buildingName: string | null;
  gisBuildingId: string;
  heightMeters: number;
  parcelCode: string;
  polygon: number[][];
  totalFloorAreaSquareMeters: number;
  totalPlotAreaSquareMeters: number;
  undergroundFloorCount: number;
  useApprovalDate: string | null;
  violationBuildingYn: string | null;
};

class GisBuildingFeatureParser {
  public parse(xml: string): ParsedGisBuildingFeature {
    const featureMatch = xml.match(/<sop:dt_d010\b[\s\S]*?<\/sop:dt_d010>/);

    if (!featureMatch) {
      throw new Error('GIS건물통합정보에서 건물 피처를 찾지 못했습니다.');
    }

    const featureXml = featureMatch[0];
    const geometryXml = this.getTagValue(featureXml, 'sop:ag_geom');
    const coordinatesText =
      (geometryXml ? this.getTagValue(geometryXml, 'gml:coordinates') : null) ??
      this.getTagValue(featureXml, 'gml:coordinates');

    if (!coordinatesText) {
      throw new Error('GIS건물통합정보에서 폴리곤 좌표를 찾지 못했습니다.');
    }

    return {
      aboveGroundFloorCount: this.toNumber(
        this.getRequiredTagValue(featureXml, 'sop:ground_floor_co'),
      ),
      buildingName: this.getTagValue(featureXml, 'sop:buld_nm'),
      gisBuildingId: this.getRequiredTagValue(featureXml, 'sop:gis_idntfc_no'),
      heightMeters: this.toNumber(this.getRequiredTagValue(featureXml, 'sop:hg')),
      parcelCode: this.getRequiredTagValue(featureXml, 'sop:pnu'),
      polygon: this.parseCoordinates(coordinatesText),
      totalFloorAreaSquareMeters: this.toNumber(
        this.getRequiredTagValue(featureXml, 'sop:totar'),
      ),
      totalPlotAreaSquareMeters: this.toNumber(
        this.getRequiredTagValue(featureXml, 'sop:plot_ar'),
      ),
      undergroundFloorCount: this.toNumber(
        this.getRequiredTagValue(featureXml, 'sop:undgrnd_floor_co'),
      ),
      useApprovalDate: this.getTagValue(featureXml, 'sop:use_confm_de'),
      violationBuildingYn: this.getTagValue(featureXml, 'sop:violt_bild'),
    };
  }

  private getRequiredTagValue(xml: string, tagName: string): string {
    const value = this.getTagValue(xml, tagName);

    if (!value) {
      throw new Error(`${tagName} 값을 읽지 못했습니다.`);
    }

    return value;
  }

  private getTagValue(xml: string, tagName: string): string | null {
    const pattern = new RegExp(
      `<${tagName}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tagName}>`,
    );
    const match = xml.match(pattern);
    const value = match?.[1]?.trim();

    return value ? value : null;
  }

  private parseCoordinates(value: string): number[][] {
    return value
      .trim()
      .split(/\s+/)
      .map(pair => pair.split(',').map(Number))
      .filter(
        (pair): pair is number[] =>
          pair.length === 2 &&
          Number.isFinite(pair[0]) &&
          Number.isFinite(pair[1]),
      );
  }

  private toNumber(value: string): number {
    const numericValue = Number(value);

    if (!Number.isFinite(numericValue)) {
      throw new Error(`숫자 변환에 실패했습니다: ${value}`);
    }

    return numericValue;
  }
}
