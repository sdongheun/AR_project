import {describe, expect, it} from '@jest/globals';
import {
  AddressParser,
  BuildingFeatureSelector,
  CoordinateFormatter,
  PolygonContainmentChecker,
  type BuildingFeature,
} from '../src/services/vworldBuildingService';

describe('AddressParser', () => {
  const parser = new AddressParser();

  it('extracts road name and building number from a road address', () => {
    expect(parser.extractBuildingNumber('부산광역시 해운대구 달맞이길 30')).toBe(
      '30',
    );
    expect(parser.extractBuildingNumber('부산광역시 해운대구 달맞이길 30-1')).toBe(
      '30-1',
    );
    expect(parser.extractRoadName('부산광역시 해운대구 달맞이길 30')).toBe(
      '달맞이길',
    );
  });
});

describe('CoordinateFormatter', () => {
  const formatter = new CoordinateFormatter();

  it('creates the VWorld WFS bbox used by the current implementation', () => {
    expect(formatter.createWfsBbox(35.16, 129.16, 0.01)).toBe(
      '35.15,129.15,35.17,129.17,EPSG:4326',
    );
  });

  it('returns a feature outer ring', () => {
    const feature = createFeature({
      bbox: [129, 35, 130, 36],
      buildingNo: '1',
      roadName: '테스트로',
      ring: [
        [
          [129, 35],
          [130, 35],
          [130, 36],
          [129, 35],
        ],
      ],
    });

    expect(formatter.getOuterRing(feature)).toEqual([
      [129, 35],
      [130, 35],
      [130, 36],
      [129, 35],
    ]);
  });
});

describe('BuildingFeatureSelector', () => {
  const selector = new BuildingFeatureSelector();

  it('prefers an exact road name and building number match', () => {
    const fallback = createFeature({
      bbox: [129, 35, 130, 36],
      buildingNo: '8',
      roadName: '해운대로',
    });
    const exact = createFeature({
      bbox: [129, 35, 130, 36],
      buildingNo: '10',
      roadName: '해운대로',
    });

    expect(
      selector.select([fallback, exact], {
        buildingNo: '10',
        point: {x: 129.1, y: 35.1},
        roadName: '해운대로',
      }),
    ).toBe(exact);
  });

  it('falls back to a road-matched feature containing the geocoded point', () => {
    const outside = createFeature({
      bbox: [129, 35, 129.1, 35.1],
      buildingNo: '1',
      roadName: '광안해변로',
    });
    const containing = createFeature({
      bbox: [129.2, 35.1, 129.4, 35.3],
      buildingNo: '2',
      roadName: '광안해변로',
    });

    expect(
      selector.select([outside, containing], {
        buildingNo: null,
        point: {x: 129.3, y: 35.2},
        roadName: '광안해변로',
      }),
    ).toBe(containing);
  });
});

describe('PolygonContainmentChecker', () => {
  const checker = new PolygonContainmentChecker();
  const square = [
    [129, 35],
    [130, 35],
    [130, 36],
    [129, 36],
    [129, 35],
  ];

  it('detects inside, outside, and boundary points', () => {
    expect(checker.containsPoint({latitude: 35.5, longitude: 129.5}, square)).toBe(
      true,
    );
    expect(checker.containsPoint({latitude: 36.5, longitude: 129.5}, square)).toBe(
      false,
    );
    expect(checker.containsPoint({latitude: 35, longitude: 129.5}, square)).toBe(
      true,
    );
  });
});

function createFeature(params: {
  bbox: number[];
  buildingNo: string;
  roadName: string;
  ring?: number[][][];
}): BuildingFeature {
  return {
    bbox: params.bbox,
    geometry: {
      coordinates: [params.ring ?? [[[129, 35]]]],
    },
    properties: {
      bd_mgt_sn: 'test-management-number',
      buld_no: params.buildingNo,
      pnu: 'test-pnu',
      rd_nm: params.roadName,
    },
  };
}
