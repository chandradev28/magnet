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
const _lime = Color(0xFFA9FF62);
const _muted = Color(0xFF8CA9A0);

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
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _ink,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          elevation: 0,
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
            borderSide: const BorderSide(color: Color(0xFF244138)),
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
            side: const BorderSide(color: Color(0xFF244138)),
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

  final _magnetController = TextEditingController();
  final _scrollController = ScrollController();

  LibtorrentFlutter? _engine;
  StreamSubscription<Map<int, TorrentInfo>>? _torrentSubscription;
  StreamSubscription<Map<int, StreamInfo>>? _streamSubscription;

  Map<int, TorrentInfo> _torrents = {};
  int? _activeTorrentId;
  String? _activeMagnet;
  String? _activeName;
  List<FileInfo> _files = [];

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
  bool _isStartingStream = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _initializeEngine();
  }

  Future<void> _loadLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = _decodeEntries(prefs.getString(_savedKey));
    final history = _decodeEntries(prefs.getString(_historyKey));
    if (!mounted) return;
    setState(() {
      _savedMagnets = saved;
      _history = history;
    });
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedKey,
      jsonEncode(_savedMagnets.map((entry) => entry.toJson()).toList()),
    );
    await prefs.setString(
      _historyKey,
      jsonEncode(_history.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> _initializeEngine() async {
    try {
      if (!LibtorrentFlutter.isInitialized) {
        await LibtorrentFlutter.init(
          fetchTrackers: true,
          pollInterval: const Duration(milliseconds: 700),
        );
      }
      _engine = LibtorrentFlutter.instance;
      _torrentSubscription = _engine!.torrentUpdates.listen(_handleTorrents);
      _streamSubscription = _engine!.streamUpdates.listen(_handleStreams);
      if (!mounted) return;
      setState(() {
        _engineReady = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Torrent engine could not start: $error';
      });
    }
  }

  void _handleTorrents(Map<int, TorrentInfo> snapshot) {
    if (!mounted) return;
    final active =
        _activeTorrentId == null ? null : snapshot[_activeTorrentId!];

    if (active != null && active.hasMetadata && _files.isEmpty) {
      try {
        final files = _engine!.getFiles(active.id);
        setState(() {
          _torrents = snapshot;
          _files = files;
        });
        return;
      } catch (error) {
        setState(() {
          _torrents = snapshot;
          _error = 'Metadata was found, but the file list failed: $error';
        });
        return;
      }
    }

    setState(() => _torrents = snapshot);
  }

  void _handleStreams(Map<int, StreamInfo> snapshot) {
    if (!mounted) return;
    final activeId = _stream?.id;
    final subtitleId = _subtitleStream?.id;
    final audioId = _audioStream?.id;
    setState(() {
      if (activeId != null) _stream = snapshot[activeId] ?? _stream;
      if (subtitleId != null) {
        _subtitleStream = snapshot[subtitleId] ?? _subtitleStream;
      }
      if (audioId != null) _audioStream = snapshot[audioId] ?? _audioStream;
    });
  }

  Future<void> _addMagnet([String? supplied]) async {
    final value = (supplied ?? _magnetController.text).trim();
    if (!value.toLowerCase().startsWith('magnet:?') ||
        !value.toLowerCase().contains('xt=urn:btih:')) {
      _showMessage('Paste a valid magnet link.');
      return;
    }
    if (!_engineReady || _engine == null) {
      _showMessage('The torrent engine is still starting.');
      return;
    }

    setState(() {
      _isAdding = true;
      _error = null;
    });

    try {
      await _closePlayback();
      final oldTorrentId = _activeTorrentId;
      if (oldTorrentId != null) {
        _engine!.removeTorrent(oldTorrentId, deleteFiles: false);
      }

      final id = _engine!.addMagnet(value, null, true);
      final name = _nameFromMagnet(value);
      final entry = MagnetEntry(
        uri: value,
        name: name,
        savedAt: DateTime.now().millisecondsSinceEpoch,
      );

      _magnetController.text = value;
      setState(() {
        _activeTorrentId = id;
        _activeMagnet = value;
        _activeName = name;
        _files = [];
        _torrents = {};
        _isAdding = false;
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
    final streamIds = <int>{
      if (_stream != null) _stream!.id,
      if (_subtitleStream != null) _subtitleStream!.id,
      if (_audioStream != null) _audioStream!.id,
    };
    for (final id in streamIds) {
      try {
        _engine?.stopStream(id);
      } catch (_) {}
    }

    final player = _player;
    _player = null;
    _videoController = null;
    _stream = null;
    _subtitleStream = null;
    _audioStream = null;
    _playingFile = null;
    if (mounted && updateUi) setState(() {});
    await player?.dispose();
  }

  Future<void> _startStream(FileInfo file) async {
    final torrentId = _activeTorrentId;
    if (torrentId == null || _engine == null) return;

    setState(() {
      _isStartingStream = true;
      _error = null;
    });

    try {
      await _closePlayback();
      final stream = _engine!.startStream(
        torrentId,
        fileIndex: file.index,
        maxCacheBytes: 512 * 1024 * 1024,
      );
      final player = Player();
      final controller = VideoController(player);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _stream = stream;
        _playingFile = file;
        _player = player;
        _videoController = controller;
        _isStartingStream = false;
      });
      await player.open(Media(stream.url), play: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStartingStream = false;
        _error = 'The file could not start: $error';
      });
    }
  }

  Future<void> _openExternalPlayer() async {
    final stream = _stream;
    if (stream == null) return;
    final mime = _mimeFor(_playingFile?.name ?? '');

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
    final torrentId = _activeTorrentId;
    if (player == null || torrentId == null || _engine == null) return;
    try {
      final info = _engine!.startStream(
        torrentId,
        fileIndex: file.index,
        maxCacheBytes: 16 * 1024 * 1024,
      );
      if (_subtitleStream != null) {
        _engine!.stopStream(_subtitleStream!.id);
      }
      _subtitleStream = info;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(
          info.url,
          title: _fileName(file.name),
        ),
      );
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('Subtitle could not be loaded: $error');
    }
  }

  Future<void> _loadExternalAudio(FileInfo file) async {
    final player = _player;
    final torrentId = _activeTorrentId;
    if (player == null || torrentId == null || _engine == null) return;
    try {
      final info = _engine!.startStream(
        torrentId,
        fileIndex: file.index,
        maxCacheBytes: 32 * 1024 * 1024,
      );
      if (_audioStream != null) {
        _engine!.stopStream(_audioStream!.id);
      }
      _audioStream = info;
      await player.setAudioTrack(
        AudioTrack.uri(
          info.url,
          title: _fileName(file.name),
        ),
      );
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('Audio track could not be loaded: $error');
    }
  }

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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
  }

  String _formatSpeed(int bytesPerSecond) =>
      '${_formatBytes(bytesPerSecond)}/s';

  String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'\.(mp3|m4a|aac|flac|wav|ogg|opus|mka)$').hasMatch(lower)) {
      return 'audio/*';
    }
    return 'video/*';
  }

  bool _isSubtitle(FileInfo file) => RegExp(
        r'\.(srt|ass|ssa|vtt|sub|idx)$',
        caseSensitive: false,
      ).hasMatch(file.name);

  bool _isExternalAudio(FileInfo file) => RegExp(
        r'\.(mp3|m4a|aac|flac|wav|ogg|opus|mka)$',
        caseSensitive: false,
      ).hasMatch(file.name);

  TorrentInfo? get _activeTorrent =>
      _activeTorrentId == null ? null : _torrents[_activeTorrentId!];

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
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            const Text(
              'magnet',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 9,
                  color: _engineReady ? _lime : Colors.orange,
                ),
                const SizedBox(width: 7),
                Text(
                  _engineReady ? 'ready' : 'starting',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _buildHome(),
            _buildLibrary(),
          ],
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

  Widget _buildHome() {
    final active = _activeTorrent;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const SizedBox(height: 12),
        const Text(
          'PLAY THE PIECES.',
          style: TextStyle(
            color: _lime,
            fontSize: 12,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'Stream what\'s yours.',
          style: TextStyle(
            fontSize: 38,
            height: .98,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Native Android playback from seeders and peers.\nOnly use content you own or are authorized to access.',
          style: TextStyle(color: _muted, height: 1.45),
        ),
        const SizedBox(height: 24),
        _buildMagnetInput(),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _buildError(),
        ],
        const SizedBox(height: 20),
        if (_isAdding || !_engineReady) _buildEngineCard(),
        if (active != null || _activeTorrentId != null) ...[
          _buildActiveTorrent(active),
          if (_player != null && _videoController != null) ...[
            const SizedBox(height: 16),
            _buildPlayer(),
          ],
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFilePicker(),
          ],
        ] else
          _buildEmptyState(),
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
              onSubmitted: (_) => _addMagnet(),
              decoration: InputDecoration(
                hintText: 'Paste a magnet link',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _magnetController.text = data!.text!.trim();
                    }
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

  Widget _buildError() {
    return Card(
      color: const Color(0xFF2A1717),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child:
                  Text(_error!, style: const TextStyle(color: Colors.orange)),
            ),
            IconButton(
              onPressed: () => setState(() => _error = null),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineCard() {
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
                _isAdding
                    ? 'Joining the swarm…'
                    : 'Starting native torrent engine…',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTorrent(TorrentInfo? torrent) {
    final progress = torrent?.progress ?? 0;
    final state = torrent?.state.label ?? 'Waiting for metadata';
    final peers = torrent?.numPeers ?? 0;
    final seeds = torrent?.numSeeds ?? 0;
    final speed =
        torrent == null ? '0 B/s' : _formatSpeed(torrent.downloadRate);

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
                        state.toUpperCase(),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Save magnet',
                  onPressed: _toggleSavedCurrent,
                  icon: Icon(
                    _savedMagnets.any((entry) => entry.uri == _activeMagnet)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: _lime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                    child: _stat('Peers', '$peers', Icons.people_alt_outlined)),
                Expanded(child: _stat('Seeds', '$seeds', Icons.cloud_outlined)),
                Expanded(child: _stat('Down', speed, Icons.arrow_downward)),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 7,
                backgroundColor: const Color(0xFF203C32),
                color: _lime,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  torrent?.hasMetadata == true
                      ? '${(progress * 100).toStringAsFixed(1)}% available'
                      : 'Finding metadata from peers…',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (torrent?.isPaused == true)
                  const Text('Paused', style: TextStyle(color: Colors.orange)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _muted, size: 17),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    );
  }

  Widget _buildPlayer() {
    final player = _player!;
    final subtitles = _files.where(_isSubtitle).toList();
    final externalAudio = _files.where(_isExternalAudio).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(controller: _videoController!),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _fileName(_playingFile?.name ?? 'Now playing'),
                    maxLines: 1,
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
                  onPressed: _closePlayback,
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
              final audioTracks = tracks.audio;
              final subtitleTracks = tracks.subtitle;
              final hasAudioChoice = audioTracks.length > 2;
              final hasSubtitleChoice = subtitleTracks.length > 2;
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
                    if (hasAudioChoice) _audioMenu(player, audioTracks),
                    if (hasSubtitleChoice)
                      _subtitleMenu(player, subtitleTracks),
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
      child: _smallAction(Icons.audiotrack_outlined, 'Audio'),
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
      child: _smallAction(Icons.closed_caption_outlined, 'Subtitles'),
    );
  }

  Widget _externalSubtitleMenu(List<FileInfo> files) {
    return PopupMenuButton<FileInfo>(
      onSelected: _loadExternalSubtitle,
      itemBuilder: (context) => files
          .map(
            (file) => PopupMenuItem(
              value: file,
              child:
                  Text(_fileName(file.name), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      child: _smallAction(Icons.subtitles_outlined, 'External subs'),
    );
  }

  Widget _externalAudioMenu(List<FileInfo> files) {
    return PopupMenuButton<FileInfo>(
      onSelected: _loadExternalAudio,
      itemBuilder: (context) => files
          .map(
            (file) => PopupMenuItem(
              value: file,
              child:
                  Text(_fileName(file.name), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      child: _smallAction(Icons.library_music_outlined, 'External audio'),
    );
  }

  Widget _smallAction(IconData icon, String label) {
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

  Widget _buildFilePicker() {
    final streamable = _files.where((file) => file.isStreamable).toList();
    if (streamable.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
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
            const Text(
              'Choose a file to play',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...streamable.map(
              (file) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _lime.withValues(alpha: .14),
                  foregroundColor: _lime,
                  child: Icon(
                    _isExternalAudio(file)
                        ? Icons.music_note
                        : Icons.movie_outlined,
                  ),
                ),
                title: Text(
                  _fileName(file.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _formatBytes(file.size),
                  style: const TextStyle(color: _muted),
                ),
                trailing: _isStartingStream && _playingFile == file
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Play',
                        onPressed: () => _startStream(file),
                        icon:
                            const Icon(Icons.play_arrow_rounded, color: _lime),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(Icons.waves_rounded,
                color: _lime.withValues(alpha: .8), size: 38),
            const SizedBox(height: 10),
            const Text(
              'Ready when you are',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Add an authorized magnet to discover its files and start playback.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibrary() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      children: [
        const Text(
          'YOUR LIBRARY',
          style: TextStyle(
            color: _lime,
            letterSpacing: 2.0,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'Saved for later.',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Magnets stay on this device. Nothing is uploaded to a cloud account.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 26),
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
            Text(
              '${entries.length}',
              style: const TextStyle(color: _muted),
            ),
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
    _scrollController.dispose();
    _torrentSubscription?.cancel();
    _streamSubscription?.cancel();
    _closePlayback(updateUi: false);
    super.dispose();
  }
}
