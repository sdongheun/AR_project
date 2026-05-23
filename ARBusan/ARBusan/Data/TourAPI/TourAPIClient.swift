import Foundation
import CoreLocation

protocol TourAPIClient {
    func fetchTourismSpots() async throws -> [TourismSpot]
}

enum TourAPIClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "TourAPI 키가 설정되지 않았습니다."
        case .invalidURL:
            return "TourAPI 요청 URL을 만들 수 없습니다."
        case .invalidResponse:
            return "TourAPI 응답을 해석할 수 없습니다."
        case let .requestFailed(statusCode):
            return "TourAPI 요청이 실패했습니다. HTTP \(statusCode)"
        }
    }
}

struct LocalGovernmentHubTourAPIClient: TourAPIClient {
    private let apiKey: String
    private let session: URLSession
    private let requests: [TourAPIAreaRequest]

    init(
        apiKey: String,
        session: URLSession = .shared,
        requests: [TourAPIAreaRequest] = [TourAPIAreaRequests.gimhae]
    ) {
        self.apiKey = apiKey
        self.session = session
        self.requests = requests
    }

    func fetchTourismSpots() async throws -> [TourismSpot] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TourAPIClientError.missingAPIKey
        }

        var spots: [TourismSpot] = []
        for request in requests {
            let data = try await fetchData(for: request)
            let items = try parseItems(from: data)
            spots.append(contentsOf: items.compactMap { item in
                TourismSpot(localGovernmentHubItem: item, request: request)
            })
        }
        return spots
    }

    private func fetchData(for request: TourAPIAreaRequest) async throws -> Data {
        guard let url = makeURL(for: request) else {
            throw TourAPIClientError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TourAPIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TourAPIClientError.requestFailed(httpResponse.statusCode)
        }
        return data
    }

    private func makeURL(for request: TourAPIAreaRequest) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "apis.data.go.kr"
        components.path = "/B551011/LocgoHubTarService1/areaBasedList1"
        components.queryItems = [
            URLQueryItem(name: "serviceKey", value: apiKey),
            URLQueryItem(name: "MobileOS", value: "IOS"),
            URLQueryItem(name: "MobileApp", value: "ARBusan"),
            URLQueryItem(name: "baseYm", value: request.baseYearMonth),
            URLQueryItem(name: "areaCd", value: request.areaCode),
            URLQueryItem(name: "signguCd", value: request.signguCode),
            URLQueryItem(name: "numOfRows", value: "100"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "_type", value: "json"),
        ]
        return components.url
    }

    private func parseItems(from data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let items = findTourAPIItems(in: object) else {
            throw TourAPIClientError.invalidResponse
        }
        return items
    }

    private func findTourAPIItems(in object: Any) -> [[String: Any]]? {
        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        if let item = dictionary["item"] {
            if let items = item as? [[String: Any]] {
                return items
            }
            if let item = item as? [String: Any] {
                return [item]
            }
        }

        for value in dictionary.values {
            if let items = findTourAPIItems(in: value) {
                return items
            }
        }

        return nil
    }
}

struct MockTourAPIClient: TourAPIClient {
    func fetchTourismSpots() async throws -> [TourismSpot] {
        MockTourismSpots.gimhae
    }
}

private extension TourismSpot {
    init?(localGovernmentHubItem item: [String: Any], request: TourAPIAreaRequest) {
        guard let name = item.stringValue(for: [
            "hubTatsNm",
            "hubTarNm",
            "hubTitle",
            "title",
            "tAtsNm",
            "trrsrtNm",
            "name",
        ]) else {
            return nil
        }

        guard let longitude = item.doubleValue(for: [
            "mapx",
            "mapX",
            "gpsX",
            "longitude",
            "lon",
            "lng",
            "x",
        ]), let latitude = item.doubleValue(for: [
            "mapy",
            "mapY",
            "gpsY",
            "latitude",
            "lat",
            "y",
        ]) else {
            return nil
        }

        let code = item.stringValue(for: [
            "hubTatsCd",
            "contentid",
            "contentId",
            "tAtsCd",
            "id",
        ]) ?? name

        let address = item.stringValue(for: [
            "addr1",
            "hubBsicAdres",
            "basicAddress",
            "adres",
            "address",
            "signguNm",
        ]) ?? request.districtDisplayName

        let category = item.stringValue(for: [
            "hubCtgryLclsNm",
            "hubCtgryMclsNm",
            "hubCtgrySclsNm",
            "cat1",
            "category",
        ]) ?? "TourAPI 중심 관광지"

        self.init(
            id: "tourapi-\(request.areaCode)-\(request.signguCode)-\(code)",
            name: name,
            address: address,
            districtName: request.signguName,
            category: category,
            source: .tourAPI,
            geometryKind: .point,
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            recognitionHints: [name],
            notes: "TourAPI 기초지자체 중심 관광지 정보에서 가져온 후보입니다."
        )
    }
}

private extension [String: Any] {
    func stringValue(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = self[key] as? CustomStringConvertible {
                let string = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !string.isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    func doubleValue(for keys: [String]) -> Double? {
        for key in keys {
            if let value = self[key] as? Double {
                return value
            }
            if let value = self[key] as? Int {
                return Double(value)
            }
            if let value = self[key] as? String,
               let double = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return double
            }
        }
        return nil
    }
}
