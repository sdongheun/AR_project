import SwiftData
import SwiftUI

@main
struct ARBusanApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ARExploreView()
                .environmentObject(appState)
        }
        .modelContainer(for: TourismSpotEntity.self)
    }
}

