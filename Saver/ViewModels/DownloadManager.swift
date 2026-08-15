import SwiftUI
import Combine

@MainActor
class DownloadManager: ObservableObject {
    @Published var urlInput: String = ""
    @Published var state: DownloadState = .idle
    @Published var mediaInfo: MediaInfo?
    @Published var selectedQuality: VideoQuality = .q1080
    @Published var selectedFormat: OutputFormat = .mp4
    @Published var downloadedFileURL: URL?
    @Published var showShareSheet = false
    @Published var errorMessage: String?

    private let service = YTDLPService.shared
    private let saveService = SaveService.shared

    func fetchInfo() async {
        guard !urlInput.isEmpty else { return }
        state = .fetching
        errorMessage = nil
        mediaInfo = nil

        do {
            let info = try await service.fetchInfo(url: urlInput)
            mediaInfo = info
            state = .ready
        } catch {
            state = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func startDownload() async {
        guard !urlInput.isEmpty else { return }
        state = .downloading(progress: 0)
        errorMessage = nil

        do {
            let url = try await service.download(
                url: urlInput,
                quality: selectedQuality,
                format: selectedFormat
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .downloading(progress: progress)
                }
            }
            downloadedFileURL = url
            state = .completed(url: url)
        } catch {
            state = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func saveToGallery() async {
        guard let url = downloadedFileURL else { return }
        do {
            try await saveService.saveToPhotoLibrary(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelDownload() {
        service.cancel()
        state = .idle
    }

    func reset() {
        state = .idle
        mediaInfo = nil
        downloadedFileURL = nil
        urlInput = ""
        errorMessage = nil
    }

    func applyDefaultSettings(from settings: AppSettings) {
        selectedQuality = settings.defaultQuality
        selectedFormat = settings.defaultFormat
    }
}
