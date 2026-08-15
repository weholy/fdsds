import SwiftUI

@main
struct SaverApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var downloadManager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(downloadManager)
                .preferredColorScheme(settings.colorScheme)
        }
    }
}
