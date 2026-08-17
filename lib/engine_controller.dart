import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SnackBarAction;
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import 'format.dart';
import 'library_store.dart';
import 'messenger.dart';
import 'native_bridge.dart';
import 'settings_store.dart';

/// Pausing a torrent aborts in-flight tracker announces and DHT lookups, so
/// the first nudge waits until the swarm has had a fair chance.
const firstReannounceAfter = Duration(seconds: 45);

/// How often we force a fresh announce after that, while metadata is missing.
const reannounceEvery = Duration(seconds: 60);

/// Nudging forever guarantees metadata limbo. Stop after this many tries.
const maxReannounces = 4;

/// How long we tolerate zero peers before telling the user the truth.
const peerWatchdog = Duration(seconds: 60);

/// Appended to every magnet so peer discovery never depends on the engine's
/// remote tracker-list download succeeding.
const fallbackTrackers = <String>[
  // Keep HTTP(S) entries in addition to UDP. Some mobile networks allow web
  // traffic but drop UDP tracker/DHT packets, which otherwise leaves every
  // magnet stuck at zero peers.
  'https://tracker.zhuqiy.com:443/announce',
  'https://tracker.yemekyedim.com:443/announce',
  'https://tracker.pmman.tech:443/announce',
  'https://tracker.bt4g.com:443/announce',
  'http://tracker2.dler.org:80/announce',
  'http://tracker.dler.org:6969/announce',
  'http://tracker.bt4g.com:2095/announce',
  'http://tracker.bittor.pw:1337/announce',
  'http://tr.nyacat.pw:80/announce',
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://open.tracker.cl:1337/announce',
  'udp://open.demonii.com:1337/announce',
  'udp://tracker.torrent.eu.org:451/announce',
  'udp://exodus.desync.com:6969/announce',
  'udp://explodie.org:6969/announce',
  'udp://tracker.dler.org:6969/announce',
  'udp://tracker.openbittorrent.com:6969/announce',
  'http://tracker.opentrackr.org:1337/announce',
];

final _videoExtensions = RegExp(
  r'\.(mp4|mkv|avi|mov|m4v|webm|flv|wmv|mpg|mpeg|ts|m2ts|3gp|ogv|divx|vob)$',
  caseSensitive: false,
);
final _audioExtensions = RegExp(
  r'\.(mp3|m4a|aac|flac|wav|ogg|opus|mka|wma)$',
  caseSensitive: false,
);
final _subtitleExtensions = RegExp(
  r'\.(srt|ass|ssa|vtt|sub|idx)$',
  caseSensitive: false,
);

/// Native log lines worth keeping. Everything else is Flutter framework noise.
const _nativeLogKeywords = <String>[
  'libtorrent',
  'tracker',
  'dht',
  'peer',
  'metadata',
  'listen',
  'socket',
  'port',
  'torrent',
  'stream',
  'mpv',
  'codec',
];

bool isVideoFile(String name) => _videoExtensions.hasMatch(name);

bool isAudioFile(String name) => _audioExtensions.hasMatch(name);

bool isSubtitleFile(String name) => _subtitleExtensions.hasMatch(name);

/// Trusting only [FileInfo.isStreamable] used to hide every file, so fall back
/// to the extension.
bool isPlayableFile(FileInfo file) =>
    file.isStreamable || isVideoFile(file.name) || isAudioFile(file.name);

String fileNameOf(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  return parts.isEmpty ? path : parts.last;
}

String nameFromMagnet(String magnet) {
  final match =
      RegExp(r'(?:\?|&)dn=([^&]+)', caseSensitive: false).firstMatch(magnet);
  if (match == null) return 'Untitled magnet';
  try {
    final decoded = Uri.decodeComponent(match.group(1)!).replaceAll('+', ' ');
    return decoded.isEmpty ? 'Untitled magnet' : decoded;
  } catch (_) {
    return match.group(1)!;
  }
}

/// Native counters are -1 until the session has real data. Never show that.
int safeCount(int value) => value < 0 ? 0 : value;

String withFallbackTrackers(String magnet) {
  final existing = RegExp(r'[?&]tr=([^&]*)', caseSensitive: false)
      .allMatches(magnet)
      .map((match) {
    final raw = match.group(1) ?? '';
    try {
      return Uri.decodeComponent(raw).toLowerCase();
    } catch (_) {
      return raw.toLowerCase();
    }
  }).toSet();

  final buffer = StringBuffer(magnet);
  for (final tracker in fallbackTrackers) {
    if (existing.contains(tracker.toLowerCase())) continue;
    buffer.write('&tr=${Uri.encodeComponent(tracker)}');
  }
  return buffer.toString();
}

EngineController? _nativeLogTarget;

/// The engine and the player print their real failures and expose no API to
/// read them. `main` captures stdout in a Zone and forwards the lines here.
void logNativeLine(String line) => _nativeLogTarget?.logNative(line);

/// Owns the torrent session, the active stream and the player.
class EngineController extends ChangeNotifier {
  EngineController({required this.settings, required this.store});

  final SettingsStore settings;
  final LibraryStore store;

  LibtorrentFlutter? _engine;
  StreamSubscription<Map<int, TorrentInfo>>? _torrentSub;
  StreamSubscription<Map<int, StreamInfo>>? _streamSub;
  StreamSubscription<String>? _playerErrorSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _pollTimer;
  Timer? _positionTimer;
  Future<void>? _trackerWarmup;
  bool _disposed = false;

  bool ready = false;
  bool adding = false;
  bool buffering = false;
  bool bufferTimedOut = false;
  String status = '';
  String version = '—';
  String? error;

  final Map<int, TorrentInfo> torrents = <int, TorrentInfo>{};
  final Map<int, String> magnetOf = <int, String>{};
  final Map<int, String> nameOf = <int, String>{};
  final Map<int, List<FileInfo>> filesOf = <int, List<FileInfo>>{};
  final Map<int, DateTime> addedAt = <int, DateTime>{};
  final Map<int, DateTime> lastAnnounce = <int, DateTime>{};
  final Map<int, int> reannounces = <int, int>{};
  final Set<int> _autoStarted = <int>{};
  final Set<int> _loadingFiles = <int>{};
  final Set<String> _mutedErrors = <String>{};
  final List<String> logLines = <String>[];

  /// How many native alerts we have folded in. Proves capture is working even
  /// when every line is filtered out as noise.
  int nativeAlerts = 0;

  int? activeTorrentId;
  StreamInfo? stream;
  StreamInfo? subtitleStream;
  StreamInfo? audioStream;
  FileInfo? playingFile;
  Player? player;
  VideoController? videoController;

  TorrentInfo? get activeTorrent =>
      activeTorrentId == null ? null : torrents[activeTorrentId];

  String? get activeMagnet =>
      activeTorrentId == null ? null : magnetOf[activeTorrentId];

  String get activeName {
    final id = activeTorrentId;
    if (id == null) return 'magnet';
    final stored = nameOf[id];
    if (stored != null && stored.isNotEmpty) return stored;
    final torrent = torrents[id];
    if (torrent != null && torrent.name.isNotEmpty) return torrent.name;
    return 'Magnet';
  }

  List<FileInfo> get activeFiles =>
      filesOf[activeTorrentId] ?? const <FileInfo>[];

  List<FileInfo> get playableFiles =>
      activeFiles.where(isPlayableFile).toList();

  List<FileInfo> get subtitleFiles =>
      activeFiles.where((file) => isSubtitleFile(file.name)).toList();

  List<FileInfo> get externalAudioFiles =>
      activeFiles.where((file) => isAudioFile(file.name)).toList();

  bool get isPlaying => player != null && videoController != null;

  String get logText => logLines.reversed.join('\n');

  String stateLabelFor(int id) {
    final torrent = torrents[id];
    if (torrent == null) return 'Connecting';
    if (!torrent.hasMetadata) return 'Getting metadata';
    if (torrent.isPaused) return 'Paused';
    return torrent.state.label;
  }

  String waitedLabelFor(int? id) {
    final started = id == null ? null : addedAt[id];
    if (started == null) return '—';
    return fmtWait(DateTime.now().difference(started));
  }

  void _bump() {
    if (!_disposed) notifyListeners();
  }

  void _log(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    logLines.insert(0, '$stamp  $message');
    if (logLines.length > 200) logLines.removeLast();
  }

  /// Folds a captured stdout line into the log. Called from a Zone print
  /// handler, so it must never notify listeners (that could fire mid-build)
  /// and must never print, or it would recurse forever.
  void logNative(String line) {
    if (_disposed) return;
    var text = line.trim();
    if (text.isEmpty) return;

    final lower = text.toLowerCase();
    var relevant = false;
    for (final keyword in _nativeLogKeywords) {
      if (lower.contains(keyword)) {
        relevant = true;
        break;
      }
    }
    if (!relevant) return;

    nativeAlerts++;
    if (text.length > 300) text = '${text.substring(0, 300)}…';
    _log('native: ${text.replaceFirst('LibtorrentFlutter Alert: ', '')}');

    // A failed listen port explains "traffic but no peers" completely, so
    // promote it from a log line to a visible error.
    final failed = lower.contains('fail') || lower.contains('error');
    if (failed && lower.contains('listen') && error == null) {
      _fail('The engine could not open a listening port: $text');
    }
  }

  void _fail(String message) {
    if (_mutedErrors.contains(message)) return;
    error = message;
    _log(message);
  }

  void dismissError() {
    final current = error;
    if (current != null) _mutedErrors.add(current);
    error = null;
    _bump();
  }

  // ── Session ───────────────────────────────────────────────────

  Future<void> init() async {
    _nativeLogTarget = this;
    try {
      if (!LibtorrentFlutter.isInitialized) {
        await LibtorrentFlutter.init(
          // The package fetches trackers fire-and-forget. Warm them before
          // the first magnet is added so a fast first tap is not DHT-only.
          fetchTrackers: false,
          pollInterval: const Duration(milliseconds: 500),
        );
      }
      final engine = LibtorrentFlutter.instance;
      _engine = engine;
      _trackerWarmup = _warmTrackers();
      applySettings();

      try {
        version = engine.libraryVersion;
      } catch (_) {
        version = 'unavailable';
      }

      _torrentSub = engine.torrentUpdates.listen(_absorb);
      _streamSub = engine.streamUpdates.listen(_absorbStreams);
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

      ready = true;
      error = null;
      _log('Engine ready (libtorrent $version)');
    } catch (err) {
      ready = false;
      _fail('The torrent engine could not start: $err');
    }
    _bump();
  }

  Future<void> _warmTrackers() async {
    try {
      await TrackerManager.fetchBestTrackers().timeout(
        const Duration(seconds: 6),
      );
      _log('Tracker list ready');
    } catch (err) {
      // Built-in fallback trackers still work if the live list is unavailable.
      _log('Tracker list unavailable: $err');
    }
  }

  /// Starts from the engine's own defaults and overrides only what streaming
  /// needs, so no native default is silently reset.
  void applySettings() {
    final engine = _engine;
    if (engine == null) return;
    try {
      final defaults = engine.getDefaultConfig();
      engine.configureSession(
        defaults.copyWith(
          cacheSize: settings.cacheBytes,
          readerReadAhead: settings.readAheadPct,
          preloadCache: settings.preloadPct,
          connectionsLimit: settings.connections,
          torrentDisconnectTimeout: settings.disconnectTimeout,
          responsiveMode: true,
          disableDht: false,
          disableUpnp: false,
        ),
      );
      _log(
        'Session: ${settings.cacheMb}MB cache, preload ${settings.preloadPct}%, '
        'read-ahead ${settings.readAheadPct}%, ${settings.connections} conns',
      );
    } catch (err) {
      _log('configureSession failed: $err');
    }
  }

  void _tick() {
    final engine = _engine;
    if (engine == null) return;

    _absorb(engine.torrents);

    final streamId = stream?.id;
    if (streamId != null) {
      try {
        final info = engine.getStreamInfo(streamId);
        if (info != null) stream = info;
      } catch (_) {
        // The stream vanished between polls.
      }
    }

    _runWatchdogs();
    _bump();
  }

  /// The package only emits on `torrentUpdates` when its internal change check
  /// trips, and that check ignores `numSeeds`, so the poll above is the real
  /// source of truth. This just folds a snapshot in.
  void _absorb(Map<int, TorrentInfo> snapshot) {
    torrents
      ..clear()
      ..addAll(snapshot);

    for (final torrent in snapshot.values) {
      if (torrent.name.isNotEmpty) {
        final known = nameOf[torrent.id];
        if (known == null || known.startsWith('Untitled')) {
          nameOf[torrent.id] = torrent.name;
        }
      }
      if (torrent.errorMsg.isNotEmpty &&
          torrent.id == activeTorrentId &&
          error == null) {
        _fail('Torrent error: ${torrent.errorMsg}');
      }
      if (torrent.hasMetadata) _ensureFiles(torrent.id);
    }

    if (activeTorrentId == null && snapshot.isNotEmpty) {
      activeTorrentId = snapshot.keys.first;
    }
    _bump();
  }

  void _absorbStreams(Map<int, StreamInfo> snapshot) {
    final id = stream?.id;
    if (id != null && snapshot[id] != null) stream = snapshot[id];
    final subId = subtitleStream?.id;
    if (subId != null && snapshot[subId] != null) {
      subtitleStream = snapshot[subId];
    }
    final audioId = audioStream?.id;
    if (audioId != null && snapshot[audioId] != null) {
      audioStream = snapshot[audioId];
    }
    _bump();
  }

  /// Nudges a silent swarm while metadata is missing - sparingly - and says
  /// something honest when nobody ever answers.
  void _runWatchdogs() {
    final engine = _engine;
    if (engine == null) return;
    final now = DateTime.now();

    for (final torrent in torrents.values) {
      if (torrent.hasMetadata) continue;
      final started = addedAt[torrent.id];
      if (started == null) continue;

      final waited = now.difference(started);
      final peers = safeCount(torrent.numPeers);
      final nudges = reannounces[torrent.id] ?? 0;
      final last = lastAnnounce[torrent.id];
      final due = last == null
          ? waited > firstReannounceAfter
          : now.difference(last) > reannounceEvery;

      // Only nudge a torrent that has reached nobody at all. Once peers are
      // answering, metadata is already on its way and a pause would throw the
      // in-flight handshakes away.
      if (due && peers == 0 && nudges < maxReannounces) {
        lastAnnounce[torrent.id] = now;
        try {
          // Pause + resume forces a re-announce to every tracker and a fresh
          // DHT lookup.
          engine.pauseTorrent(torrent.id);
          engine.resumeTorrent(torrent.id);
          reannounces[torrent.id] = nudges + 1;
          _log('Re-announced ${torrent.id} (${nudges + 1}/$maxReannounces)');
        } catch (_) {
          // Torrent already gone.
        }
      }

      if (torrent.id == activeTorrentId &&
          waited > peerWatchdog &&
          peers == 0 &&
          error == null) {
        _fail(
          'No peers reachable after ${waited.inSeconds}s. The DHT is '
          'responding but nobody is sharing this info-hash with your '
          'connection. Try a different magnet, or switch to Wi-Fi — some '
          'mobile carriers block peer traffic.',
        );
      }
    }
  }

  // ── Torrents ──────────────────────────────────────────────────

  Future<void> addMagnet(String raw) async {
    final value = raw.trim();
    final lower = value.toLowerCase();
    if (!lower.startsWith('magnet:?') || !lower.contains('xt=urn:btih:')) {
      showMessage('That does not look like a magnet link.');
      return;
    }

    final engine = _engine;
    if (!ready || engine == null) {
      showMessage('The torrent engine is still starting.');
      return;
    }

    final liveIds = engine.torrents.keys.toSet();
    for (final entry in magnetOf.entries) {
      if (liveIds.contains(entry.key) &&
          infoHashOf(entry.value) == infoHashOf(value)) {
        select(entry.key);
        showMessage('Already in your torrents.');
        return;
      }
    }

    adding = true;
    error = null;
    bufferTimedOut = false;
    status = 'Joining the swarm…';
    _bump();

    try {
      final trackerWarmup = _trackerWarmup;
      if (trackerWarmup != null) await trackerWarmup;
      final uri = settings.injectTrackers ? withFallbackTrackers(value) : value;
      // Streaming is the only supported magnet mode. The third argument is
      // libtorrent_flutter's streamOnly flag; leaving it at its default makes
      // every magnet behave like a background download.
      final id = engine.addMagnet(uri, null, true);
      final name = nameFromMagnet(value);

      magnetOf[id] = value;
      nameOf[id] = name;
      addedAt[id] = DateTime.now();
      reannounces[id] = 0;
      activeTorrentId = id;
      adding = false;
      status = 'Looking for peers and metadata…';
      _log('Added stream-only torrent $id');
      _bump();

      await store.addHistory(
        MagnetEntry(
          uri: value,
          name: name,
          savedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (err) {
      adding = false;
      _fail('This magnet could not be added: $err');
      _bump();
    }
  }

  void select(int id) {
    activeTorrentId = id;
    error = null;
    _bump();
    _ensureFiles(id);
  }

  void togglePause(int id) {
    final engine = _engine;
    if (engine == null) return;
    try {
      if (torrents[id]?.isPaused == true) {
        engine.resumeTorrent(id);
        _log('Resumed $id');
      } else {
        engine.pauseTorrent(id);
        _log('Paused $id');
      }
    } catch (err) {
      showMessage('That torrent could not be updated: $err');
    }
    _bump();
  }

  Future<void> remove(int id, {bool deleteFiles = false}) async {
    if (id == activeTorrentId || id == stream?.torrentId) {
      await stopPlayback(quiet: true);
    }
    try {
      _engine?.removeTorrent(id, deleteFiles: deleteFiles);
      _log('Removed $id (deleteFiles: $deleteFiles)');
    } catch (err) {
      _log('removeTorrent failed: $err');
    }
    torrents.remove(id);
    filesOf.remove(id);
    magnetOf.remove(id);
    nameOf.remove(id);
    addedAt.remove(id);
    lastAnnounce.remove(id);
    reannounces.remove(id);
    _autoStarted.remove(id);
    if (activeTorrentId == id) {
      activeTorrentId = torrents.isEmpty ? null : torrents.keys.first;
    }
    _bump();
  }

  /// libtorrent can report metadata a moment before the file list is
  /// queryable, so retry briefly instead of leaving the screen empty.
  Future<void> _ensureFiles(int id) async {
    if (filesOf.containsKey(id)) {
      _maybeAutoStart(id);
      return;
    }
    if (_loadingFiles.contains(id)) return;
    final engine = _engine;
    if (engine == null) return;

    _loadingFiles.add(id);
    try {
      final files = await _waitForFiles(id);
      if (files.isNotEmpty) {
        _log('Torrent $id: ${files.length} file(s)');
        _bump();
        _maybeAutoStart(id);
        return;
      }
      _log('Torrent $id reported metadata but no files');
    } catch (err) {
      _log('File list failed for $id: $err');
    } finally {
      _loadingFiles.remove(id);
    }
  }

  Future<List<FileInfo>> _waitForFiles(
    int id, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final engine = _engine;
    if (engine == null) return const <FileInfo>[];
    final deadline = DateTime.now().add(timeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      try {
        final files = engine.getFiles(id);
        if (files.isNotEmpty) {
          filesOf[id] = files;
          return files;
        }
      } catch (_) {
        // Metadata may be visible one poll before the file storage is ready.
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return const <FileInfo>[];
  }

  FileInfo? _matchRecoveredFile(List<FileInfo> files, FileInfo requested) {
    for (final candidate in files) {
      if (candidate.index == requested.index &&
          candidate.name == requested.name) {
        return candidate;
      }
    }
    for (final candidate in files) {
      if (candidate.index == requested.index) return candidate;
    }
    for (final candidate in files) {
      if (candidate.name == requested.name) return candidate;
    }
    for (final candidate in files) {
      if (isPlayableFile(candidate)) return candidate;
    }
    return null;
  }

  Future<FileInfo?> _recoverDeadTorrent(int oldId, FileInfo requested) async {
    final engine = _engine;
    final magnet = magnetOf[oldId];
    if (engine == null || magnet == null) return null;

    _log('Torrent $oldId was removed with its stream; reconnecting');
    torrents.remove(oldId);
    filesOf.remove(oldId);
    magnetOf.remove(oldId);
    nameOf.remove(oldId);
    addedAt.remove(oldId);
    lastAnnounce.remove(oldId);
    reannounces.remove(oldId);
    _autoStarted.remove(oldId);

    try {
      final uri =
          settings.injectTrackers ? withFallbackTrackers(magnet) : magnet;
      final id = engine.addMagnet(uri, null, true);
      magnetOf[id] = magnet;
      nameOf[id] = nameFromMagnet(magnet);
      addedAt[id] = DateTime.now();
      reannounces[id] = 0;
      activeTorrentId = id;
      status = 'Reconnecting to the swarm…';
      _bump();

      final files = await _waitForFiles(
        id,
        timeout: settings.bufferTimeout,
      );
      final recovered = _matchRecoveredFile(files, requested);
      if (recovered == null) {
        _fail(
          'The torrent was reconnected, but its video metadata is not ready.',
        );
        _bump();
      }
      return recovered;
    } catch (err) {
      _fail('The torrent could not be reconnected: $err');
      _bump();
      return null;
    }
  }

  void _maybeAutoStart(int id) {
    if (!settings.autoPlay) return;
    if (_autoStarted.contains(id)) return;
    if (id != activeTorrentId) return;
    if (player != null || buffering) return;
    final best = bestFileFor(id);
    if (best == null) return;
    _autoStarted.add(id);
    startStream(best, torrentId: id);
  }

  FileInfo? bestFileFor(int id) {
    final videos = videoFilesFor(id);
    final files = filesOf[id] ?? const <FileInfo>[];
    final pool =
        videos.isNotEmpty ? videos : files.where(isPlayableFile).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.first;
  }

  List<FileInfo> videoFilesFor(int id) {
    final files = filesOf[id] ?? const <FileInfo>[];
    return files.where((file) => isVideoFile(file.name)).toList()
      ..sort((a, b) => b.size.compareTo(a.size));
  }

  // ── Streaming ─────────────────────────────────────────────────

  Future<void> startStream(FileInfo file, {int? torrentId}) async {
    var id = torrentId ?? activeTorrentId;
    var selectedFile = file;
    final engine = _engine;
    if (id == null || engine == null) return;

    // The native stream server cannot serve a file until metadata is present.
    // Keep accidental early calls from creating a URL that media_kit cannot
    // recognize (this also protects against stale UI taps during metadata).
    if (torrents[id]?.hasMetadata != true && !filesOf.containsKey(id)) {
      error =
          'Still getting torrent metadata. Playback will appear when a video is ready.';
      status = 'Waiting for video metadata…';
      _bump();
      return;
    }

    await stopPlayback(quiet: true);
    activeTorrentId = id;
    buffering = true;
    bufferTimedOut = false;
    error = null;
    playingFile = selectedFile;
    status = 'Opening ${fileNameOf(selectedFile.name)}…';
    _bump();

    try {
      if (torrents[id]?.isPaused == true) engine.resumeTorrent(id);

      late StreamInfo info;
      try {
        info = engine.startStream(
          id,
          fileIndex: selectedFile.index,
          maxCacheBytes: settings.cacheBytes,
        );
      } catch (err) {
        final lower = err.toString().toLowerCase();
        if (!lower.contains('torrent not found')) rethrow;
        final recovered = await _recoverDeadTorrent(id, selectedFile);
        if (recovered == null) {
          buffering = false;
          _bump();
          return;
        }
        id = activeTorrentId ?? id;
        selectedFile = recovered;
        playingFile = selectedFile;
        info = engine.startStream(
          id,
          fileIndex: selectedFile.index,
          maxCacheBytes: settings.cacheBytes,
        );
      }
      stream = info;
      status = 'Buffering the opening pieces…';
      _log('Stream ${info.id} started for file ${selectedFile.index}');
      _bump();

      try {
        engine.setCacheSettings(
          info.id,
          capacity: settings.cacheBytes,
          readAheadPct: settings.readAheadPct,
          connectionsLimit: settings.connections,
        );
      } catch (_) {
        // Reader tuning is optional.
      }

      try {
        engine.preloadStream(info.id, preloadBytes: settings.preloadBytes);
      } catch (_) {
        // Preload is an optimisation, not a requirement.
      }

      final playable = await _waitForPlayableBuffer(info.id);
      if (_disposed) return;
      if (!playable) {
        buffering = false;
        bufferTimedOut = true;
        _fail(
          'Not enough data arrived to start playback. This swarm may have no '
          'reachable seeds right now.',
        );
        _bump();
        return;
      }

      await openPlayer();
    } catch (err) {
      buffering = false;
      _fail('The stream could not start: $err');
      _bump();
    }
  }

  /// `StreamState.ready` means the engine hit its full preload target. libmpv
  /// only needs the container head, but a completed torrent piece is not the
  /// same thing as a playable HTTP response. Probe the actual local stream
  /// first; this also advances the native reader and makes readHead real.
  Future<bool> _waitForPlayableBuffer(int streamId) async {
    final engine = _engine;
    if (engine == null) return false;
    final start = DateTime.now();
    final deadline = start.add(settings.bufferTimeout);
    var nextProbe = DateTime.now();

    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) return false;
      StreamInfo? info;
      try {
        info = engine.getStreamInfo(streamId);
      } catch (_) {
        info = null;
      }

      if (info != null) {
        stream = info;
        _bump();
        if (info.streamState == StreamState.error) return false;
        final hasHead = info.bufferPieces > 0 || info.readHead > 0;
        final now = DateTime.now();
        if (hasHead && now.isAfter(nextProbe)) {
          nextProbe = now.add(const Duration(seconds: 3));
          final served = await _probePlayableHead(info);
          if (served) {
            final refreshed = engine.getStreamInfo(streamId);
            if (refreshed != null) {
              stream = refreshed;
              _bump();
            }
            if (stream?.streamState == StreamState.ready &&
                (stream?.readHead ?? 0) > 0) {
              return true;
            }
          }
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (stream?.id != streamId) return false;
    }
    return false;
  }

  Future<bool> _probePlayableHead(StreamInfo info) async {
    if (info.fileSize <= 0) return false;
    final probeBytes = info.fileSize < 65536 ? info.fileSize : 65536;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(info.url));
      request.headers
        ..set(HttpHeaders.rangeHeader, 'bytes=0-${probeBytes - 1}')
        ..set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(
            const Duration(seconds: 45),
          );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        _log('Stream probe returned HTTP ${response.statusCode}');
        return false;
      }

      var received = 0;
      await for (final chunk in response.timeout(
        const Duration(seconds: 20),
      )) {
        received += chunk.length;
        if (received >= probeBytes) break;
      }
      _log('Stream probe received ${fmtBytes(received)}');
      final minimum = probeBytes < 4096 ? probeBytes : 4096;
      return received >= minimum;
    } catch (err) {
      _log('Stream probe failed: $err');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> openPlayer() async {
    final info = stream;
    if (info == null) return;

    final instance = Player();
    final controller = VideoController(instance);
    final errorSub = instance.stream.error.listen((message) {
      if (message.isEmpty) return;
      _fail('Player reported: $message');
      _bump();
    });

    try {
      // Open the local HTTP stream only after the native stream has a usable
      // head. Explicitly call play as well so a platform backend that ignores
      // Media(..., play: true) still starts immediately.
      await instance.open(Media(info.url), play: true);
      await instance.play();
    } catch (err) {
      await errorSub.cancel();
      if (identical(player, instance)) {
        player = null;
        videoController = null;
        buffering = false;
      }
      await instance.dispose();
      _fail('Video player could not open this stream: $err');
      _bump();
      return;
    }

    // Publish the controller only after the media URL has opened and play was
    // requested. The stream screen uses this state transition to navigate to
    // fullscreen, so a failed open cannot leave a blank player route behind.
    player = instance;
    videoController = controller;
    buffering = false;
    bufferTimedOut = false;
    status = '';
    _playerErrorSub = errorSub;
    _bump();

    if (settings.backgroundService) {
      await NativeBridge.startService(
        activeName,
        'Streaming ${fileNameOf(playingFile?.name ?? '')}',
      );
    }

    _restorePosition(instance);
    _startPositionSaves();
  }

  void _restorePosition(Player instance) {
    if (!settings.resumePlayback) return;
    final uri = activeMagnet;
    final file = playingFile;
    if (uri == null || file == null) return;
    final saved = store.positionFor(uri, file.index);
    if (saved < 20) return;

    _durationSub?.cancel();
    _durationSub = instance.stream.duration.listen((total) {
      if (total.inSeconds <= 0) return;
      if (saved >= total.inSeconds - 30) return;
      _durationSub?.cancel();
      _durationSub = null;
      instance.seek(Duration(seconds: saved));
      showMessage(
        'Resumed at ${fmtClock(Duration(seconds: saved))}',
        action: SnackBarAction(
          label: 'Start over',
          onPressed: () => instance.seek(Duration.zero),
        ),
      );
    });
  }

  void _startPositionSaves() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final instance = player;
      final uri = activeMagnet;
      final file = playingFile;
      if (instance == null || uri == null || file == null) return;
      final seconds = instance.state.position.inSeconds;
      if (seconds > 10) store.remember(uri, file.index, seconds);
    });
  }

  Future<void> stopPlayback({bool quiet = false}) async {
    final engine = _engine;
    final instance = player;
    final uri = activeMagnet;
    final file = playingFile;

    if (instance != null && uri != null && file != null) {
      final seconds = instance.state.position.inSeconds;
      if (seconds > 10) await store.remember(uri, file.index, seconds);
    }

    _positionTimer?.cancel();
    _positionTimer = null;
    await _durationSub?.cancel();
    _durationSub = null;
    await _playerErrorSub?.cancel();
    _playerErrorSub = null;

    for (final id in <int?>{stream?.id, subtitleStream?.id, audioStream?.id}) {
      if (id == null) continue;
      try {
        engine?.stopStream(id);
      } catch (_) {
        // Already stopped.
      }
    }

    player = null;
    videoController = null;
    stream = null;
    subtitleStream = null;
    audioStream = null;
    playingFile = null;
    buffering = false;
    if (!quiet) status = '';
    await NativeBridge.stopService();
    _bump();
    await instance?.dispose();
  }

  Future<void> retryLastFile() async {
    final file = playingFile;
    if (file == null) return;
    bufferTimedOut = false;
    await startStream(file);
  }

  // ── Extra tracks and diagnostics ──────────────────────────────────

  Future<void> loadExternalSubtitle(FileInfo file) async {
    final instance = player;
    final id = activeTorrentId;
    final engine = _engine;
    if (instance == null || id == null || engine == null) return;
    try {
      final info = engine.startStream(
        id,
        fileIndex: file.index,
        maxCacheBytes: 16 * 1024 * 1024,
      );
      final previous = subtitleStream;
      if (previous != null) engine.stopStream(previous.id);
      subtitleStream = info;
      await instance.setSubtitleTrack(
        SubtitleTrack.uri(info.url, title: fileNameOf(file.name)),
      );
      _bump();
    } catch (err) {
      showMessage('That subtitle could not be loaded: $err');
    }
  }

  Future<void> loadExternalAudio(FileInfo file) async {
    final instance = player;
    final id = activeTorrentId;
    final engine = _engine;
    if (instance == null || id == null || engine == null) return;
    try {
      final info = engine.startStream(
        id,
        fileIndex: file.index,
        maxCacheBytes: 32 * 1024 * 1024,
      );
      final previous = audioStream;
      if (previous != null) engine.stopStream(previous.id);
      audioStream = info;
      await instance.setAudioTrack(
        AudioTrack.uri(info.url, title: fileNameOf(file.name)),
      );
      _bump();
    } catch (err) {
      showMessage('That audio track could not be loaded: $err');
    }
  }

  Future<void> openExternalPlayer() async {
    final info = stream;
    if (info == null) {
      showMessage('Start a stream first.');
      return;
    }
    final mime = isAudioFile(playingFile?.name ?? '') ? 'audio/*' : 'video/*';
    try {
      if (Platform.isAndroid) {
        final vlc = AndroidIntent(
          action: 'action_view',
          data: info.url,
          type: mime,
          package: 'org.videolan.vlc',
        );
        if (await vlc.canResolveActivity() == true) {
          await vlc.launch();
          return;
        }
        final chooser = AndroidIntent(
          action: 'action_view',
          data: info.url,
          type: mime,
        );
        await chooser.launchChooser('Open stream with');
        return;
      }
      await launchUrl(
        Uri.parse(info.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (err) {
      showMessage('No external player could open this stream: $err');
    }
  }

  /// Range-requests the engine's local HTTP server. Proves whether the native
  /// side is serving bytes, independently of the player.
  Future<void> probeStream() async {
    final info = stream;
    if (info == null) {
      showMessage('Start a stream first.');
      return;
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(info.url));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');
      final response = await request.close();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        if (received >= 65536) break;
      }
      final result =
          'Stream server answered ${response.statusCode} with ${fmtBytes(received)}.';
      _log(result);
      showMessage(result);
    } catch (err) {
      final result = 'Stream server unreachable: $err';
      _log(result);
      showMessage(result);
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _nativeLogTarget = null;
    _pollTimer?.cancel();
    _positionTimer?.cancel();
    _torrentSub?.cancel();
    _streamSub?.cancel();
    _playerErrorSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }
}
