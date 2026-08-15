import SwiftUI
import Combine

enum VideoQuality: String, CaseIterable, Identifiable {
    case best = "Лучшее"
    case q2160 = "4K (2160p)"
    case q1440 = "1440p"
    case q1080 = "1080p"
    case q720 = "720p"
    case q480 = "480p"
    case q360 = "360p"
    case q240 = "240p"
    case worst = "Минимальное"

    var id: String { rawValue }

    var ytdlpFormat: String {
        switch self {
        case .best: return "bestvideo+bestaudio/best"
        case .q2160: return "bestvideo[height<=2160]+bestaudio/best[height<=2160]"
        case .q1440: return "bestvideo[height<=1440]+bestaudio/best[height<=1440]"
        case .q1080: return "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .q720: return "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .q480: return "bestvideo[height<=480]+bestaudio/best[height<=480]"
        case .q360: return "bestvideo[height<=360]+bestaudio/best[height<=360]"
        case .q240: return "bestvideo[height<=240]+bestaudio/best[height<=240]"
        case .worst: return "worstvideo+worstaudio/worst"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"
    case mkv = "MKV"
    case webm = "WebM"
    case mp3 = "MP3"
    case aac = "AAC"
    case wav = "WAV"
    case m4a = "M4A"
    case flac = "FLAC"
    case ogg = "OGG"

    var id: String { rawValue }
    var isAudioOnly: Bool { [.mp3, .aac, .wav, .m4a, .flac, .ogg].contains(self) }

    var ytdlpArgs: [String] {
        switch self {
        case .mp3: return ["--extract-audio", "--audio-format", "mp3"]
        case .aac: return ["--extract-audio", "--audio-format", "aac"]
        case .wav: return ["--extract-audio", "--audio-format", "wav"]
        case .m4a: return ["--extract-audio", "--audio-format", "m4a"]
        case .flac: return ["--extract-audio", "--audio-format", "flac"]
        case .ogg: return ["--extract-audio", "--audio-format", "vorbis"]
        case .mov: return ["--recode-video", "mov"]
        case .mkv: return ["--recode-video", "mkv"]
        case .webm: return ["--recode-video", "webm"]
        case .mp4: return ["--recode-video", "mp4"]
        }
    }
}

enum DownloadState: Equatable {
    case idle
    case fetching
    case ready
    case downloading(progress: Double)
    case completed(url: URL)
    case failed(message: String)
}

struct MediaInfo: Identifiable {
    let id = UUID()
    var title: String
    var thumbnailURL: String?
    var duration: String?
    var uploader: String?
    var platform: String?
    var formats: [String]
    var sourceURL: String
}

enum AppIcon: String, CaseIterable, Identifiable {
    case dark = "AppIconDark"
    case light = "AppIconLight"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .dark: return "Тёмный"
        case .light: return "Светлый"
        }
    }
    var previewAsset: String {
        switch self {
        case .dark: return "AppIconBlack"
        case .light: return "AppIconWhite"
        }
    }
    var alternateIconName: String? {
        switch self {
        case .dark: return nil
        case .light: return "AppIconLight"
        }
    }
}
