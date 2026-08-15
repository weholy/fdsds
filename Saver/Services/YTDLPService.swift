import Foundation
import Photos

#if os(macOS)
import AppKit
private typealias PlatformPasteboard = NSPasteboard
#else
import UIKit
private typealias PlatformPasteboard = UIPasteboard
#endif

protocol YTDLPServiceProtocol {
    func fetchInfo(url: String) async throws -> MediaInfo
    func download(url: String, quality: VideoQuality, format: OutputFormat, onProgress: @escaping (Double) -> Void) async throws -> URL
    func cancel()
    func outputDirectory() -> URL
}

#if os(macOS)
class YTDLPService: ObservableObject, YTDLPServiceProtocol {
    static let shared = YTDLPService()
    private var activeProcess: Process?

    var ytdlpPath: String {
        if let bundled = Bundle.main.path(forResource: "yt-dlp", ofType: nil) {
            return bundled
        }
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "yt-dlp"
    }

    var ffmpegPath: String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "ffmpeg"
    }

    func outputDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let saverDir = docs.appendingPathComponent("Saver", isDirectory: true)
        try? FileManager.default.createDirectory(at: saverDir, withIntermediateDirectories: true)
        return saverDir
    }

    func fetchInfo(url: String) async throws -> MediaInfo {
        let args = [ytdlpPath, "--dump-json", "--no-playlist", url]
        let output = try await runProcess(args: args)
        return try parseMediaInfo(json: output, sourceURL: url)
    }

    func download(
        url: String,
        quality: VideoQuality,
        format: OutputFormat,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let outputDir = outputDirectory()
        let outputTemplate = outputDir.appendingPathComponent("%(title)s.%(ext)s").path

        var args = [ytdlpPath]
        args += ["--ffmpeg-location", ffmpegPath]
        args += ["-f", quality.ytdlpFormat]
        args += format.ytdlpArgs
        args += ["-o", outputTemplate]
        args += ["--no-playlist"]
        args += ["--newline"]
        args += [url]

        let outputURL = try await runDownloadProcess(args: args, outputDir: outputDir, onProgress: onProgress)
        return outputURL
    }

    func cancel() {
        activeProcess?.terminate()
        activeProcess = nil
    }

    private func runProcess(args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = Array(args.dropFirst())

            let pipe = Pipe()
            process.standardOutput = pipe
            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } else {
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: SaverError.downloadFailed(msg))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runDownloadProcess(
        args: [String],
        outputDir: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = Array(args.dropFirst())

            let pipe = Pipe()
            process.standardOutput = pipe
            let errPipe = Pipe()
            process.standardError = errPipe

            var downloadedFile: URL?

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard let line = String(data: data, encoding: .utf8) else { return }
                if let progress = self.parseProgress(line) {
                    DispatchQueue.main.async { onProgress(progress) }
                }
                if line.contains("[download] Destination:") || line.contains("Merging formats into") {
                    let parts = line.components(separatedBy: "\"")
                    if let path = parts.first(where: { $0.contains(outputDir.path) }) {
                        downloadedFile = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespaces))
                    }
                }
            }

            self.activeProcess = process

            do {
                try process.run()
                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    if let file = downloadedFile {
                        continuation.resume(returning: file)
                    } else {
                        let files = (try? FileManager.default.contentsOfDirectory(
                            at: outputDir, includingPropertiesForKeys: [.creationDateKey],
                            options: .skipsHiddenFiles
                        )) ?? []
                        let sorted = files.sorted {
                            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                            return d1 > d2
                        }
                        if let newest = sorted.first {
                            continuation.resume(returning: newest)
                        } else {
                            continuation.resume(throwing: SaverError.fileNotFound)
                        }
                    }
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "Ошибка загрузки"
                    continuation.resume(throwing: SaverError.downloadFailed(msg))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseProgress(_ line: String) -> Double? {
        guard line.contains("[download]"), line.contains("%") else { return nil }
        let parts = line.components(separatedBy: " ").filter { !$0.isEmpty }
        for part in parts {
            if part.hasSuffix("%"), let value = Double(part.dropLast()) {
                return value / 100.0
            }
        }
        return nil
    }

    private func parseMediaInfo(json: String, sourceURL: String) throws -> MediaInfo {
        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SaverError.invalidResponse
        }

        let formats = (dict["formats"] as? [[String: Any]])?.compactMap { $0["ext"] as? String } ?? []

        return MediaInfo(
            title: dict["title"] as? String ?? "Без названия",
            thumbnailURL: dict["thumbnail"] as? String,
            duration: formatDuration(dict["duration"] as? Double),
            uploader: dict["uploader"] as? String,
            platform: dict["extractor_key"] as? String,
            formats: Array(Set(formats)),
            sourceURL: sourceURL
        )
    }

    private func formatDuration(_ seconds: Double?) -> String? {
        guard let s = seconds else { return nil }
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}
#else
class YTDLPService: ObservableObject, YTDLPServiceProtocol {
    static let shared = YTDLPService()

    var ytdlpPath: String { "yt-dlp" }
    var ffmpegPath: String { "ffmpeg" }

    func outputDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let saverDir = docs.appendingPathComponent("Saver", isDirectory: true)
        try? FileManager.default.createDirectory(at: saverDir, withIntermediateDirectories: true)
        return saverDir
    }

    func fetchInfo(url: String) async throws -> MediaInfo {
        throw SaverError.downloadFailed("Запуск внешних процессов недоступен на iOS")
    }

    func download(
        url: String,
        quality: VideoQuality,
        format: OutputFormat,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        throw SaverError.downloadFailed("Запуск внешних процессов недоступен на iOS")
    }

    func cancel() {}
}
#endif

enum SaverError: LocalizedError {
    case downloadFailed(String)
    case invalidResponse
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return msg
        case .invalidResponse: return "Не удалось получить информацию о медиа"
        case .fileNotFound: return "Файл не найден после загрузки"
        }
    }
}
