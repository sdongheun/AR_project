import Foundation

struct APIKeys: Equatable {
    let tourAPI: String
    let vworld: String
    let googleARCore: String

    static let empty = APIKeys(tourAPI: "", vworld: "", googleARCore: "")

    var statuses: [APIKeyStatus] {
        [
            APIKeyStatus(name: "TourAPI", isConfigured: tourAPI.isConfiguredAPIKey),
            APIKeyStatus(name: "VWorld", isConfigured: vworld.isConfiguredAPIKey),
            APIKeyStatus(name: "Google ARCore", isConfigured: googleARCore.isConfiguredAPIKey),
        ]
    }
}

struct APIKeyStatus: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let isConfigured: Bool
}

enum APIKeyProvider {
    static func load(bundle: Bundle = .main) -> APIKeys {
        APIKeys(
            tourAPI: bundle.apiKey(for: "ARBUSAN_TOUR_API_KEY"),
            vworld: bundle.apiKey(for: "ARBUSAN_VWORLD_API_KEY"),
            googleARCore: bundle.apiKey(for: "ARBUSAN_GOOGLE_ARCORE_API_KEY")
        )
    }
}

private extension Bundle {
    func apiKey(for key: String) -> String {
        object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

private extension String {
    var isConfiguredAPIKey: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(") && !trimmed.contains("your_")
    }
}
