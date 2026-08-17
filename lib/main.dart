import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _ink = Color(0xFF07110E);
const _panel = Color(0xFF10221D);
const _panelRaised = Color(0xFF142B24);
const _line = Color(0xFF244138);
const _lime = Color(0xFFA9FF62);
const _muted = Color(0xFF8CA9A0);
const _danger = Color(0xFFFF8A6B);

/// Used so async code can show messages without touching a stale BuildContext.
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MagnetApp());
}

class MagnetApp extends StatelessWidget {
  const MagnetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _lime,
      brightness: Brightness.dark,
      surface: _ink,
    );

    return MaterialApp(
      title: 'magnet',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _ink,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: _panelRaised,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _lime, width: 1.4),
          ),
          hintStyle: const TextStyle(color: _muted),
        ),
        cardTheme: CardThemeData(
          color: _panel,
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: _line),
          ),
        ),
      ),
      home: const MagnetHomePage(),
    );
  }
}

class MagnetEntry {
  const MagnetEntry({
    required this.uri,
    required this.name,
    required this.savedAt,
  });

  final String uri;
  final String name;
  final int savedAt;

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        'savedAt': savedAt,
      };

  factory MagnetEntry.fromJson(Map<String, dynamic> json) => MagnetEntry(
        uri: json['uri'] as String? ?? '',
        name: json['name'] as String? ?? 'Magnet',
        savedAt: json['savedAt'] as int? ?? 0,
      );
}

class MagnetHomePage extends StatefulWidget {
  const MagnetHomePage({super.key});

  @override
  State<MagnetHomePage> createState() => _MagnetHomePageState();
}

class _MagnetHomePageState extends State<MagnetHomePage> {
  static const _savedKey = 'magnet.saved.v1';
  static const _historyKey = 'magnet.history.v1';

  /// RAM the native piece cache may use for a stream.
  static const _streamCacheBytes = 192 * 1024 * 1024;

  /// How long we wait for the swarm to fill the startup buffer.
  static const _bufferTimeout = Duration(seconds: 150);

  static final _videoExtensions = RegExp(
    r'\.(mp4|mkv|avi|mov|m4v|webm|flv|wmv|mpg|mpeg|ts|m2ts|3gp|ogv|divx|vob)$',
    caseSensitive: false,
  );
  static final _audioExtensions = RegExp(
    r'\.(mp3|m4a|aac|flac|wav|ogg|opus|mka|wma)$',
    caseSensitive: false,
  );
  static final _subtitleExtensions = RegExp(
    r'\.(srt|ass|ssa|vtt|sub|idx)$',
    caseSensitive: false,
  );

  final _magnetController = TextEditingController();

  LibtorrentFlutter? _engine;
  StreamSubscription<Map<int, TorrentInfo>>? _torrentSubscription;
  StreamSubscription<Map<int, StreamInfo>>? _streamSubscription;
  StreamSubscription<String>? _playerErrorSubscription;

  int? _torrentId;
  TorrentInfo? _torrent;
  String? _activeMagnet;
  String? _activeName;
  List<FileInfo> _files = [];
  bool _loadingFiles = false;
  int? _autoStartedTorrentId;

  StreamInfo? _stream;
  StreamInfo? _subtitleStream;
  StreamInfo? _audioStream;
  Player? _player;
  VideoController? _videoController;
  FileInfo? _playingFile;

  List<MagnetEntry> _savedMagnets = [];
  List<MagnetEntry> _history = [];
  int _selectedTab = 0;
  bool _engineReady = false;
  bool _isAdding = false;
  bool _isBuffering = false;
  bool _bufferTimedOut = false;
  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _initializeEngine();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _loadLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = _decodeEntries(prefs.getString(_savedKey));
      final history = _decodeEntries(prefs.getString(_historyKey));
      if (!mounted) return;
      setState(() {
        _savedMagnets = saved;
        _history = history;
      });
    } catch (_) {
      // A missing platform channel (tests, first run) must never block the UI.
    }
  }

  List<MagnetEntry> _decodeEntries(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MagnetEntry.fromJson)
          .where((entry) => entry.uri.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persistLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _savedKey,
        jsonEncode(_savedMagnets.map((entry) => entry.toJson()).toList()),
      );
      await prefs.setString(
        _historyKey,
        jsonEncode(_history.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Ignore storage failures; playback does not depend on them.
    }
  }

  // ── Engine ────────────────────────────────────────────────────────────────

  Future<void> _initializeEngine() async {
    try {
      if (!LibtorrentFlutter.isInitialized) {
        await LibtorrentFlutter.init(
          fetchTrackers: true,
          pollInterval: const Duration(milliseconds: 500),
        );
      }
      final engine = LibtorrentFlutter.instance;

      // Streaming needs a large reader cache, aggressive read-ahead and a
      // disconnect timeout long enough to survive slow metadata lookups.
      try {
        engine.configureSession(
          const BtConfig(
            cacheSize: _streamCacheBytes,
            readerReadAhead: 95,
            preloadCache: 50,
            connectionsLimit: 40,
            torrentDisconnectTimeout: 300,
            responsiveMode: true,
          ),
        );
      } catch (_) {
        // Tuning is best effort; defaults still stream.
      }

      _torrentSubscription = engine.torrentUpdates.listen(_handleTorrents);
      _streamSubscription = engine.streamUpdates.listen(_handleStreams);
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _engineReady = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _engineReady = false;
        _error = 'The torrent engine could not start: $error';
      });
    }
  }

  void _handleTorrents(Map<int, TorrentInfo> snapshot) {
    if (!mounted) return;
    final id = _torrentId;
    if (id == null) return;
    final torrent = snapshot[id];
    if (torrent == null) return;

    setState(() {
      _torrent = torrent;
      if (torrent.errorMsg.isNotEmpty) {
        _error = 'Torrent error: ${torrent.errorMsg}';
      }
      if ((_activeName == null || _activeName!.isEmpty) &&
          torrent.name.isNotEmpty) {
        _activeName = torrent.name;
      }
    });

    if (torrent.hasMetadata && _files.isEmpty && !_loadingFiles) {
      _loadFiles(id);
    }
  }

  void _handleStreams(Map<int, StreamInfo> snapshot) {
    if (!mounted) return;
    final streamId = _stream?.id;
    final subtitleId = _subtitleStream?.id;
    final audioId = _audioStream?.id;
    setState(() {
      if (streamId != null) _stream = snapshot[streamId] ?? _stream;
      if (subtitleId != null) {
        _subtitleStream = snapshot[subtitleId] ?? _subtitleStream;
      }
      if (audioId != null) _audioStream = snapshot[audioId] ?? _audioStream;
    });
  }

  /// libtorrent can report metadata a moment before the file list is queryable,
  /// so retry briefly instead of leaving the screen empty forever.
  Future<void> _loadFiles(int torrentId) async {
    final engine = _engine;
    if (engine == null) return;
    _loadingFiles = true;
    try {
      for (var attempt = 0; attempt < 8; attempt++) {
        final files = engine.getFiles(torrentId);
        if (files.isNotEmpty) {
          if (!mounted) return;
          setState(() => _files = files);
          _maybeAutoStart(torrentId, files);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted || _torrentId != torrentId) return;
      }
      if (!mounted) return;
      setState(() {
        _error = 'Metadata arrived but this torrent reported no files.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'The file list could not be read: $error');
    } finally {
      _loadingFiles = false;
    }
  }

  void _maybeAutoStart(int torrentId, List<FileInfo> files) {
    if (_autoStartedTorrentId == torrentId) return;
    if (_player != null || _isBuffering) return;
    final best = _bestFile(files);
    if (best == null) return;
    _autoStartedTorrentId = torrentId;
    _startStream(best);
  }

  // ── Magnet lifecycle ──────────────────────────────────────────────────────

  Future<void> _addMagnet([String? supplied]) async {
    final value = (supplied ?? _magnetController.text).trim();
    final lower = value.toLowerCase();
    if (!lower.startsWith('magnet:?') || !lower.contains('xt=urn:btih:')) {
      _showMessage('That does not look like a magnet link.');
      return;
    }
    final engine = _engine;
    if (!_engineReady || engine == null) {
      _showMessage('The torrent engine is still starting.');
      return;
    }

    setState(() {
      _isAdding = true;
      _error = null;
      _bufferTimedOut = false;
      _status = 'Joining the swarm…';
    });

    try {
      await _closePlayback();
      final previousId = _torrentId;
      if (previousId != null) {
        try {
          engine.disposeTorrent(previousId);
        } catch (_) {
          // Already gone.
        }
      }

      final id = engine.addMagnet(value);
      final name = _nameFromMagnet(value);
      final entry = MagnetEntry(
        uri: value,
        name: name,
        savedAt: DateTime.now().millisecondsSinceEpoch,
      );

      _magnetController.text = value;
      if (!mounted) return;
      setState(() {
        _torrentId = id;
        _torrent = null;
        _activeMagnet = value;
        _activeName = name;
        _files = [];
        _autoStartedTorrentId = null;
        _isAdding = false;
        _status = 'Looking for peers and metadata…';
      });

      _history = [
        entry,
        ..._history.where((item) => item.uri != value),
      ].take(50).toList();
      await _persistLibrary();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isAdding = false;
        _error = 'This magnet could not be added: $error';
      });
    }
  }

  Future<void> _closePlayback({bool updateUi = true}) async {
    final engine = _engine;
    final streamIds = <int>{
      if (_stream != null) _stream!.id,
      if (_subtitleStream != null) _subtitleStream!.id,
      if (_audioStream != null) _audioStream!.id,
    };
    for (final id in streamIds) {
      try {
        engine?.stopStream(id);
      } catch (_) {
        // Stream already stopped.
      }
    }

    await _playerErrorSubscription?.cancel();
    _playerErrorSubscription = null;

    final player = _player;
    _player = null;
    _videoController = null;
    _stream = null;
    _subtitleStream = null;
    _audioStream = null;
    _playingFile = null;
    _isBuffering = false;
    if (mounted && updateUi) setState(() {});
    await player?.dispose();
  }

  // ── Streaming ─────────────────────────────────────────────────────────────

  /// Starts a native stream, waits until the engine reports it is actually
  /// ready, and only then hands the local URL to the player. Opening the URL
  /// immediately is what made playback fail silently before.
  Future<void> _startStream(FileInfo file) async {
    final torrentId = _torrentId;
    final engine = _engine;
    if (torrentId == null || engine == null) return;

    await _closePlayback();
    if (!mounted) return;
    setState(() {
      _isBuffering = true;
      _bufferTimedOut = false;
      _error = null;
      _playingFile = file;
      _status = 'Opening ${_fileName(file.name)}…';
    });

    try {
      if (_torrent?.isPaused == true) {
        engine.resumeTorrent(torrentId);
      }

      final info = engine.startStream(
        torrentId,
        fileIndex: file.index,
        maxCacheBytes: _streamCacheBytes,
      );
      if (!mounted) return;
      setState(() {
        _stream = info;
        _status = 'Buffering the opening pieces…';
      });

      try {
        engine.preloadStream(info.id);
      } catch (_) {
        // Preload is an optimisation, not a requirement.
      }

      final ready = await _waitForStreamReady(info.id);
      if (!mounted) return;
      if (!ready) {
        setState(() {
          _isBuffering = false;
          _bufferTimedOut = true;
          _error = 'Not enough data arrived to start playback. This swarm may '
              'have no reachable seeds right now.';
        });
        return;
      }

      await _openPlayer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBuffering = false;
        _error = 'The stream could not start: $error';
      });
    }
  }

  Future<bool> _waitForStreamReady(int streamId) async {
    final engine = _engine;
    if (engine == null) return false;
    final deadline = DateTime.now().add(_bufferTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final info = engine.getStreamInfo(streamId);
      if (info != null) {
        if (mounted) setState(() => _stream = info);
        if (info.streamState == StreamState.ready) return true;
        if (info.streamState == StreamState.error) return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || _stream?.id != streamId) return false;
    }
    return false;
  }

  Future<void> _openPlayer() async {
    final stream = _stream;
    if (stream == null) return;

    final player = Player();
    final controller = VideoController(player);
    _playerErrorSubscription = player.stream.error.listen((message) {
      if (!mounted || message.isEmpty) return;
      setState(() => _error = 'Player reported: $message');
    });

    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _videoController = controller;
      _isBuffering = false;
      _bufferTimedOut = false;
      _status = '';
    });

    await player.open(Media(stream.url), play: true);
  }

  Future<void> _openExternalPlayer() async {
    final stream = _stream;
    if (stream == null) {
      _showMessage('Start a stream first.');
      return;
    }
    final mime = _isAudio(_playingFile?.name ?? '') ? 'audio/*' : 'video/*';

    try {
      if (Platform.isAndroid) {
        final vlc = AndroidIntent(
          action: 'action_view',
          data: stream.url,
          type: mime,
          package: 'org.videolan.vlc',
        );
        if (await vlc.canResolveActivity() == true) {
          await vlc.launch();
          return;
        }

        final chooser = AndroidIntent(
          action: 'action_view',
          data: stream.url,
          type: mime,
        );
        await chooser.launchChooser('Open stream with');
        return;
      }

      await launchUrl(
        Uri.parse(stream.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      _showMessage('No external player could open this stream: $error');
    }
  }

  Future<void> _loadExternalSubtitle(FileInfo file) async {
    final player = _player;
    final torrentId = _torrentId;
    final engine = _engine;
    if (player == null || torrentId == null || engine == null) return;
    try {
      final info = engine.startStream(
        torrentId,
        fileIndex: file.index,
        maxCacheBytes: 16 * 1024 * 1024,
      );
      final previous = _subtitleStream;
      if (previous != null) engine.stopStream(previous.id);
      _subtitleStream = info;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(info.url, title: _fileName(file.name)),
      );
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('That subtitle could not be loaded: $error');
    }
  }

  Future<void> _loadExternalAudio(FileInfo file) async {
    final player = _player;
    final torrentId = _torrentId;
    final engine = _engine;
    if (player == null || torrentId == null || engine == null) return;
    try {
      final info = engine.startStream(
        torrentId,
        fileIndex: file.index,
        maxCacheBytes: 32 * 1024 * 1024,
      );
      final previous = _audioStream;
      if (previous != null) engine.stopStream(previous.id);
      _audioStream = info;
      await player.setAudioTrack(
        AudioTrack.uri(info.url, title: _fileName(file.name)),
      );
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('That audio track could not be loaded: $error');
    }
  }

  // ── Library ───────────────────────────────────────────────────────────────

  Future<void> _toggleSavedCurrent() async {
    final uri = _activeMagnet;
    final name = _activeName;
    if (uri == null || name == null) return;
    final exists = _savedMagnets.any((entry) => entry.uri == uri);
    setState(() {
      if (exists) {
        _savedMagnets.removeWhere((entry) => entry.uri == uri);
      } else {
        _savedMagnets.insert(
          0,
          MagnetEntry(
            uri: uri,
            name: name,
            savedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    });
    await _persistLibrary();
  }

  Future<void> _toggleSaved(MagnetEntry entry) async {
    final exists = _savedMagnets.any((item) => item.uri == entry.uri);
    setState(() {
      if (exists) {
        _savedMagnets.removeWhere((item) => item.uri == entry.uri);
      } else {
        _savedMagnets.insert(0, entry);
      }
    });
    await _persistLibrary();
  }

  Future<void> _openEntry(MagnetEntry entry) async {
    _magnetController.text = entry.uri;
    setState(() => _selectedTab = 0);
    await _addMagnet(entry.uri);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showMessage(String message) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Native counters are -1 until the session has real data. Never show that.
  int _safe(int value) => value < 0 ? 0 : value;

  String _nameFromMagnet(String magnet) {
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

  String _fileName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  bool _isVideo(String name) => _videoExtensions.hasMatch(name);

  bool _isAudio(String name) => _audioExtensions.hasMatch(name);

  bool _isSubtitle(FileInfo file) => _subtitleExtensions.hasMatch(file.name);

  /// Trusting only [FileInfo.isStreamable] used to hide every file and leave a
  /// blank screen, so fall back to the extension.
  bool _isPlayable(FileInfo file) =>
      file.isStreamable || _isVideo(file.name) || _isAudio(file.name);

  List<FileInfo> get _playableFiles =>
      _files.where(_isPlayable).toList(growable: false);

  FileInfo? _bestFile(List<FileInfo> files) {
    final videos = files.where((file) => _isVideo(file.name)).toList();
    final pool = videos.isNotEmpty ? videos : files.where(_isPlayable).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.first;
  }

  String get _stateLabel {
    final torrent = _torrent;
    if (torrent == null) return 'Connecting';
    if (!torrent.hasMetadata) return 'Getting metadata';
    if (torrent.isPaused) return 'Paused';
    return torrent.state.label;
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _lime,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Text(
                'M',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 11),
            const Text(
              'magnet',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [_buildStatusPill()],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _selectedTab,
          children: [_buildStreamTab(), _buildLibraryTab()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        backgroundColor: _ink,
        indicatorColor: _lime.withValues(alpha: .18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Stream',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Library',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill() {
    final ready = _engineReady;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 9,
              color: ready ? _lime : Colors.orange,
            ),
            const SizedBox(width: 7),
            Text(
              ready ? 'engine ready' : 'starting',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamTab() {
    final hasTorrent = _torrentId != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const SizedBox(height: 8),
        const Text(
          'PLAY THE PIECES.',
          style: TextStyle(
            color: _lime,
            fontSize: 12,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Stream what's yours.",
          style: TextStyle(
            fontSize: 36,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Only use content you own or are authorized to access.',
          style: TextStyle(color: _muted, height: 1.45),
        ),
        const SizedBox(height: 22),
        _buildMagnetInput(),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _buildErrorCard(),
        ],
        if (!_engineReady) ...[
          const SizedBox(height: 14),
          _buildBusyCard('Starting the native torrent engine…'),
        ],
        if (_isAdding) ...[
          const SizedBox(height: 14),
          _buildBusyCard('Joining the swarm…'),
        ],
        if (hasTorrent) ...[
          const SizedBox(height: 16),
          _buildTorrentCard(),
          if (_isBuffering) ...[
            const SizedBox(height: 14),
            _buildBufferingCard(),
          ],
          if (_player != null && _videoController != null) ...[
            const SizedBox(height: 14),
            _buildPlayerCard(),
          ],
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildFileCard(),
          ],
          const SizedBox(height: 14),
          _buildDiagnostics(),
        ] else ...[
          const SizedBox(height: 16),
          _buildEmptyState(),
        ],
      ],
    );
  }

  Widget _buildMagnetInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _magnetController,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 13),
              onSubmitted: (_) => _addMagnet(),
              decoration: InputDecoration(
                hintText: 'Paste a magnet link',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text?.trim();
                    if (text == null || text.isEmpty) {
                      _showMessage('The clipboard is empty.');
                      return;
                    }
                    _magnetController.text = text;
                  },
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isAdding ? null : _addMagnet,
              icon: _isAdding
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(_isAdding ? 'Adding magnet…' : 'Start streaming'),
              style: FilledButton.styleFrom(
                backgroundColor: _lime,
                foregroundColor: _ink,
                minimumSize: const Size.fromHeight(54),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: const Color(0xFF2A1717),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 9, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: _danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: _danger, height: 1.35),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () => setState(() => _error = null),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            if (_bufferTimedOut)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () {
                        final file = _playingFile;
                        if (file != null) _startStream(file);
                      },
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _bufferTimedOut = false);
                        _openPlayer();
                      },
                      child: const Text('Play anyway'),
                    ),
                    TextButton(
                      onPressed: _openExternalPlayer,
                      child: const Text('Open in VLC'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyCard(String label) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTorrentCard() {
    final torrent = _torrent;
    final hasMetadata = torrent?.hasMetadata ?? false;
    final progress = (torrent?.progress ?? 0).clamp(0.0, 1.0);
    final saved = _savedMagnets.any((entry) => entry.uri == _activeMagnet);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stateLabel.toUpperCase(),
                        style: const TextStyle(
                          color: _lime,
                          letterSpacing: 1.5,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _activeName ?? 'Magnet',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: saved ? 'Remove from library' : 'Save magnet',
                  onPressed: _toggleSavedCurrent,
                  icon: Icon(
                    saved ? Icons.bookmark : Icons.bookmark_border,
                    color: _lime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _stat(
                    'Peers',
                    '${_safe(torrent?.numPeers ?? 0)}',
                    Icons.people_alt_outlined,
                  ),
                ),
                Expanded(
                  child: _stat(
                    'Seeds',
                    '${_safe(torrent?.numSeeds ?? 0)}',
                    Icons.cloud_outlined,
                  ),
                ),
                Expanded(
                  child: _stat(
                    'Down',
                    formatSpeed(_safe(torrent?.downloadRate ?? 0)),
                    Icons.arrow_downward_rounded,
                  ),
                ),
                Expanded(
                  child: _stat(
                    'Up',
                    formatSpeed(_safe(torrent?.uploadRate ?? 0)),
                    Icons.arrow_upward_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (hasMetadata) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: const Color(0xFF203C32),
                  color: _lime,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${formatBytes(_safe(torrent?.totalDone ?? 0))}'
                    ' of ${formatBytes(_safe(torrent?.totalWanted ?? 0))}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  Text(
                    torrent == null ? '' : 'ETA ${formatEta(torrent)}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ] else ...[
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  backgroundColor: Color(0xFF203C32),
                  color: _lime,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _status.isEmpty
                    ? 'Asking DHT and trackers for metadata…'
                    : _status,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _muted, size: 16),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    );
  }

  Widget _buildBufferingCard() {
    final stream = _stream;
    final buffer = stream?.bufferPct ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    _status.isEmpty ? 'Buffering…' : _status,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: buffer == 0 ? null : buffer,
                minHeight: 7,
                backgroundColor: const Color(0xFF203C32),
                color: _lime,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _stat(
                    'Buffer',
                    '${(buffer * 100).toStringAsFixed(0)}%',
                    Icons.speed_rounded,
                  ),
                ),
                Expanded(
                  child: _stat(
                    'Ahead',
                    '${(stream?.bufferSeconds ?? 0).toStringAsFixed(1)}s',
                    Icons.timer_outlined,
                  ),
                ),
                Expanded(
                  child: _stat(
                    'Stream peers',
                    '${_safe(stream?.activePeers ?? 0)}',
                    Icons.hub_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _closePlayback(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard() {
    final player = _player!;
    final subtitles = _files.where(_isSubtitle).toList();
    final externalAudio =
        _files.where((file) => _isAudio(file.name)).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ColoredBox(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: _videoController!),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _fileName(_playingFile?.name ?? 'Now playing'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Open in VLC or another player',
                  onPressed: _openExternalPlayer,
                  icon: const Icon(Icons.open_in_new_rounded, color: _lime),
                ),
                IconButton(
                  tooltip: 'Close player',
                  onPressed: () => _closePlayback(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          StreamBuilder<Tracks>(
            stream: player.stream.tracks,
            initialData: player.state.tracks,
            builder: (context, snapshot) {
              final tracks = snapshot.data;
              if (tracks == null) return const SizedBox.shrink();
              final hasAudioChoice = tracks.audio.length > 2;
              final hasSubtitleChoice = tracks.subtitle.length > 2;
              if (!hasAudioChoice &&
                  !hasSubtitleChoice &&
                  subtitles.isEmpty &&
                  externalAudio.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasAudioChoice) _audioMenu(player, tracks.audio),
                    if (hasSubtitleChoice)
                      _subtitleMenu(player, tracks.subtitle),
                    if (subtitles.isNotEmpty) _externalSubtitleMenu(subtitles),
                    if (externalAudio.isNotEmpty)
                      _externalAudioMenu(externalAudio),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _audioMenu(Player player, List<AudioTrack> tracks) {
    return PopupMenuButton<AudioTrack>(
      onSelected: player.setAudioTrack,
      itemBuilder: (context) => tracks
          .map(
            (track) => PopupMenuItem(
              value: track,
              child: Text(_trackLabel(track.id, track.title, track.language)),
            ),
          )
          .toList(),
      child: _chip(Icons.audiotrack_outlined, 'Audio'),
    );
  }

  Widget _subtitleMenu(Player player, List<SubtitleTrack> tracks) {
    return PopupMenuButton<SubtitleTrack>(
      onSelected: player.setSubtitleTrack,
      itemBuilder: (context) => tracks
          .map(
            (track) => PopupMenuItem(
              value: track,
              child: Text(_trackLabel(track.id, track.title, track.language)),
            ),
          )
          .toList(),
      child: _chip(Icons.closed_caption_outlined, 'Subtitles'),
    );
  }

  Widget _externalSubtitleMenu(List<FileInfo> files) {
    return PopupMenuButton<FileInfo>(
      onSelected: _loadExternalSubtitle,
      itemBuilder: (context) => files
          .map(
            (file) => PopupMenuItem(
              value: file,
              child: Text(
                _fileName(file.name),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      child: _chip(Icons.subtitles_outlined, 'External subs'),
    );
  }

  Widget _externalAudioMenu(List<FileInfo> files) {
    return PopupMenuButton<FileInfo>(
      onSelected: _loadExternalAudio,
      itemBuilder: (context) => files
          .map(
            (file) => PopupMenuItem(
              value: file,
              child: Text(
                _fileName(file.name),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      child: _chip(Icons.library_music_outlined, 'External audio'),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: _panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B4B3E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _lime),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _trackLabel(String id, String? title, String? language) {
    if (id == 'auto') return 'Automatic';
    if (id == 'no') return 'Off';
    return title ?? language ?? 'Track $id';
  }

  Widget _buildFileCard() {
    final playable = _playableFiles;
    final others = _files.where((file) => !_isPlayable(file)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FILES',
              style: TextStyle(
                color: _lime,
                letterSpacing: 1.5,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              playable.isEmpty
                  ? '${_files.length} file(s) found'
                  : 'Choose a file to play',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...playable.map(_fileTile),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${others.length} other file(s)',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                  children: others.map(_fileTile).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fileTile(FileInfo file) {
    final isPlaying = _playingFile?.index == file.index;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: _lime.withValues(alpha: .14),
        foregroundColor: _lime,
        child: Icon(
          _isAudio(file.name)
              ? Icons.music_note
              : _isVideo(file.name)
                  ? Icons.movie_outlined
                  : Icons.insert_drive_file_outlined,
        ),
      ),
      title: Text(
        _fileName(file.name),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.w800 : FontWeight.w500,
          color: isPlaying ? _lime : Colors.white,
        ),
      ),
      subtitle: Text(
        formatBytes(file.size),
        style: const TextStyle(color: _muted),
      ),
      trailing: _isBuffering && isPlaying
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: 'Play',
              onPressed: () => _startStream(file),
              icon: const Icon(Icons.play_arrow_rounded, color: _lime),
            ),
    );
  }

  Widget _buildDiagnostics() {
    final engine = _engine;
    final stream = _stream;
    String version;
    try {
      version = engine?.libraryVersion ?? 'not started';
    } catch (_) {
      version = 'unavailable';
    }

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.bug_report_outlined, color: _muted),
          title: const Text(
            'Diagnostics',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          children: [
            _diagnosticRow('libtorrent', version),
            _diagnosticRow('Torrent state', _stateLabel),
            _diagnosticRow(
              'Has metadata',
              '${_torrent?.hasMetadata ?? false}',
            ),
            _diagnosticRow('Files', '${_files.length}'),
            _diagnosticRow(
              'Stream state',
              stream == null ? 'no stream' : stream.streamState.name,
            ),
            if (stream != null) _diagnosticRow('Stream URL', stream.url),
            if (stream != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: stream.url),
                    );
                    _showMessage('Stream URL copied.');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy stream URL'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _diagnosticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(Icons.waves_rounded, color: _lime.withValues(alpha: .8),
                size: 38),
            const SizedBox(height: 10),
            const Text(
              'Ready when you are',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Paste an authorized magnet link. The largest video file starts '
              'playing automatically once metadata arrives.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      children: [
        const Text(
          'YOUR LIBRARY',
          style: TextStyle(
            color: _lime,
            letterSpacing: 2,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'Saved for later.',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Magnets stay on this device. Nothing is uploaded to a cloud account.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 24),
        _librarySection('Saved magnets', _savedMagnets, showBookmark: true),
        const SizedBox(height: 22),
        _librarySection('History', _history, showBookmark: false),
      ],
    );
  }

  Widget _librarySection(
    String title,
    List<MagnetEntry> entries, {
    required bool showBookmark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text('${entries.length}', style: const TextStyle(color: _muted)),
          ],
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                showBookmark
                    ? 'Saved magnets will appear here.'
                    : 'Played magnets will appear here.',
                style: const TextStyle(color: _muted),
              ),
            ),
          )
        else
          ...entries.map(
            (entry) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _openEntry(entry),
                leading: Icon(
                  showBookmark ? Icons.bookmark : Icons.history,
                  color: _lime,
                ),
                title: Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  entry.uri,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                trailing: IconButton(
                  tooltip: showBookmark ? 'Remove saved magnet' : 'Save magnet',
                  onPressed: () => _toggleSaved(entry),
                  icon: Icon(
                    showBookmark ? Icons.delete_outline : Icons.bookmark_border,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _magnetController.dispose();
    _torrentSubscription?.cancel();
    _streamSubscription?.cancel();
    _playerErrorSubscription?.cancel();
    _closePlayback(updateUi: false);
    super.dispose();
  }
}
