import SwiftUI

struct HomeView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var settings: AppSettings
    @State private var showSaveOptions = false
    @State private var showFormatPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    URLInputCard()

                    if downloadManager.state == .fetching {
                        FetchingIndicator()
                    }

                    if let info = downloadManager.mediaInfo {
                        MediaPreviewCard(info: info)
                        FormatSelectorCard()
                        DownloadButton(showSaveOptions: $showSaveOptions)
                    }

                    if case .downloading(let progress) = downloadManager.state {
                        DownloadProgressCard(progress: progress)
                    }

                    if case .completed(let url) = downloadManager.state {
                        CompletedCard(fileURL: url, showSaveOptions: $showSaveOptions)
                    }

                    if case .failed(let msg) = downloadManager.state {
                        ErrorCard(message: msg)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Saver")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .confirmationDialog("Сохранить как", isPresented: $showSaveOptions, titleVisibility: .visible) {
                if let url = downloadManager.downloadedFileURL {
                    Button("Сохранить в Галерею") {
                        Task { await downloadManager.saveToGallery() }
                    }
                    ShareLink(item: url) {
                        Text("Открыть в Файлах / Поделиться")
                    }
                } else {
                    Button("Скачать") {
                        Task { await downloadManager.startDownload() }
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .onAppear {
            downloadManager.applyDefaultSettings(from: settings)
        }
    }
}

struct URLInputCard: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("Вставьте ссылку...", text: $downloadManager.urlInput)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .padding(.leading, 16)
                .padding(.vertical, 14)

            Divider()
                .frame(height: 28)
                .padding(.horizontal, 8)

            Button {
                if let str = UIPasteboard.general.string {
                    downloadManager.urlInput = str
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Button {
                isFocused = false
                Task { await downloadManager.fetchInfo() }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.primary)
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(downloadManager.urlInput.isEmpty)
            .padding(.trailing, 8)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct FetchingIndicator: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.secondary)
            Text("Получаем информацию...")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MediaPreviewCard: View {
    let info: MediaInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thumbURL = info.thumbnailURL, let url = URL(string: thumbURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray5))
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay(
                            Image(systemName: "play.rectangle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(info.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 16) {
                    if let uploader = info.uploader {
                        Label(uploader, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let duration = info.duration {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let platform = info.platform {
                        Label(platform, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct FormatSelectorCard: View {
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Параметры")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                selectorRow(
                    title: "Качество",
                    icon: "star",
                    value: downloadManager.selectedQuality.rawValue
                ) {
                    Picker("Качество", selection: $downloadManager.selectedQuality) {
                        ForEach(VideoQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }

                Divider().padding(.leading, 44)

                selectorRow(
                    title: "Формат",
                    icon: "film",
                    value: downloadManager.selectedFormat.rawValue
                ) {
                    Picker("Формат", selection: $downloadManager.selectedFormat) {
                        Section("Видео") {
                            ForEach(OutputFormat.allCases.filter { !$0.isAudioOnly }) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        Section("Аудио") {
                            ForEach(OutputFormat.allCases.filter { $0.isAudioOnly }) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
    }

    @ViewBuilder
    func selectorRow<T: View>(title: String, icon: String, value: String, @ViewBuilder picker: () -> T) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(title)
                .font(.body)
            Spacer()
            picker()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct DownloadButton: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @Binding var showSaveOptions: Bool

    var body: some View {
        Button {
            Task { await downloadManager.startDownload() }
        } label: {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                Text("Скачать")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [Color(.label), Color(.secondaryLabel)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct DownloadProgressCard: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.primary)
                Text("Загрузка...")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            }

            ProgressView(value: progress)
                .tint(.primary)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct CompletedCard: View {
    let fileURL: URL
    @Binding var showSaveOptions: Bool
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Готово")
                        .font(.headline)
                    Text(fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    Task { await downloadManager.saveToGallery() }
                } label: {
                    Label("Галерея", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.primary)
                }

                ShareLink(item: fileURL) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.primary)
                }

                Button {
                    downloadManager.reset()
                } label: {
                    Label("Новый", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct ErrorCard: View {
    let message: String
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ошибка")
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                downloadManager.state = .idle
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
