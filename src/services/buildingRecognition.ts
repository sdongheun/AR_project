import {
  angleDeltaDegrees,
  clamp,
  headingToUnitVector,
  localPointToBearingDegrees,
  projectToLocalMeters,
  type GeoCoordinate,
  type LocalPoint,
} from './geoMath';

export type PoseSource = 'vps' | 'gps' | 'fallback';

export type UserPose = GeoCoordinate & {
  altitude: number;
  horizontalAccuracyMeters: number;
  source: PoseSource;
  timestampMs: number;
  verticalAccuracyMeters?: number;
};

export type CameraPose = {
  headingDegrees: number;
  orientationAccuracyDegrees?: number;
  pitchDegrees?: number;
  timestampMs: number;
};

export type BuildingRecognitionCandidate = {
  id: string;
  name: string;
  polygon: GeoCoordinate[];
  roadAddress?: string;
  parcelCode?: string;
  heightMeters?: number;
};

export type BuildingRecognitionOptions = {
  maxDistanceMeters?: number;
  maxHeadingDeltaDegrees?: number;
  fieldOfViewDegrees?: number;
  ambiguityScoreGap?: number;
  nowMs?: number;
};

export type ScoredBuildingCandidate = {
  building: BuildingRecognitionCandidate;
  score: number;
  distanceMeters: number;
  angleDeltaDegrees: number;
  nearestRayDistanceMeters: number;
  rayHit: boolean;
};

export type BuildingRecognitionResult =
  | {
      type: 'recognized';
      building: BuildingRecognitionCandidate;
      confidence: 'high' | 'medium' | 'low';
      score: number;
      distanceMeters: number;
      angleDeltaDegrees: number;
      debug: RecognitionDebug;
    }
  | {
      type: 'ambiguous';
      candidates: ScoredBuildingCandidate[];
      debug: RecognitionDebug;
    }
  | {
      type: 'none';
      reason: string;
      debug: RecognitionDebug;
    };

export type RecognitionDebug = {
  candidateCount: number;
  rejected: Array<{
    id: string;
    reason: string;
  }>;
  scoredCandidates: ScoredBuildingCandidate[];
  userPoseSource: PoseSource;
  horizontalAccuracyMeters: number;
};

const DEFAULT_OPTIONS = {
  ambiguityScoreGap: 8,
  fieldOfViewDegrees: 45,
  maxDistanceMeters: 100,
  maxHeadingDeltaDegrees: 30,
};

export function selectLookedAtBuilding(
  userPose: UserPose,
  cameraPose: CameraPose,
  buildingCandidates: BuildingRecognitionCandidate[],
  options: BuildingRecognitionOptions = {},
): BuildingRecognitionResult {
  const resolvedOptions = {
    ...DEFAULT_OPTIONS,
    ...options,
  };
  const nowMs = options.nowMs ?? Date.now();
  const debug: RecognitionDebug = {
    candidateCount: buildingCandidates.length,
    horizontalAccuracyMeters: userPose.horizontalAccuracyMeters,
    rejected: [],
    scoredCandidates: [],
    userPoseSource: userPose.source,
  };

  if (nowMs - userPose.timestampMs > 3000) {
    return {
      type: 'none',
      reason: 'stale_user_pose',
      debug,
    };
  }

  if (!Number.isFinite(cameraPose.headingDegrees)) {
    return {
      type: 'none',
      reason: 'missing_camera_heading',
      debug,
    };
  }

  const rayDirection = headingToUnitVector(cameraPose.headingDegrees);
  const hitToleranceMeters = clamp(
    userPose.horizontalAccuracyMeters + 2,
    5,
    15,
  );

  const scoredCandidates = buildingCandidates
    .map(candidate =>
      scoreCandidate(
        userPose,
        cameraPose,
        candidate,
        rayDirection,
        hitToleranceMeters,
        resolvedOptions,
      ),
    )
    .filter((candidateScore): candidateScore is ScoredBuildingCandidate => {
      if (!candidateScore) {
        return false;
      }

      return true;
    })
    .sort((left, right) => left.score - right.score);

  debug.scoredCandidates = scoredCandidates;

  for (const candidate of buildingCandidates) {
    if (!scoredCandidates.some(scored => scored.building.id === candidate.id)) {
      debug.rejected.push({
        id: candidate.id,
        reason: 'outside_distance_or_heading',
      });
    }
  }

  const best = scoredCandidates[0];
  if (!best) {
    return {
      type: 'none',
      reason: 'no_candidate_in_view',
      debug,
    };
  }

  const second = scoredCandidates[1];
  if (
    second &&
    second.score - best.score < resolvedOptions.ambiguityScoreGap
  ) {
    return {
      type: 'ambiguous',
      candidates: scoredCandidates.slice(0, 3),
      debug,
    };
  }

  return {
    type: 'recognized',
    building: best.building,
    confidence: getConfidence(best, userPose),
    score: best.score,
    distanceMeters: best.distanceMeters,
    angleDeltaDegrees: best.angleDeltaDegrees,
    debug,
  };
}

function scoreCandidate(
  userPose: UserPose,
  cameraPose: CameraPose,
  candidate: BuildingRecognitionCandidate,
  rayDirection: LocalPoint,
  hitToleranceMeters: number,
  options: Required<
    Pick<
      BuildingRecognitionOptions,
      'ambiguityScoreGap' | 'fieldOfViewDegrees' | 'maxDistanceMeters' | 'maxHeadingDeltaDegrees'
    >
  >,
): ScoredBuildingCandidate | null {
  const localPolygon = candidate.polygon.map(point =>
    projectToLocalMeters(userPose, point),
  );

  if (localPolygon.length < 3) {
    return null;
  }

  const centroid = getCentroid(localPolygon);
  const centroidBearing = localPointToBearingDegrees(centroid);
  const angleDelta = angleDeltaDegrees(cameraPose.headingDegrees, centroidBearing);
  const distanceMeters = getDistanceToPolygonMeters(localPolygon);
  const nearestRayDistanceMeters = getRayPolygonDistanceMeters(
    rayDirection,
    localPolygon,
  );
  const rayHit = nearestRayDistanceMeters <= hitToleranceMeters;
  const inFieldOfView = angleDelta <= options.fieldOfViewDegrees / 2;

  if (distanceMeters > options.maxDistanceMeters) {
    return null;
  }

  if (!rayHit && !inFieldOfView) {
    return null;
  }

  if (angleDelta > options.maxHeadingDeltaDegrees && !rayHit) {
    return null;
  }

  const accuracyPenalty =
    userPose.horizontalAccuracyMeters > 8
      ? (userPose.horizontalAccuracyMeters - 8) * 1.5
      : 0;
  const metadataPenalty =
    candidate.name.trim().length === 0 && !candidate.roadAddress ? 10 : 0;
  const rayHitBonus = rayHit ? 25 : 0;
  const score =
    angleDelta * 2 +
    distanceMeters * 0.15 +
    nearestRayDistanceMeters * 1.5 +
    accuracyPenalty +
    metadataPenalty -
    rayHitBonus;

  return {
    angleDeltaDegrees: angleDelta,
    building: candidate,
    distanceMeters,
    nearestRayDistanceMeters,
    rayHit,
    score,
  };
}

function getConfidence(candidate: ScoredBuildingCandidate, userPose: UserPose) {
  if (
    candidate.rayHit &&
    candidate.angleDeltaDegrees <= 12 &&
    candidate.distanceMeters <= 50 &&
    userPose.horizontalAccuracyMeters <= 8
  ) {
    return 'high';
  }

  if (
    candidate.rayHit ||
    (candidate.angleDeltaDegrees <= 18 && candidate.distanceMeters <= 80)
  ) {
    return 'medium';
  }

  return 'low';
}

function getCentroid(points: LocalPoint[]): LocalPoint {
  const sum = points.reduce(
    (total, point) => ({
      east: total.east + point.east,
      north: total.north + point.north,
    }),
    {east: 0, north: 0},
  );

  return {
    east: sum.east / points.length,
    north: sum.north / points.length,
  };
}

function getDistanceToPolygonMeters(polygon: LocalPoint[]) {
  if (isPointInPolygon({east: 0, north: 0}, polygon)) {
    return 0;
  }

  let nearest = Number.POSITIVE_INFINITY;

  forEachSegment(polygon, (start, end) => {
    nearest = Math.min(nearest, getPointSegmentDistanceMeters({east: 0, north: 0}, start, end));
  });

  return nearest;
}

function getRayPolygonDistanceMeters(rayDirection: LocalPoint, polygon: LocalPoint[]) {
  let nearest = Number.POSITIVE_INFINITY;

  forEachSegment(polygon, (start, end) => {
    const intersectionDistance = getRaySegmentIntersectionDistance(
      rayDirection,
      start,
      end,
    );

    if (intersectionDistance !== null) {
      nearest = Math.min(nearest, 0);
      return;
    }

    nearest = Math.min(
      nearest,
      getPointRayDistanceMeters(start, rayDirection),
      getPointRayDistanceMeters(end, rayDirection),
    );
  });

  return nearest;
}

function getPointRayDistanceMeters(point: LocalPoint, rayDirection: LocalPoint) {
  const projection = point.east * rayDirection.east + point.north * rayDirection.north;

  if (projection < 0) {
    return Math.sqrt(point.east * point.east + point.north * point.north);
  }

  const closest = {
    east: rayDirection.east * projection,
    north: rayDirection.north * projection,
  };

  return distance(point, closest);
}

function getRaySegmentIntersectionDistance(
  rayDirection: LocalPoint,
  start: LocalPoint,
  end: LocalPoint,
) {
  const segment = {
    east: end.east - start.east,
    north: end.north - start.north,
  };
  const denominator = cross(rayDirection, segment);

  if (Math.abs(denominator) < 1e-9) {
    return null;
  }

  const startFromOrigin = start;
  const rayDistance = cross(startFromOrigin, segment) / denominator;
  const segmentDistance = cross(startFromOrigin, rayDirection) / denominator;

  if (rayDistance >= 0 && segmentDistance >= 0 && segmentDistance <= 1) {
    return rayDistance;
  }

  return null;
}

function getPointSegmentDistanceMeters(
  point: LocalPoint,
  start: LocalPoint,
  end: LocalPoint,
) {
  const segment = {
    east: end.east - start.east,
    north: end.north - start.north,
  };
  const segmentLengthSquared =
    segment.east * segment.east + segment.north * segment.north;

  if (segmentLengthSquared === 0) {
    return distance(point, start);
  }

  const projection =
    ((point.east - start.east) * segment.east +
      (point.north - start.north) * segment.north) /
    segmentLengthSquared;
  const clampedProjection = clamp(projection, 0, 1);

  return distance(point, {
    east: start.east + segment.east * clampedProjection,
    north: start.north + segment.north * clampedProjection,
  });
}

function isPointInPolygon(point: LocalPoint, polygon: LocalPoint[]) {
  let inside = false;

  for (
    let current = 0, previous = polygon.length - 1;
    current < polygon.length;
    previous = current, current += 1
  ) {
    const currentPoint = polygon[current];
    const previousPoint = polygon[previous];
    const intersects =
      currentPoint.north > point.north !== previousPoint.north > point.north &&
      point.east <
        ((previousPoint.east - currentPoint.east) *
          (point.north - currentPoint.north)) /
          (previousPoint.north - currentPoint.north) +
          currentPoint.east;

    if (intersects) {
      inside = !inside;
    }
  }

  return inside;
}

function forEachSegment(
  polygon: LocalPoint[],
  callback: (start: LocalPoint, end: LocalPoint) => void,
) {
  for (let index = 0; index < polygon.length; index += 1) {
    callback(polygon[index], polygon[(index + 1) % polygon.length]);
  }
}

function cross(left: LocalPoint, right: LocalPoint) {
  return left.east * right.north - left.north * right.east;
}

function distance(left: LocalPoint, right: LocalPoint) {
  const dEast = left.east - right.east;
  const dNorth = left.north - right.north;

  return Math.sqrt(dEast * dEast + dNorth * dNorth);
}
