# magnet

Minimal Flutter Android torrent streaming app for content you own or are authorized to access.

## What is included

- Native libtorrent engine with DHT, trackers, peers, metadata and file selection.
- HTTP range streaming into an in-app media_kit/libmpv player.
- Broad video/audio codec support with embedded and external subtitle/audio track selection.
- One-click VLC intent with a fallback chooser for other Android players.
- Device-local saved magnets and playback history.
- GitHub Actions release build for an arm64 Android APK.

## Build in GitHub Actions

Pushes to `main` and pull requests run `.github/workflows/android.yml`. The workflow runs formatting checks, static analysis, widget tests, and produces an arm64 release APK as a downloadable Actions artifact.

The first Android build downloads native libtorrent and libmpv binaries. This is expected and is cached by the workflow.

## Local development

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi -PlibtorrentFlutterAbis=arm64-v8a
```

The app uses the native torrent engine on Android, so regular TCP/DHT-only peers can work. The hosted browser preview is a separate WebRTC-only environment and has different peer limitations.

Use only magnets for lawful, authorized content.
