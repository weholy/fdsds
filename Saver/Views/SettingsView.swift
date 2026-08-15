import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                defaultsSection
                storageSection
                appIconSection
                infoSection
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    var appearanceSection: some View {
        Section {
            Picker("Тема", selection: $settings.selectedTheme) {
                Text("Системная").tag("system")
                Text("Светлая").tag("light")
                Text("Тёмная").tag("dark")
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Label("Внешний вид", systemImage: "paintbrush.fill")
        }
    }

    var defaultsSection: some View {
        Section {
            HStack {
                Label("Качество по умолчанию", systemImage: "sparkles")
                Spacer()
                Picker("Качество", selection: $settings.defaultQuality) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .pickerStyle(.menu)
                .tint(.blue)
            }

            HStack {
                Label("Формат по умолчанию", systemImage: "film.fill")
                Spacer()
                Picker("Формат", selection: $settings.defaultFormat) {
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
                .tint(.blue)
            }

            Toggle(isOn: $settings.autoDownload) {
                Label("Авто-загрузка при вставке", systemImage: "bolt.fill")
            }
            .tint(.blue)
        } header: {
            Label("Параметры загрузки", systemImage: "slider.horizontal.3")
        }
    }

    var storageSection: some View {
        Section {
            Toggle(isOn: $settings.saveToPhotos) {
                Label("Сохранять в Галерею", systemImage: "photo.fill")
            }
            .tint(.blue)

            Toggle(isOn: $settings.saveToFiles) {
                Label("Сохранять в папку Saver", systemImage: "folder.fill")
            }
            .tint(.blue)

            HStack {
                Label("Параллельных загрузок", systemImage: "arrow.triangle.branch")
                Spacer()
                Stepper("\(settings.concurrentDownloads)", value: $settings.concurrentDownloads, in: 1...5)
            }
        } header: {
            Label("Хранилище", systemImage: "internaldrive.fill")
        }
    }

    var appIconSection: some View {
        Section {
            ForEach(AppIcon.allCases) { icon in
                AppIconRow(icon: icon, isSelected: settings.selectedAppIcon == icon)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.applyAppIcon(icon)
                        }
                    }
            }
        } header: {
            Label("Иконка приложения", systemImage: "app.fill")
        } footer: {
            Text("Иконка будет обновлена сразу после выбора")
                .font(.caption)
        }
    }

    var infoSection: some View {
        Section {
            Link(destination: URL(string: "https://t.me/seyats")!) {
                HStack(spacing: 14) {
                    Image("telegram-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telegram")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("t.me/seyats")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: URL(string: "https://github.com/seyats/saver")!) {
                HStack(spacing: 14) {
                    Image("github-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("github.com/seyats/saver")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Информация", systemImage: "info.circle.fill")
        } footer: {
            Text("Saver v1.0.0 · Swift + yt-dlp")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct AppIconRow: View {
    let icon: AppIcon
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(icon.previewAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

            Text(icon.displayName)
                .font(.body)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
    }
}
