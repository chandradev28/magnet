# magnet

A native torrent streaming player for Android. Paste a magnet link and playback
starts as soon as the opening pieces arrive — there is no wait for the full
download.

## What it does

- **Instant streaming** — sequential piece selection with a head preload, so the
  player opens on the first playable bytes instead of waiting for the engine's
  full preload target.
- **Honest live stats** — peers, seeds, download and upload rates are polled once
  a second straight from the session, and negative sentinels are never shown.
- **Peer discovery that works** — extra public trackers are merged into every
  magnet, and a watchdog re-announces while metadata is still missing.
- **Real player** — fullscreen route with rotation, embedded and external audio
  and subtitle tracks, resume, and a live overlay of stream health.
- **Multiple torrents** — add several magnets, pause, resume, remove with or
  without deleting files.
- **Library** — saved magnets, recent history, and per-file resume positions.
- **Background downloads** — a foreground service keeps the swarm alive when the
  app is not in front.
- **Magnet link intake** — magnet links tapped in a browser or shared from
  another app open directly in the app.
- **Diagnostics** — stream state, read head, buffer pieces, re-announce count,
  the libtorrent version, a copyable session log, and a one-tap range request
  against the local stream server.

## Architecture

```
lib/
  main.dart              app entry, theme, MaterialApp
  app_state.dart         long lived singletons
  engine_controller.dart torrent session, streaming, player lifecycle
  settings_store.dart    persisted tuning
  library_store.dart     saved items, history, resume positions
  native_bridge.dart     method and event channels
  format.dart            byte, speed, duration formatting
  theme.dart             colours and Material theme
  messenger.dart         snack bars without a BuildContext
  widgets/ui.dart        shared building blocks
  screens/               stream, torrents, library, settings, player
android/app/src/main/kotlin/
  MainActivity.kt        magnet intent intake, channel wiring
  StreamService.kt       foreground service
```

Playback uses `media_kit` (libmpv) against the local HTTP server exposed by
`libtorrent_flutter`, which wraps libtorrent through FFI.

## Build

```bash
flutter pub get
flutter run                 # debug on a connected device
flutter build apk --release --split-per-abi -PlibtorrentFlutterAbis=arm64-v8a
```

CI builds an `arm64-v8a` release APK on every push and pull request and uploads
it as the `magnet-android-arm64` artifact. That APK is signed with the debug
key; swap in a real signing config before distributing it.

## Tuning

Everything in Settings maps to the session config. Preload and read-ahead are
percentages **of the cache**, so a big cache with a big preload target can
demand more data than a thin swarm will ever deliver. The defaults — 64 MB
cache, 10% preload, 40% read-ahead, 8 MB head preload, 12 s soft gate — are
tuned to start playback quickly on mobile connections.

If peers stay at zero on a known-good magnet, the swarm is unreachable rather
than the app being broken: some mobile carriers block peer traffic, so try
Wi-Fi.

## Legal

Only stream content you are authorised to access.
