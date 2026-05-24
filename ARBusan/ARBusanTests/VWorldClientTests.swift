import CoreLocation
import XCTest
@testable import ARBusan

final class VWorldClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testVWorldClientParsesBuildingPolygonResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, "api.vworld.kr")
            XCTAssertEqual(components.path, "/req/data")
            XCTAssertEqual(queryItems["service"], "data")
            XCTAssertEqual(queryItems["request"], "GetFeature")
            XCTAssertEqual(queryItems["data"], "LT_C_SPBD")
            XCTAssertEqual(queryItems["geometry"], "true")
            XCTAssertEqual(queryItems["crs"], "EPSG:4326")
            XCTAssertEqual(queryItems["key"], "test-vworld-key")
            XCTAssertTrue(queryItems["geomFilter"]?.hasPrefix("BOX(") == true)
            XCTAssertEqual(
                queryItems["geomFilter"],
                "BOX(128.90282999999999,35.24615,128.90333,35.24665)"
            )

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Self.samplePolygonResponse, response)
        }

        let client = VWorldDataAPIClient(apiKey: "test-vworld-key", session: makeMockSession())
        let polygon = try await client.fetchBuildingPolygon(for: MockTourismSpots.gimhae[0])

        XCTAssertEqual(polygon?.spotID, "mock-gimhae-twosome-inje-192")
        XCTAssertEqual(polygon?.sourceLayer, "LT_C_SPBD")
        XCTAssertEqual(polygon?.vertexCount, 5)
        let firstCoordinate = try XCTUnwrap(polygon?.rings.first?.first)
        XCTAssertEqual(firstCoordinate.longitude, 128.90290, accuracy: 0.000001)
        XCTAssertEqual(firstCoordinate.latitude, 35.24640, accuracy: 0.000001)
    }

    func testVWorldClientReturnsNilWhenNoPolygonFeatureExists() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Self.emptyFeatureResponse, response)
        }

        let client = VWorldDataAPIClient(apiKey: "test-vworld-key", session: makeMockSession())
        let polygon = try await client.fetchBuildingPolygon(for: MockTourismSpots.gimhae[0])

        XCTAssertNil(polygon)
    }

    func testVWorldClientSelectsPolygonContainingPOIBeforeNearestCentroid() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Self.containingAndNearerCentroidResponse, response)
        }

        let client = VWorldDataAPIClient(apiKey: "test-vworld-key", session: makeMockSession())
        let result = try await client.fetchBuildingPolygonWithDiagnostics(for: MockTourismSpots.gimhae[0])

        let firstCoordinate = try XCTUnwrap(result.polygon?.rings.first?.first)
        XCTAssertEqual(firstCoordinate.longitude, 128.90250, accuracy: 0.000001)
        XCTAssertEqual(firstCoordinate.latitude, 35.24600, accuracy: 0.000001)
        XCTAssertTrue(result.logs.contains("브이월드 POI 포함 Polygon 개수: 1"))
        XCTAssertTrue(result.logs.contains("브이월드 선택 기준: POI가 Polygon 내부에 포함됨"))
    }

    func testVWorldClientRequiresConfiguredAPIKey() async {
        let client = VWorldDataAPIClient(apiKey: "", session: makeMockSession())

        do {
            _ = try await client.fetchBuildingPolygon(for: MockTourismSpots.gimhae[0])
            XCTFail("브이월드 키가 없으면 요청을 보내기 전에 실패해야 합니다.")
        } catch VWorldClientError.missingAPIKey {
            XCTAssertTrue(true)
        } catch {
            XCTFail("예상하지 못한 에러입니다: \(error)")
        }
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static let samplePolygonResponse = """
    {
      "response": {
        "status": "OK",
        "result": {
          "featureCollection": {
            "features": [
              {
                "type": "Feature",
                "geometry": {
                  "type": "Polygon",
                  "coordinates": [
                    [
                      [128.90290, 35.24640],
                      [128.90302, 35.24640],
                      [128.90302, 35.24652],
                      [128.90290, 35.24652],
                      [128.90290, 35.24640]
                    ]
                  ]
                },
                "properties": {
                  "buld_nm": "테스트 건물"
                }
              }
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!

    private static let containingAndNearerCentroidResponse = """
    {
      "response": {
        "status": "OK",
        "result": {
          "featureCollection": {
            "features": [
              {
                "type": "Feature",
                "geometry": {
                  "type": "Polygon",
                  "coordinates": [
                    [
                      [128.90299, 35.24644],
                      [128.90301, 35.24644],
                      [128.90301, 35.24646],
                      [128.90299, 35.24646],
                      [128.90299, 35.24644]
                    ]
                  ]
                }
              },
              {
                "type": "Feature",
                "geometry": {
                  "type": "Polygon",
                  "coordinates": [
                    [
                      [128.90250, 35.24600],
                      [128.90300, 35.24600],
                      [128.90300, 35.24700],
                      [128.90250, 35.24700],
                      [128.90250, 35.24600]
                    ]
                  ]
                }
              }
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!

    private static let emptyFeatureResponse = """
    {
      "response": {
        "status": "OK",
        "result": {
          "featureCollection": {
            "features": []
          }
        }
      }
    }
    """.data(using: .utf8)!
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
