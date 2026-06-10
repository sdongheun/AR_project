import CoreLocation
import Foundation

/// TMAP 보행자 경로 안내점(turnType) 종류. 회전 판정을 기하 각도가 아니라 TMAP 안내로 하기 위함.
enum TMAPManeuverKind: Equatable {
    case depart, arrive, straight
    case turnLeft, turnRight, slightLeft, slightRight, uTurn
    case crosswalk, overpass, underpass, stairs, other

    /// 화살표용 좌/우. 회전류가 아니면 nil.
    var turnDirection: RouteTurnDirection? {
        switch self {
        case .turnLeft, .slightLeft, .uTurn:
            return .left
        case .turnRight, .slightRight:
            return .right
        default:
            return nil
        }
    }

    /// 전방 3D 화살표를 띄울 회전류인지.
    var isTurn: Bool {
        turnDirection != nil
    }

    /// TMAP 보행자 turnType 코드 → 종류 매핑.
    static func from(turnType: Int) -> TMAPManeuverKind {
        switch turnType {
        case 11: return .straight
        case 12, 16: return .turnLeft     // 좌회전 / 8시 방향
        case 17: return .slightLeft       // 10시 방향
        case 13, 19: return .turnRight    // 우회전 / 4시 방향
        case 18: return .slightRight      // 2시 방향
        case 14: return .uTurn
        case 125: return .overpass        // 육교
        case 126: return .underpass       // 지하보도
        case 127, 128, 129: return .stairs // 계단/경사로
        case 200: return .depart
        case 201: return .arrive
        case 211...218: return .crosswalk  // 횡단보도류
        default: return .other
        }
    }
}

/// TMAP 경로의 개별 안내점(Point feature).
struct TMAPRouteManeuver {
    let coordinate: CLLocationCoordinate2D
    let turnType: Int
    let kind: TMAPManeuverKind
    let description: String
}

struct TMAPPedestrianRoute {
    let destinationName: String
    let requestedStart: CLLocationCoordinate2D
    let requestedDestination: CLLocationCoordinate2D
    let arrivalCoordinate: CLLocationCoordinate2D
    let routeCoordinates: [CLLocationCoordinate2D]
    let totalDistanceMeters: Double?
    let totalTimeSeconds: Double?
    /// TMAP 안내점 목록. POI fallback 경로 등에서는 비어 있을 수 있다.
    var maneuvers: [TMAPRouteManeuver] = []
}

struct TMAPPOISearchResult: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
}

protocol TMAPClient {
    func searchPOIs(
        keyword: String,
        near center: CLLocationCoordinate2D?
    ) async throws -> [TMAPPOISearchResult]

    func fetchPedestrianRoute(
        from start: CLLocationCoordinate2D,
        to destination: TourismSpot
    ) async throws -> TMAPPedestrianRoute
}

enum TMAPClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case requestFailed(Int)
    case emptySearchKeyword
    case missingArrivalCoordinate

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "TMAP API 키가 설정되지 않았습니다."
        case .invalidURL:
            return "TMAP 요청 URL을 만들 수 없습니다."
        case .invalidResponse:
            return "TMAP 응답을 해석할 수 없습니다."
        case let .requestFailed(statusCode):
            return "TMAP 요청이 실패했습니다. HTTP \(statusCode)"
        case .emptySearchKeyword:
            return "검색어를 입력해야 합니다."
        case .missingArrivalCoordinate:
            return "TMAP 응답에서 마지막 도착 좌표를 찾을 수 없습니다."
        }
    }
}

struct SKOpenAPITMAPClient: TMAPClient {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func searchPOIs(
        keyword: String,
        near center: CLLocationCoordinate2D?
    ) async throws -> [TMAPPOISearchResult] {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else {
            throw TMAPClientError.emptySearchKeyword
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TMAPClientError.missingAPIKey
        }
        guard let url = makePOISearchURL(keyword: trimmedKeyword, near: center) else {
            throw TMAPClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "appKey")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMAPClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TMAPClientError.requestFailed(httpResponse.statusCode)
        }

        return try parsePOISearchPayload(from: data)
    }

    func fetchPedestrianRoute(
        from start: CLLocationCoordinate2D,
        to destination: TourismSpot
    ) async throws -> TMAPPedestrianRoute {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TMAPClientError.missingAPIKey
        }
        guard let url = makeURL() else {
            throw TMAPClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "appKey")
        request.httpBody = try JSONSerialization.data(withJSONObject: makeBody(from: start, to: destination))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMAPClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TMAPClientError.requestFailed(httpResponse.statusCode)
        }

        let payload = try parsePayload(from: data)
        guard let arrivalCoordinate = payload.arrivalCoordinate else {
            throw TMAPClientError.missingArrivalCoordinate
        }

        return TMAPPedestrianRoute(
            destinationName: destination.name,
            requestedStart: start,
            requestedDestination: destination.center,
            arrivalCoordinate: arrivalCoordinate,
            routeCoordinates: payload.routeCoordinates,
            totalDistanceMeters: payload.totalDistanceMeters,
            totalTimeSeconds: payload.totalTimeSeconds,
            maneuvers: payload.maneuvers
        )
    }

    private func makeURL() -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "apis.openapi.sk.com"
        components.path = "/tmap/routes/pedestrian"
        components.queryItems = [
            URLQueryItem(name: "version", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }

    private func makePOISearchURL(keyword: String, near center: CLLocationCoordinate2D?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "apis.openapi.sk.com"
        components.path = "/tmap/pois"
        var queryItems = [
            URLQueryItem(name: "version", value: "1"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "searchKeyword", value: keyword),
            URLQueryItem(name: "resCoordType", value: "WGS84GEO"),
            URLQueryItem(name: "reqCoordType", value: "WGS84GEO"),
            URLQueryItem(name: "count", value: "10"),
        ]
        if let center {
            queryItems.append(URLQueryItem(name: "centerLat", value: String(center.latitude)))
            queryItems.append(URLQueryItem(name: "centerLon", value: String(center.longitude)))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func makeBody(from start: CLLocationCoordinate2D, to destination: TourismSpot) -> [String: Any] {
        [
            "startX": start.longitude,
            "startY": start.latitude,
            "endX": destination.center.longitude,
            "endY": destination.center.latitude,
            "startName": "ARBusan 현재 위치",
            "endName": destination.name,
            "reqCoordType": "WGS84GEO",
            "resCoordType": "WGS84GEO",
            "searchOption": "0",
            "sort": "index",
        ]
    }

    private func parsePayload(from data: Data) throws -> ParsedTMAPRoutePayload {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let features = dictionary["features"] as? [[String: Any]] else {
            throw TMAPClientError.invalidResponse
        }

        var arrivalCoordinate: CLLocationCoordinate2D?
        var routeCoordinates: [CLLocationCoordinate2D] = []
        var totalDistanceMeters: Double?
        var totalTimeSeconds: Double?
        var maneuvers: [TMAPRouteManeuver] = []

        for feature in features {
            let properties = feature["properties"] as? [String: Any]
            if let properties {
                totalDistanceMeters = totalDistanceMeters ?? properties.doubleValue(for: "totalDistance")
                totalTimeSeconds = totalTimeSeconds ?? properties.doubleValue(for: "totalTime")
            }

            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else {
                continue
            }

            if type == "Point",
               let coordinate = parseCoordinate(geometry["coordinates"]) {
                arrivalCoordinate = coordinate
                routeCoordinates.append(coordinate)
                if let turnType = properties?.intValue(for: "turnType") {
                    maneuvers.append(
                        TMAPRouteManeuver(
                            coordinate: coordinate,
                            turnType: turnType,
                            kind: TMAPManeuverKind.from(turnType: turnType),
                            description: properties?.stringValue(for: "description") ?? ""
                        )
                    )
                }
            } else if type == "LineString",
                      let coordinates = parseCoordinates(geometry["coordinates"]) {
                routeCoordinates.append(contentsOf: coordinates)
                if let last = coordinates.last {
                    arrivalCoordinate = last
                }
            }
        }

        return ParsedTMAPRoutePayload(
            arrivalCoordinate: arrivalCoordinate,
            routeCoordinates: routeCoordinates,
            totalDistanceMeters: totalDistanceMeters,
            totalTimeSeconds: totalTimeSeconds,
            maneuvers: maneuvers
        )
    }

    private func parsePOISearchPayload(from data: Data) throws -> [TMAPPOISearchResult] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let searchInfo = dictionary["searchPoiInfo"] as? [String: Any],
              let pois = searchInfo["pois"] as? [String: Any] else {
            throw TMAPClientError.invalidResponse
        }

        let rawPOIs: [[String: Any]]
        if let array = pois["poi"] as? [[String: Any]] {
            rawPOIs = array
        } else if let item = pois["poi"] as? [String: Any] {
            rawPOIs = [item]
        } else {
            rawPOIs = []
        }

        return rawPOIs.compactMap { poi in
            guard let name = poi.stringValue(for: "name"),
                  let coordinate = parsePOICoordinate(poi) else {
                return nil
            }

            let addressParts = [
                poi.stringValue(for: "upperAddrName"),
                poi.stringValue(for: "middleAddrName"),
                poi.stringValue(for: "lowerAddrName"),
                poi.stringValue(for: "detailAddrName"),
                poi.stringValue(for: "roadName"),
                poi.stringValue(for: "firstBuildNo"),
            ]
            let address = addressParts
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            let id = poi.stringValue(for: "id")
                ?? "\(name)-\(coordinate.latitude)-\(coordinate.longitude)"
            return TMAPPOISearchResult(
                id: id,
                name: name,
                address: address.isEmpty ? "주소 정보 없음" : address,
                coordinate: coordinate
            )
        }
    }

    private func parsePOICoordinate(_ poi: [String: Any]) -> CLLocationCoordinate2D? {
        let latitude = poi.doubleValue(for: "frontLat")
            ?? poi.doubleValue(for: "noorLat")
            ?? poi.doubleValue(for: "lat")
        let longitude = poi.doubleValue(for: "frontLon")
            ?? poi.doubleValue(for: "noorLon")
            ?? poi.doubleValue(for: "lon")
        guard let latitude, let longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func parseCoordinate(_ value: Any?) -> CLLocationCoordinate2D? {
        guard let values = value as? [Any], values.count >= 2,
              let longitude = values[0] as? Double,
              let latitude = values[1] as? Double else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func parseCoordinates(_ value: Any?) -> [CLLocationCoordinate2D]? {
        guard let values = value as? [[Any]] else {
            return nil
        }
        return values.compactMap(parseCoordinate)
    }
}

private struct ParsedTMAPRoutePayload {
    let arrivalCoordinate: CLLocationCoordinate2D?
    let routeCoordinates: [CLLocationCoordinate2D]
    let totalDistanceMeters: Double?
    let totalTimeSeconds: Double?
    let maneuvers: [TMAPRouteManeuver]
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(for key: String) -> String? {
        if let value = self[key] as? String {
            return value
        }
        if let value = self[key] as? Int {
            return String(value)
        }
        if let value = self[key] as? Double {
            return String(value)
        }
        return nil
    }

    func doubleValue(for key: String) -> Double? {
        if let value = self[key] as? Double {
            return value
        }
        if let value = self[key] as? Int {
            return Double(value)
        }
        if let value = self[key] as? String {
            return Double(value)
        }
        return nil
    }

    func intValue(for key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? Double {
            return Int(value)
        }
        if let value = self[key] as? String {
            return Int(value)
        }
        return nil
    }
}
