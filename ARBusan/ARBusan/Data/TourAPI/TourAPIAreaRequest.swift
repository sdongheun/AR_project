import Foundation

struct TourAPIAreaRequest: Hashable {
    let baseYearMonth: String
    let areaCode: String
    let areaName: String
    let signguCode: String
    let signguName: String

    var districtDisplayName: String {
        "\(areaName) \(signguName)"
    }
}

enum TourAPIAreaRequests {
    static let gimhae = TourAPIAreaRequest(
        baseYearMonth: "202504",
        areaCode: "48",
        areaName: "경상남도",
        signguCode: "48250",
        signguName: "김해시"
    )

    static let busan: [TourAPIAreaRequest] = [
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26110", signguName: "중구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26140", signguName: "서구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26170", signguName: "동구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26200", signguName: "영도구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26230", signguName: "부산진구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26260", signguName: "동래구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26290", signguName: "남구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26320", signguName: "북구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26350", signguName: "해운대구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26380", signguName: "사하구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26410", signguName: "금정구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26440", signguName: "강서구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26470", signguName: "연제구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26500", signguName: "수영구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26530", signguName: "사상구"),
        TourAPIAreaRequest(baseYearMonth: "202504", areaCode: "26", areaName: "부산광역시", signguCode: "26710", signguName: "기장군"),
    ]
}
