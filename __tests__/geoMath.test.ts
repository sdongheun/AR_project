import {describe, expect, it} from '@jest/globals';
import {
  angleDeltaDegrees,
  getBearingDegrees,
  getDistanceMeters,
  projectToLocalMeters,
} from '../src/services/geoMath';

describe('geoMath', () => {
  it('calculates distance, bearing, angle delta, and local projection', () => {
    const origin = {latitude: 35, longitude: 129};
    const north = {latitude: 35.0001, longitude: 129};

    expect(getDistanceMeters(origin, north)).toBeGreaterThan(10);
    expect(getDistanceMeters(origin, north)).toBeLessThan(12);
    expect(getBearingDegrees(origin, north)).toBeCloseTo(0, 0);
    expect(angleDeltaDegrees(350, 10)).toBe(20);

    const local = projectToLocalMeters(origin, north);
    expect(local.north).toBeGreaterThan(11);
    expect(Math.abs(local.east)).toBeLessThan(0.01);
  });
});
