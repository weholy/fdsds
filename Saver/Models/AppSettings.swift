import SwiftUI
import Combine

class AppSettings: ObservableObject {
    @AppStorage("selectedTheme") var selectedTheme: String = "system"
    @AppStorage("defaultQuality") var defaultQualityRaw: String = VideoQuality.q1080.rawValue
    @AppStorage("defaultFormat") var defaultFormatRaw: String = OutputFormat.mp4.rawValue
    @AppStorage("saveToPhotos") var saveToPhotos: Bool = true
    @AppStorage("saveToFiles") var saveToFiles: Bool = true
    @AppStorage("selectedAppIcon") var selectedAppIconRaw: String = AppIcon.dark.rawValue
    @AppStorage("concurrentDownloads") var concurrentDownloads: Int = 2
    @AppStorage("autoDownload") var autoDownload: Bool = false

    var defaultQuality: VideoQuality {
        get { VideoQuality(rawValue: defaultQualityRaw) ?? .q1080 }
        set { defaultQualityRaw = newValue.rawValue }
    }

    var defaultFormat: OutputFormat {
        get { OutputFormat(rawValue: defaultFormatRaw) ?? .mp4 }
        set { defaultFormatRaw = newValue.rawValue }
    }

    var selectedAppIcon: AppIcon {
        get { AppIcon(rawValue: selectedAppIconRaw) ?? .dark }
        set { selectedAppIconRaw = newValue.rawValue }
    }

    var colorScheme: ColorScheme? {
        switch selectedTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    func applyAppIcon(_ icon: AppIcon) {
        selectedAppIcon = icon
        #if os(iOS)
        UIApplication.shared.setAlternateIconName(icon.alternateIconName)
        #endif
    }
}
