import SwiftUI

struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Загрузка", systemImage: "arrow.down.circle")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(1)
        }
        .tint(.primary)
    }
}
