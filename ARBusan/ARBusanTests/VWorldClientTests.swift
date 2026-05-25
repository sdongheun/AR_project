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
        XCTAssertEqual(polygon?.buildingName, "테스트 건물")
        XCTAssertEqual(polygon?.heightMeters, 14.5)
        XCTAssertEqual(polygon?.groundFloorCount, 4)
        XCTAssertEqual(polygon?.sourceProperties["buld_nm"], "테스트 건물")
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

    func testVWorldClientSelectsNearBoundaryPolygonWhenPOIIsWithinThreeMeters() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Self.nearBoundaryResponse, response)
        }

        let client = VWorldDataAPIClient(apiKey: "test-vworld-key", session: makeMockSession())
        let result = try await client.fetchBuildingPolygonWithDiagnostics(for: MockTourismSpots.gimhae[0])

        XCTAssertNotNil(result.polygon)
        XCTAssertTrue(result.logs.contains("브이월드 POI 포함 Polygon 개수: 0"))
        XCTAssertTrue(result.logs.contains("브이월드 선택 기준: POI 내부 포함 없음, 외곽 3m 이내 fallback"))
    }

    func testVWorldClientDoesNotAutoSelectBuildingCandidateBetweenThreeAndEightMeters() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Self.buildingCandidateOnlyResponse, response)
        }

        let client = VWorldDataAPIClient(apiKey: "test-vworld-key", session: makeMockSession())
        let result = try await client.fetchBuildingPolygonWithDiagnostics(for: MockTourismSpots.gimhae[0])

        XCTAssertNil(result.polygon)
        XCTAssertTrue(result.logs.contains("브이월드 POI 포함 Polygon 개수: 0"))
        XCTAssertTrue(result.logs.contains("브이월드 선택 기준: POI 내부 포함 없음, 외곽 3~8m 건물 후보. 자동 선택 보류"))
    }

    func testVWorldClientTreatsDistantPolygonAsPointOrAreaTourismSpot() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Self.distantPolygonResponse, response)
        }

        let client = VWorldDataAPIClient(apiKey: "test-vworld-key", session: makeMockSession())
        let result = try await client.fetchBuildingPolygonWithDiagnostics(for: MockTourismSpots.gimhae[0])

        XCTAssertNil(result.polygon)
        XCTAssertTrue(result.logs.contains("브이월드 POI 포함 Polygon 개수: 0"))
        XCTAssertTrue(result.logs.contains("브이월드 선택 기준: POI 내부 포함 없음, 비건물형/point 관광지로 처리"))
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

    func testBuildingHeightResolverUsesVWorldHeightFirst() {
        let polygon = makeTestPolygon(heightMeters: 18.5, groundFloorCount: 4)
        let resolvedHeight = BuildingHeightResolver().resolve(
            polygon: polygon,
            streetscapeMeshHeightMeters: 20
        )

        XCTAssertEqual(resolvedHeight.valueMeters, 18.5)
        XCTAssertEqual(resolvedHeight.source, .vworldHeight)
        XCTAssertEqual(resolvedHeight.confidence, .high)
    }

    func testBuildingHeightResolverUsesStreetscapeBeforeFloorEstimate() {
        let polygon = makeTestPolygon(heightMeters: nil, groundFloorCount: 7)
        let resolvedHeight = BuildingHeightResolver().resolve(
            polygon: polygon,
            streetscapeMeshHeightMeters: 22
        )

        XCTAssertEqual(resolvedHeight.valueMeters, 22)
        XCTAssertEqual(resolvedHeight.source, .streetscapeMesh)
        XCTAssertEqual(resolvedHeight.confidence, .medium)
    }

    func testBuildingHeightResolverEstimatesHeightFromFloorCount() {
        let polygon = makeTestPolygon(heightMeters: nil, groundFloorCount: 5)
        let resolvedHeight = BuildingHeightResolver().resolve(polygon: polygon)

        XCTAssertEqual(resolvedHeight.valueMeters, 16.5, accuracy: 0.001)
        XCTAssertEqual(resolvedHeight.source, .floorEstimate)
        XCTAssertEqual(resolvedHeight.confidence, .medium)
    }

    func testBuildingHeightResolverFallsBackToDefaultHeight() {
        let polygon = makeTestPolygon(heightMeters: nil, groundFloorCount: nil)
        let resolvedHeight = BuildingHeightResolver().resolve(polygon: polygon)

        XCTAssertEqual(resolvedHeight.valueMeters, 5)
        XCTAssertEqual(resolvedHeight.source, .defaultFallback)
        XCTAssertEqual(resolvedHeight.confidence, .low)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeTestPolygon(
        heightMeters: Double?,
        groundFloorCount: Int?
    ) -> BuildingPolygon {
        BuildingPolygon(
            spotID: "test-spot",
            rings: [[
                CLLocationCoordinate2D(latitude: 35.0, longitude: 128.0),
                CLLocationCoordinate2D(latitude: 35.0, longitude: 128.1),
                CLLocationCoordinate2D(latitude: 35.1, longitude: 128.1),
                CLLocationCoordinate2D(latitude: 35.1, longitude: 128.0),
                CLLocationCoordinate2D(latitude: 35.0, longitude: 128.0),
            ]],
            sourceLayer: "test",
            buildingName: "테스트 건물",
            heightMeters: heightMeters,
            groundFloorCount: groundFloorCount,
            sourceProperties: [:]
        )
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
                  "buld_nm": "테스트 건물",
                  "height": "14.5",
                  "gro_flo_co": "4"
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

    private static let nearBoundaryResponse = polygonResponse(
        minLongitude: 128.90301,
        minLatitude: 35.24640,
        maxLongitude: 128.90308,
        maxLatitude: 35.24652
    )

    private static let buildingCandidateOnlyResponse = polygonResponse(
        minLongitude: 128.90304,
        minLatitude: 35.24640,
        maxLongitude: 128.90312,
        maxLatitude: 35.24652
    )

    private static let distantPolygonResponse = polygonResponse(
        minLongitude: 128.90320,
        minLatitude: 35.24640,
        maxLongitude: 128.90330,
        maxLatitude: 35.24652
    )

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

    private static func polygonResponse(
        minLongitude: Double,
        minLatitude: Double,
        maxLongitude: Double,
        maxLatitude: Double
    ) -> Data {
        """
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
                          [\(minLongitude), \(minLatitude)],
                          [\(maxLongitude), \(minLatitude)],
                          [\(maxLongitude), \(maxLatitude)],
                          [\(minLongitude), \(maxLatitude)],
                          [\(minLongitude), \(minLatitude)]
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
    }
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
