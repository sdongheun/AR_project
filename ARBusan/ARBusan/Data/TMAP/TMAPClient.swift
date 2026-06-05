import CoreLocation
import Foundation

struct TMAPPedestrianRoute {
    let destinationName: String
    let requestedStart: CLLocationCoordinate2D
    let requestedDestination: CLLocationCoordinate2D
    let arrivalCoordinate: CLLocationCoordinate2D
    let routeCoordinates: [CLLocationCoordinate2D]
    let totalDistanceMeters: Double?
    let totalTimeSeconds: Double?
}

protocol TMAPClient {
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
            totalTimeSeconds: payload.totalTimeSeconds
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

        for feature in features {
            if let properties = feature["properties"] as? [String: Any] {
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
            totalTimeSeconds: totalTimeSeconds
        )
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
}

private extension Dictionary where Key == String, Value == Any {
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
}
