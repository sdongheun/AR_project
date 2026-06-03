import CoreLocation
import Foundation

struct BuildingPolygon: Equatable {
    let spotID: TourismSpot.ID
    let rings: [[CLLocationCoordinate2D]]
    let sourceLayer: String
    let buildingName: String?
    let heightMeters: Double?
    let groundFloorCount: Int?
    let sourceProperties: [String: String]

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

enum BuildingHeightSource: String {
    case vworldHeight
    case streetscapeMesh
    case floorEstimate
    case defaultFallback

    var displayName: String {
        switch self {
        case .vworldHeight:
            return "브이월드 HEIGHT"
        case .streetscapeMesh:
            return "ARCore Streetscape Geometry"
        case .floorEstimate:
            return "브이월드 층수 추정"
        case .defaultFallback:
            return "기본값"
        }
    }
}

struct ResolvedBuildingHeight: Equatable {
    let valueMeters: Double
    let source: BuildingHeightSource
    let confidence: RecognitionConfidence
    let explanation: String

    var displayText: String {
        "\(String(format: "%.1f", valueMeters))m / \(source.displayName) / 신뢰도 \(confidence.displayName)"
    }
}

struct BuildingHeightResolver {
    private let averageFloorHeightMeters: Double
    private let defaultHeightMeters: Double

    init(averageFloorHeightMeters: Double = 3.3, defaultHeightMeters: Double = 5.0) {
        self.averageFloorHeightMeters = averageFloorHeightMeters
        self.defaultHeightMeters = defaultHeightMeters
    }

    func resolve(
        polygon: BuildingPolygon,
        streetscapeMeshHeightMeters: Double? = nil
    ) -> ResolvedBuildingHeight {
        if let heightMeters = polygon.heightMeters, heightMeters > 0 {
            return ResolvedBuildingHeight(
                valueMeters: heightMeters,
                source: .vworldHeight,
                confidence: .high,
                explanation: "브이월드가 제공한 실제 HEIGHT 값을 사용했습니다."
            )
        }

        if let streetscapeMeshHeightMeters, streetscapeMeshHeightMeters > 0 {
            return ResolvedBuildingHeight(
                valueMeters: streetscapeMeshHeightMeters,
                source: .streetscapeMesh,
                confidence: .medium,
                explanation: "ARCore Streetscape Geometry mesh 높이 범위를 사용했습니다."
            )
        }

        if let floorCount = polygon.groundFloorCount, floorCount > 0 {
            return ResolvedBuildingHeight(
                valueMeters: Double(floorCount) * averageFloorHeightMeters,
                source: .floorEstimate,
                confidence: .medium,
                explanation: "브이월드 지상층수 \(floorCount)층에 평균 층고 \(String(format: "%.1f", averageFloorHeightMeters))m를 곱해 추정했습니다."
            )
        }

        return ResolvedBuildingHeight(
            valueMeters: defaultHeightMeters,
            source: .defaultFallback,
            confidence: .low,
            explanation: "브이월드 높이/층수와 Streetscape Geometry 높이가 없어 기본 표시 높이를 사용했습니다."
        )
    }
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
            sourceLayer: "mock",
            buildingName: spot.name,
            heightMeters: nil,
            groundFloorCount: nil,
            sourceProperties: [:]
        )
    }
}

struct VWorldDataAPIClient: VWorldDiagnosticClient {
    private let apiKey: String
    private let session: URLSession
    private let buildingLayer = "LT_C_SPBD"
    private let searchHalfSizeDegrees = 0.00025
    private let nearBoundaryFallbackDistanceMeters: CLLocationDistance = 3
    private let buildingCandidateDistanceMeters: CLLocationDistance = 8

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
        if !containingPolygons.isEmpty {
            let containingIndexes = containingPolygons.compactMap { containingPolygon in
                parseResult.polygons.firstIndex(of: containingPolygon).map { "#\($0 + 1)" }
            }
            logs.append("브이월드 POI 포함 후보: \(containingIndexes.joined(separator: ", "))")
        }

        let polygon: BuildingPolygon?
        if let containingPolygon = containingPolygons.min(by: {
            $0.distanceFromCentroid(to: spot.center) < $1.distanceFromCentroid(to: spot.center)
        }) {
            polygon = containingPolygon
            logs.append("브이월드 선택 기준: POI가 Polygon 내부에 포함됨")
        } else {
            let nearestBoundaryCandidate = parseResult.polygons
                .map { polygon in
                    PolygonBoundaryCandidate(
                        polygon: polygon,
                        distanceMeters: polygon.distanceFromBoundary(to: spot.center)
                    )
                }
                .min { $0.distanceMeters < $1.distanceMeters }

            if let nearestBoundaryCandidate {
                logs.append("브이월드 POI-Polygon 외곽 최단 거리: \(String(format: "%.2f", nearestBoundaryCandidate.distanceMeters))m")
            }

            if let nearestBoundaryCandidate,
               nearestBoundaryCandidate.distanceMeters <= nearBoundaryFallbackDistanceMeters {
                polygon = nearestBoundaryCandidate.polygon
                logs.append("브이월드 선택 기준: POI 내부 포함 없음, 외곽 \(Int(nearBoundaryFallbackDistanceMeters))m 이내 fallback")
            } else {
                polygon = nil
                if let nearestBoundaryCandidate,
                   nearestBoundaryCandidate.distanceMeters <= buildingCandidateDistanceMeters {
                    logs.append("브이월드 선택 기준: POI 내부 포함 없음, 외곽 \(Int(nearBoundaryFallbackDistanceMeters))~\(Int(buildingCandidateDistanceMeters))m 건물 후보. 자동 선택 보류")
                } else {
                    logs.append("브이월드 선택 기준: POI 내부 포함 없음, 비건물형/point 관광지로 처리")
                }
            }
        }
        if let polygon {
            let selectedIndex = parseResult.polygons.firstIndex(of: polygon).map { "#\($0 + 1)" } ?? "#?"
            logs.append("브이월드 선택 Polygon \(selectedIndex): 외곽 좌표 \(polygon.vertexCount)개 / centroid \(polygon.centroid?.latitude ?? 0), \(polygon.centroid?.longitude ?? 0)")
            logs.append("브이월드 선택 Polygon 속성: \(polygon.attributeSummary)")
            let resolvedHeight = BuildingHeightResolver().resolve(polygon: polygon)
            logs.append("건물 높이 결정: \(resolvedHeight.displayText)")
            logs.append("건물 높이 결정 사유: \(resolvedHeight.explanation)")
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
            let properties = Self.normalizedProperties(from: feature["properties"])

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
                sourceLayer: buildingLayer,
                buildingName: Self.firstNonEmptyString(
                    in: properties,
                    keys: ["BLD_NM", "bld_nm", "BULD_NM", "buld_nm", "BULD_NM_DC", "buld_nm_dc", "BD_NM", "bd_nm"]
                ),
                heightMeters: Self.firstDouble(
                    in: properties,
                    keys: ["HEIGHT", "height", "HEIT", "heit", "BLD_HG", "bld_hg"]
                ),
                groundFloorCount: Self.firstInt(
                    in: properties,
                    keys: ["GRND_FLR", "grnd_flr", "GROUND_FLR", "ground_flr", "FLR", "flr", "GRO_FLO_CO", "gro_flo_co"]
                ),
                sourceProperties: properties
            )
        }
        logs.append("브이월드 파싱된 Polygon 개수: \(polygons.count)")
        for (index, polygon) in polygons.enumerated() {
            let candidateNumber = index + 1
            let containsPOI = polygon.contains(spotCenter)
            let centroidDistance = polygon.distanceFromCentroid(to: spotCenter)
            let boundaryDistance = polygon.distanceFromBoundary(to: spotCenter)
            logs.append("")
            logs.append("──── 브이월드 후보 Polygon #\(candidateNumber)/\(polygons.count) ────")
            logs.append("요약: POI 포함 \(containsPOI ? "예" : "아니오") / 외곽 좌표 \(polygon.vertexCount)개 / centroid \(polygon.centroidDescription)")
            logs.append("거리: centroid \(String(format: "%.1f", centroidDistance))m / 외곽 최단 \(String(format: "%.1f", boundaryDistance))m")
            logs.append("속성: \(polygon.attributeSummary)")
            logs.append("properties: \(polygon.propertiesDescription)")
            logs.append("좌표: \(polygon.coordinateListDescription)")
        }
        return VWorldPolygonParseResult(polygons: polygons, logs: logs)
    }

    private static func normalizedProperties(from value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else {
            return [:]
        }

        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = stringValue(from: pair.value)
        }
    }

    private static func stringValue(from value: Any) -> String {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value is NSNull {
            return ""
        }
        return "\(value)"
    }

    private static func firstNonEmptyString(in properties: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let value = properties[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func firstDouble(in properties: [String: String], keys: [String]) -> Double? {
        for key in keys {
            guard let value = properties[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            let normalizedValue = value.replacingOccurrences(of: ",", with: "")
            if let double = Double(normalizedValue) {
                return double
            }
        }
        return nil
    }

    private static func firstInt(in properties: [String: String], keys: [String]) -> Int? {
        for key in keys {
            guard let value = properties[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            let normalizedValue = value.replacingOccurrences(of: ",", with: "")
            if let int = Int(normalizedValue) {
                return int
            }
            if let double = Double(normalizedValue) {
                return Int(double)
            }
        }
        return nil
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

private struct PolygonBoundaryCandidate {
    let polygon: BuildingPolygon
    let distanceMeters: CLLocationDistance
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

    func distanceFromBoundary(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        rings
            .map { Self.distanceFromRingBoundary($0, to: coordinate) }
            .min() ?? .greatestFiniteMagnitude
    }

    private static func distanceFromRingBoundary(
        _ ring: [CLLocationCoordinate2D],
        to coordinate: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        guard ring.count >= 2 else {
            return .greatestFiniteMagnitude
        }

        var minDistance = CLLocationDistance.greatestFiniteMagnitude
        for index in 1..<ring.count {
            let distance = distanceFromCoordinate(
                coordinate,
                toSegmentStart: ring[index - 1],
                end: ring[index]
            )
            minDistance = min(minDistance, distance)
        }
        return minDistance
    }

    private static func distanceFromCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        toSegmentStart start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let metersPerLatitudeDegree = 111_320.0
        let metersPerLongitudeDegree = cos(coordinate.latitude * .pi / 180) * metersPerLatitudeDegree

        let pointX = coordinate.longitude * metersPerLongitudeDegree
        let pointY = coordinate.latitude * metersPerLatitudeDegree
        let startX = start.longitude * metersPerLongitudeDegree
        let startY = start.latitude * metersPerLatitudeDegree
        let endX = end.longitude * metersPerLongitudeDegree
        let endY = end.latitude * metersPerLatitudeDegree

        let segmentX = endX - startX
        let segmentY = endY - startY
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY
        guard segmentLengthSquared > 0 else {
            return hypot(pointX - startX, pointY - startY)
        }

        let rawProjection = ((pointX - startX) * segmentX + (pointY - startY) * segmentY) / segmentLengthSquared
        let projection = min(1, max(0, rawProjection))
        let projectedX = startX + projection * segmentX
        let projectedY = startY + projection * segmentY
        return hypot(pointX - projectedX, pointY - projectedY)
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

    var attributeSummary: String {
        let nameText = buildingName ?? "없음"
        let heightText = heightMeters.map { "\(String(format: "%.1f", $0))m" } ?? "없음"
        let floorText = groundFloorCount.map { "\($0)층" } ?? "없음"
        return "건물명 \(nameText) / 높이 \(heightText) / 지상층수 \(floorText)"
    }

    var propertiesDescription: String {
        guard !sourceProperties.isEmpty else {
            return "없음"
        }
        return sourceProperties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.isEmpty ? "빈 값" : $0.value)" }
            .joined(separator: " / ")
    }
}

private extension String {
    var isUsableAPIKey: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}
