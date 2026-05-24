import CoreLocation
import Foundation

struct BuildingPolygon: Equatable {
    let spotID: TourismSpot.ID
    let rings: [[CLLocationCoordinate2D]]
    let sourceLayer: String

    var vertexCount: Int {
        rings.reduce(0) { $0 + $1.count }
    }

    var centroid: CLLocationCoordinate2D? {
        let coordinates = rings.flatMap { $0 }
        guard !coordinates.isEmpty else {
            return nil
        }

        let latitude = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let longitude = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func == (lhs: BuildingPolygon, rhs: BuildingPolygon) -> Bool {
        lhs.spotID == rhs.spotID
            && lhs.sourceLayer == rhs.sourceLayer
            && lhs.vertexCount == rhs.vertexCount
    }
}

protocol VWorldClient {
    func validatePolygon(for spot: TourismSpot) async throws -> Bool
    func fetchBuildingPolygon(for spot: TourismSpot) async throws -> BuildingPolygon?
}

protocol VWorldDiagnosticClient: VWorldClient {
    func fetchBuildingPolygonWithDiagnostics(for spot: TourismSpot) async throws -> VWorldPolygonLookupResult
}

struct VWorldPolygonLookupResult {
    let polygon: BuildingPolygon?
    let logs: [String]
}

struct MockVWorldClient: VWorldClient {
    func validatePolygon(for spot: TourismSpot) async throws -> Bool {
        spot.geometryKind == .buildingPolygon
    }

    func fetchBuildingPolygon(for spot: TourismSpot) async throws -> BuildingPolygon? {
        let offset = 0.00005
        let center = spot.center
        return BuildingPolygon(
            spotID: spot.id,
            rings: [[
                CLLocationCoordinate2D(latitude: center.latitude - offset, longitude: center.longitude - offset),
                CLLocationCoordinate2D(latitude: center.latitude - offset, longitude: center.longitude + offset),
                CLLocationCoordinate2D(latitude: center.latitude + offset, longitude: center.longitude + offset),
                CLLocationCoordinate2D(latitude: center.latitude + offset, longitude: center.longitude - offset),
                CLLocationCoordinate2D(latitude: center.latitude - offset, longitude: center.longitude - offset),
            ]],
            sourceLayer: "mock"
        )
    }
}

struct VWorldDataAPIClient: VWorldDiagnosticClient {
    private let apiKey: String
    private let session: URLSession
    private let buildingLayer = "LT_C_SPBD"
    private let searchHalfSizeDegrees = 0.00025

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func validatePolygon(for spot: TourismSpot) async throws -> Bool {
        try await fetchBuildingPolygon(for: spot) != nil
    }

    func fetchBuildingPolygon(for spot: TourismSpot) async throws -> BuildingPolygon? {
        try await fetchBuildingPolygonWithDiagnostics(for: spot).polygon
    }

    func fetchBuildingPolygonWithDiagnostics(for spot: TourismSpot) async throws -> VWorldPolygonLookupResult {
        var logs: [String] = []
        logs.append("브이월드 요청 대상: \(spot.name) / POI \(spot.center.latitude), \(spot.center.longitude)")

        guard apiKey.isUsableAPIKey else {
            logs.append("브이월드 요청 중단: API 키 없음")
            throw VWorldClientError.missingAPIKey
        }

        guard let url = makeURL(for: spot) else {
            logs.append("브이월드 요청 중단: URL 생성 실패")
            throw VWorldClientError.invalidURL
        }
        logs.append("브이월드 요청 URL: \(Self.redactedURLString(url))")

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            logs.append("브이월드 응답 오류: HTTP 응답 아님")
            throw VWorldClientError.invalidResponse
        }
        logs.append("브이월드 HTTP 상태: \(httpResponse.statusCode)")
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw VWorldClientError.requestFailed(httpResponse.statusCode)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let parseResult = try parseBuildingPolygons(from: object, spotID: spot.id, spotCenter: spot.center)
        logs.append(contentsOf: parseResult.logs)

        let containingPolygons = parseResult.polygons.filter {
            $0.contains(spot.center)
        }
        logs.append("브이월드 POI 포함 Polygon 개수: \(containingPolygons.count)")

        let polygon: BuildingPolygon?
        if let containingPolygon = containingPolygons.min(by: {
            $0.distanceFromCentroid(to: spot.center) < $1.distanceFromCentroid(to: spot.center)
        }) {
            polygon = containingPolygon
            logs.append("브이월드 선택 기준: POI가 Polygon 내부에 포함됨")
        } else {
            polygon = parseResult.polygons.min {
                $0.distanceFromCentroid(to: spot.center) < $1.distanceFromCentroid(to: spot.center)
            }
            if polygon != nil {
                logs.append("브이월드 선택 기준: POI 내부 포함 후보 없음, centroid 최단 거리 fallback")
            }
        }
        if let polygon {
            logs.append("브이월드 선택 Polygon: 외곽 좌표 \(polygon.vertexCount)개 / centroid \(polygon.centroid?.latitude ?? 0), \(polygon.centroid?.longitude ?? 0)")
        } else {
            logs.append("브이월드 선택 Polygon 없음")
        }
        return VWorldPolygonLookupResult(polygon: polygon, logs: logs)
    }

    private func makeURL(for spot: TourismSpot) -> URL? {
        let center = spot.center
        let minLongitude = center.longitude - searchHalfSizeDegrees
        let minLatitude = center.latitude - searchHalfSizeDegrees
        let maxLongitude = center.longitude + searchHalfSizeDegrees
        let maxLatitude = center.latitude + searchHalfSizeDegrees

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.vworld.kr"
        components.path = "/req/data"
        components.queryItems = [
            URLQueryItem(name: "service", value: "data"),
            URLQueryItem(name: "version", value: "2.0"),
            URLQueryItem(name: "request", value: "GetFeature"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "data", value: buildingLayer),
            URLQueryItem(name: "geometry", value: "true"),
            URLQueryItem(name: "attribute", value: "true"),
            URLQueryItem(name: "crs", value: "EPSG:4326"),
            URLQueryItem(name: "geomFilter", value: "BOX(\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude))"),
            URLQueryItem(name: "size", value: "10"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        return components.url
    }

    private func parseBuildingPolygons(
        from object: Any,
        spotID: TourismSpot.ID,
        spotCenter: CLLocationCoordinate2D
    ) throws -> VWorldPolygonParseResult {
        var logs: [String] = []
        guard let dictionary = object as? [String: Any],
              let response = dictionary["response"] as? [String: Any],
              let status = response["status"] as? String else {
            throw VWorldClientError.invalidResponse
        }
        logs.append("브이월드 response.status: \(status)")

        guard status.uppercased() == "OK" else {
            if let error = response["error"] as? [String: Any] {
                let code = error["code"] as? String ?? "unknown"
                let text = error["text"] as? String ?? "unknown"
                logs.append("브이월드 response.error: \(code) / \(text)")
            }
            return VWorldPolygonParseResult(polygons: [], logs: logs)
        }

        guard let result = response["result"] as? [String: Any],
              let featureCollection = result["featureCollection"] as? [String: Any],
              let features = featureCollection["features"] as? [[String: Any]] else {
            logs.append("브이월드 featureCollection 없음")
            return VWorldPolygonParseResult(polygons: [], logs: logs)
        }
        logs.append("브이월드 feature 개수: \(features.count)")

        let polygons = features.compactMap { feature -> BuildingPolygon? in
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else {
                return nil
            }

            let rings: [[CLLocationCoordinate2D]]
            switch type {
            case "Polygon":
                rings = Self.parsePolygonRings(from: coordinates)
            case "MultiPolygon":
                rings = Self.parseMultiPolygonRings(from: coordinates)
            default:
                rings = []
            }

            guard !rings.isEmpty else {
                return nil
            }

            return BuildingPolygon(
                spotID: spotID,
                rings: rings,
                sourceLayer: buildingLayer
            )
        }
        logs.append("브이월드 파싱된 Polygon 개수: \(polygons.count)")
        for (index, polygon) in polygons.enumerated() {
            logs.append("브이월드 후보 Polygon #\(index + 1): 외곽 좌표 \(polygon.vertexCount)개 / centroid \(polygon.centroidDescription) / POI 포함 \(polygon.contains(spotCenter) ? "예" : "아니오")")
            logs.append("브이월드 후보 Polygon #\(index + 1) 좌표: \(polygon.coordinateListDescription)")
        }
        return VWorldPolygonParseResult(polygons: polygons, logs: logs)
    }

    private static func parsePolygonRings(from value: Any) -> [[CLLocationCoordinate2D]] {
        guard let rings = value as? [[[Double]]] else {
            return []
        }
        return rings.map { ring in
            ring.compactMap { pair in
                guard pair.count >= 2 else {
                    return nil
                }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
        }
    }

    private static func parseMultiPolygonRings(from value: Any) -> [[CLLocationCoordinate2D]] {
        guard let polygons = value as? [[[[Double]]]] else {
            return []
        }
        return polygons.flatMap { polygon in
            parsePolygonRings(from: polygon)
        }
    }

    private static func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            item.name == "key" ? URLQueryItem(name: item.name, value: "REDACTED") : item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}

private struct VWorldPolygonParseResult {
    let polygons: [BuildingPolygon]
    let logs: [String]
}

enum VWorldClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "브이월드 API 키가 설정되지 않았습니다."
        case .invalidURL:
            return "브이월드 Polygon 요청 URL을 만들 수 없습니다."
        case .invalidResponse:
            return "브이월드 Polygon 응답을 해석할 수 없습니다."
        case let .requestFailed(statusCode):
            return "브이월드 Polygon 요청이 실패했습니다. HTTP \(statusCode)"
        }
    }
}

private extension BuildingPolygon {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        rings.contains { ring in
            Self.ring(ring, contains: coordinate)
        }
    }

    private static func ring(_ ring: [CLLocationCoordinate2D], contains coordinate: CLLocationCoordinate2D) -> Bool {
        guard ring.count >= 3 else {
            return false
        }

        let pointX = coordinate.longitude
        let pointY = coordinate.latitude
        var isInside = false
        var previousIndex = ring.count - 1

        for currentIndex in ring.indices {
            let current = ring[currentIndex]
            let previous = ring[previousIndex]

            let currentX = current.longitude
            let currentY = current.latitude
            let previousX = previous.longitude
            let previousY = previous.latitude

            if pointIsOnSegment(
                pointX: pointX,
                pointY: pointY,
                startX: previousX,
                startY: previousY,
                endX: currentX,
                endY: currentY
            ) {
                return true
            }

            let intersects = (currentY > pointY) != (previousY > pointY)
                && pointX < (previousX - currentX) * (pointY - currentY) / (previousY - currentY) + currentX
            if intersects {
                isInside.toggle()
            }

            previousIndex = currentIndex
        }

        return isInside
    }

    private static func pointIsOnSegment(
        pointX: Double,
        pointY: Double,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double
    ) -> Bool {
        let epsilon = 0.000000001
        let crossProduct = (pointY - startY) * (endX - startX) - (pointX - startX) * (endY - startY)
        guard abs(crossProduct) <= epsilon else {
            return false
        }

        let minX = min(startX, endX) - epsilon
        let maxX = max(startX, endX) + epsilon
        let minY = min(startY, endY) - epsilon
        let maxY = max(startY, endY) + epsilon
        return pointX >= minX && pointX <= maxX && pointY >= minY && pointY <= maxY
    }

    func distanceFromCentroid(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        guard let centroid else {
            return .greatestFiniteMagnitude
        }
        return CLLocation(latitude: centroid.latitude, longitude: centroid.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    var centroidDescription: String {
        guard let centroid else {
            return "없음"
        }
        return "\(centroid.latitude), \(centroid.longitude)"
    }

    var coordinateListDescription: String {
        rings
            .flatMap { $0 }
            .map { "\($0.latitude),\($0.longitude)" }
            .joined(separator: " | ")
    }
}

private extension String {
    var isUsableAPIKey: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}
