import {describe, expect, it} from '@jest/globals';
import {
  selectLookedAtBuilding,
  type BuildingRecognitionCandidate,
  type UserPose,
} from '../src/services/buildingRecognition';

const origin = {
  latitude: 35,
  longitude: 129,
};
const nowMs = 100000;
const userPose: UserPose = {
  ...origin,
  altitude: 0,
  horizontalAccuracyMeters: 4,
  source: 'vps',
  timestampMs: nowMs,
};

describe('selectLookedAtBuilding', () => {
  it('recognizes the building intersected by the camera ray', () => {
    const result = selectLookedAtBuilding(
      userPose,
      {headingDegrees: 0, timestampMs: nowMs},
      [
        createRectCandidate('front', '정면 건물', -6, 24, 6, 38),
        createRectCandidate('east', '오른쪽 건물', 18, 20, 30, 36),
      ],
      {nowMs},
    );

    expect(result.type).toBe('recognized');
    if (result.type === 'recognized') {
      expect(result.building.id).toBe('front');
      expect(result.confidence).toBe('high');
    }
  });

  it('rejects a building when the camera heading is more than 30 degrees away', () => {
    const result = selectLookedAtBuilding(
      userPose,
      {headingDegrees: 90, timestampMs: nowMs},
      [createRectCandidate('north', '북쪽 건물', -6, 24, 6, 38)],
      {nowMs},
    );

    expect(result.type).toBe('none');
  });

  it('returns ambiguous when top candidates have similar scores', () => {
    const result = selectLookedAtBuilding(
      userPose,
      {headingDegrees: 0, timestampMs: nowMs},
      [
        createRectCandidate('left', '왼쪽 건물', -10, 24, -2, 38),
        createRectCandidate('right', '오른쪽 건물', 2, 24, 10, 38),
      ],
      {nowMs},
    );

    expect(result.type).toBe('ambiguous');
  });

  it('keeps a long building selectable when its centroid is off center but the ray hits the polygon', () => {
    const result = selectLookedAtBuilding(
      userPose,
      {headingDegrees: 0, timestampMs: nowMs},
      [createRectCandidate('long', '긴 건물', -2, 20, 45, 34)],
      {nowMs},
    );

    expect(result.type).toBe('recognized');
    if (result.type === 'recognized') {
      expect(result.building.id).toBe('long');
    }
  });
});

function createRectCandidate(
  id: string,
  name: string,
  minEast: number,
  minNorth: number,
  maxEast: number,
  maxNorth: number,
): BuildingRecognitionCandidate {
  return {
    id,
    name,
    polygon: [
      toGeo(minEast, minNorth),
      toGeo(maxEast, minNorth),
      toGeo(maxEast, maxNorth),
      toGeo(minEast, maxNorth),
      toGeo(minEast, minNorth),
    ],
  };
}

function toGeo(east: number, north: number) {
  const metersPerLat = 111320;
  const metersPerLon =
    111320 * Math.cos((origin.latitude * Math.PI) / 180);

  return {
    latitude: origin.latitude + north / metersPerLat,
    longitude: origin.longitude + east / metersPerLon,
  };
}
