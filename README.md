# Saver

Приложение для скачивания видео, фото и аудио из любых социальных сетей — YouTube, Instagram, TikTok, Twitter/X, VK и других. Написано на Swift + SwiftUI для iOS и macOS.

## Технологии

- **Swift 5.9 / SwiftUI** — нативный UI с LiquidGlass (iOS 26 / macOS 26)
- **yt-dlp** — движок загрузки, запускается как системный процесс
- **PythonKit** — опциональная интеграция для расширенной логики
- **Photos framework** — сохранение в Галерею
- **Multiplatform** — один таргет, работает на iPhone, iPad и Mac

## Возможности

- Загрузка видео, фото и аудио по ссылке
- Выбор качества: от 240p до 4K
- Конвертация в MP3, AAC, WAV, FLAC и другие форматы
- Предпросмотр перед скачиванием
- Сохранение в Галерею или папку Saver в Files
- Смена иконки приложения (тёмная / светлая)
- Тёмная, светлая и системная тема

## Установка yt-dlp

```bash
brew install yt-dlp ffmpeg
```

Либо положите бинарник `yt-dlp` в папку проекта — приложение найдёт его автоматически.

## Сборка

1. Открыть `Saver.xcodeproj` в Xcode 16+
2. Добавить PythonKit через File → Add Package Dependencies → `https://github.com/pvieito/PythonKit`
3. Выбрать таргет и нажать Run

## Контакты

- Telegram: [@seyats](https://t.me/seyats)
- GitHub: [github.com/seyats/saver](https://github.com/seyats/saver)
