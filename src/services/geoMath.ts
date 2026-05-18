export type GeoCoordinate = {
  latitude: number;
  longitude: number;
};

export type LocalPoint = {
  east: number;
  north: number;
};

const EARTH_RADIUS_METERS = 6371000;
const METERS_PER_LATITUDE_DEGREE = 111320;

export function toRadians(value: number) {
  return (value * Math.PI) / 180;
}

export function toDegrees(value: number) {
  return (value * 180) / Math.PI;
}

export function normalizeDegrees(value: number) {
  return ((value % 360) + 360) % 360;
}

export function angleDeltaDegrees(left: number, right: number) {
  const diff = Math.abs(normalizeDegrees(left) - normalizeDegrees(right));
  return Math.min(diff, 360 - diff);
}

export function getDistanceMeters(
  origin: GeoCoordinate,
  target: GeoCoordinate,
) {
  const dLat = toRadians(target.latitude - origin.latitude);
  const dLon = toRadians(target.longitude - origin.longitude);
  const latitudeA = toRadians(origin.latitude);
  const latitudeB = toRadians(target.latitude);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.sin(dLon / 2) *
      Math.sin(dLon / 2) *
      Math.cos(latitudeA) *
      Math.cos(latitudeB);

  return EARTH_RADIUS_METERS * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function getBearingDegrees(
  origin: GeoCoordinate,
  target: GeoCoordinate,
) {
  const latitudeA = toRadians(origin.latitude);
  const latitudeB = toRadians(target.latitude);
  const dLon = toRadians(target.longitude - origin.longitude);
  const y = Math.sin(dLon) * Math.cos(latitudeB);
  const x =
    Math.cos(latitudeA) * Math.sin(latitudeB) -
    Math.sin(latitudeA) * Math.cos(latitudeB) * Math.cos(dLon);

  return normalizeDegrees(toDegrees(Math.atan2(y, x)));
}

export function projectToLocalMeters(
  origin: GeoCoordinate,
  target: GeoCoordinate,
): LocalPoint {
  const metersPerLongitudeDegree =
    METERS_PER_LATITUDE_DEGREE * Math.cos(toRadians(origin.latitude));

  return {
    east: (target.longitude - origin.longitude) * metersPerLongitudeDegree,
    north: (target.latitude - origin.latitude) * METERS_PER_LATITUDE_DEGREE,
  };
}

export function localPointToBearingDegrees(point: LocalPoint) {
  return normalizeDegrees(toDegrees(Math.atan2(point.east, point.north)));
}

export function headingToUnitVector(headingDegrees: number): LocalPoint {
  const radians = toRadians(headingDegrees);

  return {
    east: Math.sin(radians),
    north: Math.cos(radians),
  };
}

export function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}
