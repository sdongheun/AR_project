#!/usr/bin/env python3
import argparse
import json
import math
import sys
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SECRETS_PATH = ROOT / "Config" / "Secrets.local.xcconfig"

TOURAPI_ENDPOINT = "https://apis.data.go.kr/B551011/LocgoHubTarService1/areaBasedList1"
VWORLD_ENDPOINT = "https://api.vworld.kr/req/data"

BUSAN_REQUESTS = [
    ("26110", "중구"),
    ("26140", "서구"),
    ("26170", "동구"),
    ("26200", "영도구"),
    ("26230", "부산진구"),
    ("26260", "동래구"),
    ("26290", "남구"),
    ("26320", "북구"),
    ("26350", "해운대구"),
    ("26380", "사하구"),
    ("26410", "금정구"),
    ("26440", "강서구"),
    ("26470", "연제구"),
    ("26500", "수영구"),
    ("26530", "사상구"),
    ("26710", "기장군"),
]


def load_xcconfig(path):
    values = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def fetch_json(url, timeout=15):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "ARBusan-height-probe/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = response.read()
    return json.loads(data.decode("utf-8"))


def first_value(dictionary, keys):
    for key in keys:
        value = dictionary.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return None


def first_float(dictionary, keys):
    value = first_value(dictionary, keys)
    if value is None:
        return None
    try:
        return float(value.replace(",", ""))
    except ValueError:
        return None


def first_int(dictionary, keys):
    value = first_value(dictionary, keys)
    if value is None:
        return None
    try:
        return int(float(value.replace(",", "")))
    except ValueError:
        return None


def find_tourapi_items(value):
    if isinstance(value, dict):
        item = value.get("item")
        if isinstance(item, list):
            return item
        if isinstance(item, dict):
            return [item]
        for child in value.values():
            found = find_tourapi_items(child)
            if found is not None:
                return found
    if isinstance(value, list):
        for child in value:
            found = find_tourapi_items(child)
            if found is not None:
                return found
    return None


def make_tourapi_url(api_key, base_ym, area_cd, signgu_cd, rows):
    query = urllib.parse.urlencode(
        {
            "serviceKey": api_key,
            "MobileOS": "IOS",
            "MobileApp": "ARBusanHeightProbe",
            "baseYm": base_ym,
            "areaCd": area_cd,
            "signguCd": signgu_cd,
            "numOfRows": str(rows),
            "pageNo": "1",
            "_type": "json",
        }
    )
    return f"{TOURAPI_ENDPOINT}?{query}"


def make_vworld_url(api_key, latitude, longitude, half_size_degrees):
    min_lon = longitude - half_size_degrees
    min_lat = latitude - half_size_degrees
    max_lon = longitude + half_size_degrees
    max_lat = latitude + half_size_degrees
    query = urllib.parse.urlencode(
        {
            "service": "data",
            "version": "2.0",
            "request": "GetFeature",
            "format": "json",
            "data": "LT_C_SPBD",
            "geometry": "true",
            "attribute": "true",
            "crs": "EPSG:4326",
            "geomFilter": f"BOX({min_lon},{min_lat},{max_lon},{max_lat})",
            "size": "10",
            "page": "1",
            "key": api_key,
        }
    )
    return f"{VWORLD_ENDPOINT}?{query}"


def parse_rings(geometry):
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type == "Polygon" and isinstance(coordinates, list):
        return coordinates
    if geometry_type == "MultiPolygon" and isinstance(coordinates, list):
        rings = []
        for polygon in coordinates:
            rings.extend(polygon)
        return rings
    return []


def point_in_ring(longitude, latitude, ring):
    if len(ring) < 3:
        return False

    inside = False
    previous = ring[-1]
    for current in ring:
        current_lon, current_lat = current[:2]
        previous_lon, previous_lat = previous[:2]

        intersects = (current_lat > latitude) != (previous_lat > latitude)
        if intersects:
            crossing_lon = (
                (previous_lon - current_lon)
                * (latitude - current_lat)
                / (previous_lat - current_lat)
                + current_lon
            )
            if longitude < crossing_lon:
                inside = not inside
        previous = current
    return inside


def point_in_polygon(longitude, latitude, rings):
    return any(point_in_ring(longitude, latitude, ring) for ring in rings)


def centroid_distance_meters(longitude, latitude, rings):
    points = [point for ring in rings for point in ring if len(point) >= 2]
    if not points:
        return math.inf
    center_lon = sum(point[0] for point in points) / len(points)
    center_lat = sum(point[1] for point in points) / len(points)
    meters_per_lat = 111_320.0
    meters_per_lon = math.cos(math.radians(latitude)) * meters_per_lat
    return math.hypot((longitude - center_lon) * meters_per_lon, (latitude - center_lat) * meters_per_lat)


def parse_tourapi_spot(item):
    name = first_value(item, ["hubTatsNm", "hubTarNm", "hubTitle", "title", "tAtsNm", "trrsrtNm", "name"])
    longitude = first_float(item, ["mapx", "mapX", "gpsX", "longitude", "lon", "lng", "x"])
    latitude = first_float(item, ["mapy", "mapY", "gpsY", "latitude", "lat", "y"])
    if name is None or longitude is None or latitude is None:
        return None
    return {
        "name": name,
        "longitude": longitude,
        "latitude": latitude,
    }


def fetch_tourapi_spots(api_key, base_ym, area_cd, signgu_cd, rows):
    tourapi_url = make_tourapi_url(api_key, base_ym, area_cd, signgu_cd, rows)
    tourapi_object = fetch_json(tourapi_url)
    items = find_tourapi_items(tourapi_object) or []
    return [spot for item in items if (spot := parse_tourapi_spot(item)) is not None]


def select_building_feature(vworld_object, longitude, latitude):
    response = vworld_object.get("response", {})
    if str(response.get("status", "")).upper() != "OK":
        return None

    features = (
        response.get("result", {})
        .get("featureCollection", {})
        .get("features", [])
    )

    candidates = []
    for feature in features:
        geometry = feature.get("geometry", {})
        rings = parse_rings(geometry)
        if not rings:
            continue
        properties = feature.get("properties", {}) or {}
        contains = point_in_polygon(longitude, latitude, rings)
        distance = centroid_distance_meters(longitude, latitude, rings)
        candidates.append((contains, distance, properties))

    containing = [candidate for candidate in candidates if candidate[0]]
    if containing:
        return min(containing, key=lambda candidate: candidate[1])[2]
    return None


def format_height(value):
    if value is None:
        return "없음"
    if value.is_integer():
        return f"{int(value)}m"
    return f"{value:.1f}m"


def format_floor(value):
    if value is None:
        return "없음"
    return f"{value}층"


def main():
    parser = argparse.ArgumentParser(description="TourAPI POI와 브이월드 건물 높이/층수 테스트")
    parser.add_argument("--target", choices=["gimhae", "busan", "custom"], default="gimhae")
    parser.add_argument("--base-ym", default="202504")
    parser.add_argument("--area-cd", default="48")
    parser.add_argument("--signgu-cd", default="48250")
    parser.add_argument("--rows", type=int, default=100)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--box-half-size", type=float, default=0.00025)
    parser.add_argument("--show-properties", action="store_true")
    args = parser.parse_args()

    config = load_xcconfig(SECRETS_PATH)
    tourapi_key = config.get("TOUR_API_KEY", "")
    vworld_key = config.get("VWORLD_API_KEY", "")
    if not tourapi_key or not vworld_key:
        print("TOUR_API_KEY 또는 VWORLD_API_KEY가 Secrets.local.xcconfig에 없습니다.", file=sys.stderr)
        return 1

    requests = []
    if args.target == "busan":
        requests = [("26", signgu_cd, name) for signgu_cd, name in BUSAN_REQUESTS]
    else:
        requests = [(args.area_cd, args.signgu_cd, args.signgu_cd)]

    spots = []
    for area_cd, signgu_cd, name in requests:
        district_spots = fetch_tourapi_spots(tourapi_key, args.base_ym, area_cd, signgu_cd, args.rows)
        print(f"TourAPI {name} POI {len(district_spots)}개 수신 / areaCd={area_cd}, signguCd={signgu_cd}")
        for spot in district_spots:
            spot["district"] = name
        spots.extend(district_spots)

    print(f"TourAPI POI 총 {len(spots)}개 수신 / target={args.target}")
    print("POI 포함 브이월드 건물 Polygon이 있는 대상만 높이/층수를 출력합니다.")

    matched_count = 0
    for spot in spots[: args.limit]:
        vworld_url = make_vworld_url(vworld_key, spot["latitude"], spot["longitude"], args.box_half_size)
        vworld_object = fetch_json(vworld_url)
        properties = select_building_feature(vworld_object, spot["longitude"], spot["latitude"])
        if properties is None:
            continue

        matched_count += 1
        building_name = first_value(
            properties,
            ["BLD_NM", "bld_nm", "BULD_NM", "buld_nm", "BD_NM", "bd_nm"],
        ) or spot["name"]
        height = first_float(properties, ["HEIGHT", "height", "HEIT", "heit", "BLD_HG", "bld_hg"])
        floors = first_int(
            properties,
            [
                "GRND_FLR",
                "grnd_flr",
                "GROUND_FLR",
                "ground_flr",
                "FLR",
                "flr",
                "GRO_FLO_CO",
                "gro_flo_co",
            ],
        )
        print(f"{spot['name']} -> {building_name} 건물 : 높이 : {format_height(height)}, 층 수 {format_floor(floors)}")
        if args.show_properties:
            property_text = " / ".join(
                f"{key}={value}" for key, value in sorted(properties.items())
            )
            print(f"  properties: {property_text}")

    print(f"출력 완료: POI 포함 건물 Polygon 매칭 {matched_count}개")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
