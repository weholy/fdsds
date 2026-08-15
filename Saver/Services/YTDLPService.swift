import Foundation
import Photos

#if os(macOS)
import AppKit
private typealias PlatformPasteboard = NSPasteboard
#endif

protocol YTDLPServiceProtocol {
    func fetchInfo(url: String) async throws -> MediaInfo
    func download(url: String, quality: VideoQuality, format: OutputFormat, onProgress: @escaping (Double) -> Void) async throws -> URL
    func cancel()
    func outputDirectory() -> URL
}

// MARK: - Cobalt API Models

private struct CobaltRequest: Encodable {
    let url: String
    let videoQuality: String
    let filenameStyle: String = "pretty"
    let downloadMode: String?
    
    init(url: String, quality: VideoQuality, format: OutputFormat) {
        self.url = url
        self.videoQuality = quality.ytdlpFormat.contains("best") ? "1080" : quality.ytdlpFormat.filter("0123456789".contains)
        self.downloadMode = format.isAudioOnly ? "audio" : nil
    }
}

private struct CobaltResponse: Decodable {
    let status: String
    let url: String?
    let filename: String?
    let picker: [CobaltPickerItem]?
    let error: CobaltError?
}

private struct CobaltPickerItem: Decodable {
    let url: String
    let type: String?
}

private struct CobaltError: Decodable {
    let code: String?
}

// MARK: - iOS Implementation (URLSession + Cobalt API)

#if !os(macOS)
class YTDLPService: ObservableObject, YTDLPServiceProtocol {
    static let shared = YTDLPService()
    
    private var downloadTask: URLSessionDownloadTask?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()
    
    private let cobaltAPI = "https://api.cobalt.tools/"
    
    var ytdlpPath: String { "yt-dlp" }
    var ffmpegPath: String { "ffmpeg" }
    
    func outputDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let saverDir = docs.appendingPathComponent("Saver", isDirectory: true)
        try? FileManager.default.createDirectory(at: saverDir, withIntermediateDirectories: true)
        return saverDir
    }
    
    func fetchInfo(url: String) async throws -> MediaInfo {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        
        let (data, _) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        
        let title = extractMetaContent(html: html, property: "og:title") ?? extractTitle(from: html) ?? "Video"
        let thumbnail = extractMetaContent(html: html, property: "og:image")
        let platform = detectPlatform(from: url)
        
        return MediaInfo(
            title: title,
            thumbnailURL: thumbnail,
            duration: nil,
            uploader: extractMetaContent(html: html, property: "og:site_name"),
            platform: platform,
            formats: ["mp4"],
            sourceURL: url
        )
    }
    
    func download(
        url: String,
        quality: VideoQuality,
        format: OutputFormat,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let cobaltReq = CobaltRequest(url: url, quality: quality, format: format)
        
        var request = URLRequest(url: URL(string: cobaltAPI)!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(cobaltReq)
        
        let (data, response) = try await session.data(for: request)
        
        guard let _ = response as? HTTPURLResponse else {
            throw SaverError.downloadFailed("No server response")
        }
        
        let cobaltResp = try JSONDecoder().decode(CobaltResponse.self, from: data)
        
        guard cobaltResp.status == "redirect" || cobaltResp.status == "tunnel" || cobaltResp.status == "stream" else {
            let errorMsg = cobaltResp.error?.code ?? "Could not get download URL"
            throw SaverError.downloadFailed(errorMsg)
        }
        
        let downloadURLStr: String
        if cobaltResp.status == "picker", let picker = cobaltResp.picker, !picker.isEmpty {
            downloadURLStr = picker[0].url
        } else if let respURL = cobaltResp.url {
            downloadURLStr = respURL
        } else {
            throw SaverError.downloadFailed("Empty download URL")
        }
        
        guard let downloadURL = URL(string: downloadURLStr) else {
            throw SaverError.downloadFailed("Invalid download URL")
        }
        
        let outputDir = outputDirectory()
        let ext = format.isAudioOnly ? format.rawValue.lowercased() : "mp4"
        let rawName = (cobaltResp.filename ?? "saver_video").trimmingCharacters(in: .whitespaces)
        let safeName = rawName.replacingOccurrences(of: "/", with: "_")
        let destURL = outputDir.appendingPathComponent(safeName + "." + ext)
        
        try? FileManager.default.removeItem(at: destURL)
        
        return try await downloadFile(from: downloadURL, to: destURL, onProgress: onProgress)
    }
    
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
    }
    
    private func downloadFile(from sourceURL: URL, to destURL: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.session.downloadTask(with: sourceURL) { tempURL, response, error in
                DispatchQueue.main.async { self.downloadTask = nil }
                
                if let error = error {
                    let nsErr = error as NSError
                    if nsErr.code == NSURLErrorCancelled {
                        continuation.resume(throwing: SaverError.downloadFailed("Cancelled"))
                    } else {
                        continuation.resume(throwing: SaverError.downloadFailed(error.localizedDescription))
                    }
                    return
                }
                
                guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    continuation.resume(throwing: SaverError.downloadFailed("Server error: \(code)"))
                    return
                }
                
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: SaverError.fileNotFound)
                    return
                }
                
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    continuation.resume(returning: destURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            let _ = task.progress.observe(\.fractionCompleted) { progress, _ in
                DispatchQueue.main.async { onProgress(progress.fractionCompleted) }
            }
            
            DispatchQueue.main.async { self.downloadTask = task }
            task.resume()
        }
    }
    
    // MARK: - Simple HTML Parsing (no regex with quotes)
    
    private func extractMetaContent(html: String, property: String) -> String? {
        let lowerHTML = html.lowercased()
        let lowerProp = property.lowercased()
        
        for attr in ["property", "name"] {
            let needle = attr + "=" + "\"" + lowerProp + "\""
            guard let tagStart = lowerHTML.range(of: needle) else { continue }
            let afterAttr = tagStart.upperBound
            guard let tagEnd = lowerHTML.range(of: ">", range: afterAttr..<lowerHTML.endIndex) else { continue }
            let tagContent = String(html[afterAttr..<tagEnd.upperBound])
            
            if let cStart = tagContent.range(of: "content=", options: String.CompareOptions.caseInsensitive) {
                var rest = String(tagContent[cStart.upperBound...]).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("\"") {
                    rest.removeFirst()
                    if let eq = rest.firstIndex(of: "\"") {
                        let val = String(rest[rest.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                        if !val.isEmpty { return val }
                    }
                } else if rest.hasPrefix("'") {
                    rest.removeFirst()
                    if let eq = rest.firstIndex(of: "'") {
                        let val = String(rest[rest.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                        if !val.isEmpty { return val }
                    }
                }
            }
        }
        return nil
    }
    
    private func extractTitle(from html: String) -> String? {
        guard let openTag = html.range(of: "<title", options: .caseInsensitive) else { return nil }
        let afterOpen = openTag.upperBound
        guard let closeBracket = html.range(of: ">", range: afterOpen..<html.endIndex) else { return nil }
        let afterBracket = closeBracket.upperBound
        guard let closeTag = html.range(of: "</title>", options: String.CompareOptions.caseInsensitive, range: afterBracket..<html.endIndex) else { return nil }
        return String(html[afterBracket..<closeTag.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func detectPlatform(from url: String) -> String? {
        let lower = url.lowercased()
        if lower.contains("tiktok.com") { return "TikTok" }
        if lower.contains("youtube.com") || lower.contains("youtu.be") { return "YouTube" }
        if lower.contains("instagram.com") { return "Instagram" }
        if lower.contains("twitter.com") || lower.contains("x.com") { return "Twitter/X" }
        if lower.contains("vk.com") { return "VK" }
        if lower.contains("reddit.com") { return "Reddit" }
        if lower.contains("pinterest.") { return "Pinterest" }
        if lower.contains("twitch.tv") { return "Twitch" }
        return nil
    }
}
#endif

// MARK: - macOS Implementation (Process + yt-dlp)

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
                    let parts = line.components(separatedBy: CharacterSet(charactersIn: "\""))
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
                    let msg = String(data: errData, encoding: .utf8) ?? "Download error"
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
            title: dict["title"] as? String ?? "Untitled",
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
#endif

// MARK: - Shared Error Types

enum SaverError: LocalizedError {
    case downloadFailed(String)
    case invalidResponse
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return msg
        case .invalidResponse: return "Failed to get media info"
        case .fileNotFound: return "File not found after download"
        }
    }
}
