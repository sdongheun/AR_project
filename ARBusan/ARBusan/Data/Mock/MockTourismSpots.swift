import CoreLocation
import Foundation

enum MockTourismSpots {
    static let gimhae: [TourismSpot] = [
        TourismSpot(
            id: "mock-gimhae-twosome-inje-192",
            name: "투썸플레이스",
            address: "경남 김해시 인제로 192",
            districtName: "김해시",
            category: "목업 상가",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.245758, longitude: 128.904074),
            recognitionHints: ["투썸", "투썸플레이스", "TWOSOME", "A TWOSOME PLACE"],
            notes: "간판이 잘 보이고 입구가 명확하다. 1층짜리 건물이며 상가는 2개만 있다."
        ),
        TourismSpot(
            id: "mock-gimhae-oliveyoung-inje-190",
            name: "올리브영",
            address: "경남 김해시 인제로 190",
            districtName: "김해시",
            category: "목업 상가",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.245555, longitude: 128.904186),
            recognitionHints: ["올리브영", "OLIVE YOUNG", "OLIVEYOUNG"],
            notes: "간판이 잘 보인다. 약 5층 건물이며 여러 상가가 존재한다."
        ),
        TourismSpot(
            id: "mock-gimhae-hoochamjal-inje-191",
            name: "후참잘",
            address: "경남 김해시 인제로 191",
            districtName: "김해시",
            category: "목업 상가",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.245678, longitude: 128.903683),
            recognitionHints: ["후참잘", "후라이드참잘하는집"],
            notes: "간판이 잘 보인다. 약 2층 건물이며 간판들이 빼곡하게 있다."
        ),
        TourismSpot(
            id: "mock-gimhae-thezone101-inje-266",
            name: "더존 101",
            address: "경상남도 김해시 인제로 266",
            districtName: "김해시",
            category: "목업 주택",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.252120, longitude: 128.903338),
            recognitionHints: ["더존 101", "더존101", "더존", "THEZONE101", "THE ZONE 101"],
            notes: "상업 건물이 아닌 주택이다. 약 4~5층 건물이며 실기기 테스트 위치 변경에 맞춰 추가했다."
        ),
    ]

    static let yongwon: [TourismSpot] = [
        TourismSpot(
            id: "mock-jinhae-yongwon-mcdonalds",
            name: "맥도날드 진해 용원",
            address: "좌표 기반 목업",
            districtName: "창원시 진해구",
            category: "목업 상가",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.101147, longitude: 128.810617),
            recognitionHints: ["맥도날드", "맥도날드 진해 용원", "McDonald", "McDonald's", "MCDONALD"],
            notes: "사용자가 제공한 진해 용원 테스트 좌표 기반 목업 건물이다."
        ),
        TourismSpot(
            id: "mock-jinhae-yongwon-lg-electronics",
            name: "LG전자 용원점",
            address: "좌표 기반 목업",
            districtName: "창원시 진해구",
            category: "목업 상가",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.101105, longitude: 128.810946),
            recognitionHints: ["LG전자", "LG 전자", "LG전자 용원점", "LG", "엘지전자"],
            notes: "사용자가 제공한 진해 용원 테스트 좌표 기반 목업 건물이다."
        ),
        TourismSpot(
            id: "mock-jinhae-yongwon-daiso",
            name: "다이소 용원점",
            address: "좌표 기반 목업",
            districtName: "창원시 진해구",
            category: "목업 상가",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.100603, longitude: 128.811471),
            recognitionHints: ["다이소", "다이소 용원점", "DAISO"],
            notes: "사용자가 제공한 진해 용원 테스트 좌표 기반 목업 건물이다."
        ),
        TourismSpot(
            id: "mock-jinhae-yongwon-meat-restaurant",
            name: "고기집",
            address: "좌표 기반 목업",
            districtName: "창원시 진해구",
            category: "목업 식당",
            source: .mock,
            geometryKind: .buildingPolygon,
            center: CLLocationCoordinate2D(latitude: 35.101033, longitude: 128.811171),
            recognitionHints: ["고기집", "고기", "식당"],
            notes: "사용자가 제공한 진해 용원 테스트 좌표 기반 목업 건물이다."
        ),
    ]

    static let testBuildings: [TourismSpot] = gimhae + yongwon
}
