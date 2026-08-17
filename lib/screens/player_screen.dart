import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import '../engine_controller.dart';
import '../format.dart';
import '../theme.dart';

/// Full screen playback. The player itself lives in the engine controller so
/// leaving this route does not tear down the stream.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<void> _stop() async {
    final navigator = Navigator.of(context);
    await appEngine.stopPlayback();
    navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appEngine,
      builder: (context, _) {
        final engine = appEngine;
        final controller = engine.videoController;
        final player = engine.player;
        final file = engine.playingFile;

        return Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.black54,
            foregroundColor: Colors.white,
            title: Text(
              file == null ? engine.activeName : fileNameOf(file.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            actions: [
              if (player != null) _trackMenus(player, engine),
              IconButton(
                tooltip: 'Open in another player',
                onPressed: engine.openExternalPlayer,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              IconButton(
                tooltip: 'Stop',
                onPressed: _stop,
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
          body: controller == null
              ? _buffering(engine)
              : Stack(
                  children: [
                    Positioned.fill(child: Video(controller: controller)),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 64, right: 12),
                          child: Align(
                            alignment: Alignment.topRight,
                            child: _liveStats(engine),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buffering(EngineController engine) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 18),
            Text(
              engine.status.isEmpty ? 'Buffering…' : engine.status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${fmtSpeed(safeCount(engine.activeTorrent?.downloadRate ?? 0))}'
              ' · ${safeCount(engine.stream?.activePeers ?? 0)} stream peers',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _stop,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveStats(EngineController engine) {
    final torrent = engine.activeTorrent;
    final stream = engine.stream;
    final buffer = stream?.bufferPct ?? 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '${fmtSpeed(safeCount(torrent?.downloadRate ?? 0))}  ·  '
          '${safeCount(torrent?.numPeers ?? 0)}P/'
          '${safeCount(torrent?.numSeeds ?? 0)}S  ·  '
          'buffer ${(buffer * 100).toStringAsFixed(0)}%',
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
      ),
    );
  }

  Widget _trackMenus(Player player, EngineController engine) {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data;
        final subtitleFiles = engine.subtitleFiles;
        final audioFiles = engine.externalAudioFiles;
        final embeddedAudio = (tracks?.audio.length ?? 0) > 2;
        final embeddedSubs = (tracks?.subtitle.length ?? 0) > 2;

        if (!embeddedAudio &&
            !embeddedSubs &&
            subtitleFiles.isEmpty &&
            audioFiles.isEmpty) {
          return const SizedBox.shrink();
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (embeddedAudio || audioFiles.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Audio',
                icon: const Icon(Icons.audiotrack_outlined),
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  if (tracks != null)
                    for (var i = 0; i < tracks.audio.length; i++)
                      PopupMenuItem<String>(
                        value: 'embedded:$i',
                        child: Text(
                          _trackLabel(
                            tracks.audio[i].id,
                            tracks.audio[i].title,
                            tracks.audio[i].language,
                          ),
                        ),
                      ),
                  for (var i = 0; i < audioFiles.length; i++)
                    PopupMenuItem<String>(
                      value: 'file:$i',
                      child: Text(
                        fileNameOf(audioFiles[i].name),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onSelected: (value) {
                  final parts = value.split(':');
                  final index = int.tryParse(parts[1]) ?? 0;
                  if (parts[0] == 'embedded' && tracks != null) {
                    player.setAudioTrack(tracks.audio[index]);
                  } else if (parts[0] == 'file') {
                    engine.loadExternalAudio(audioFiles[index]);
                  }
                },
              ),
            if (embeddedSubs || subtitleFiles.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Subtitles',
                icon: const Icon(Icons.closed_caption_outlined),
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  if (tracks != null)
                    for (var i = 0; i < tracks.subtitle.length; i++)
                      PopupMenuItem<String>(
                        value: 'embedded:$i',
                        child: Text(
                          _trackLabel(
                            tracks.subtitle[i].id,
                            tracks.subtitle[i].title,
                            tracks.subtitle[i].language,
                          ),
                        ),
                      ),
                  for (var i = 0; i < subtitleFiles.length; i++)
                    PopupMenuItem<String>(
                      value: 'file:$i',
                      child: Text(
                        fileNameOf(subtitleFiles[i].name),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onSelected: (value) {
                  final parts = value.split(':');
                  final index = int.tryParse(parts[1]) ?? 0;
                  if (parts[0] == 'embedded' && tracks != null) {
                    player.setSubtitleTrack(tracks.subtitle[index]);
                  } else if (parts[0] == 'file') {
                    engine.loadExternalSubtitle(subtitleFiles[index]);
                  }
                },
              ),
          ],
        );
      },
    );
  }

  String _trackLabel(String id, String? title, String? language) {
    if (id == 'auto') return 'Automatic';
    if (id == 'no') return 'Off';
    return title ?? language ?? 'Track $id';
  }
}
