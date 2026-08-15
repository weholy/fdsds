import Foundation
import Photos
import SwiftUI

class SaveService {
    static let shared = SaveService()

    func saveToPhotoLibrary(url: URL) async throws {
        let authorized = await requestPhotoAccess()
        guard authorized else { throw SaverError.downloadFailed("Нет доступа к галерее") }

        try await PHPhotoLibrary.shared().performChanges {
            let ext = url.pathExtension.lowercased()
            if ["mp4", "mov", "mkv", "webm"].contains(ext) {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } else if ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        }
    }

    func saveToSaverFolder(url: URL) -> URL {
        return url
    }

    func shareFile(url: URL) -> URL {
        return url
    }

    private func requestPhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited { return true }
        if status == .notDetermined {
            let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return result == .authorized || result == .limited
        }
        return false
    }
}
