import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../app_state.dart';
import '../engine_controller.dart';
import '../format.dart';
import '../library_store.dart';
import '../messenger.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'player_screen.dart';

class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  final TextEditingController _input = TextEditingController();
  bool _playerOpen = false;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    appEngine.addListener(_onEngineChanged);
  }

  @override
  void dispose() {
    appEngine.removeListener(_onEngineChanged);
    _input.dispose();
    super.dispose();
  }

  /// The engine owns the player, so this screen only has to react when a stream
  /// becomes playable and push the fullscreen route.
  void _onEngineChanged() {
    final playing = appEngine.isPlaying;
    if (playing && !_wasPlaying && !_playerOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPlayer());
    }
    _wasPlaying = playing;
  }

  Future<void> _openPlayer() async {
    if (_playerOpen || !mounted) return;
    _playerOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PlayerScreen()),
    );
    _playerOpen = false;
  }

  Future<void> _submit() async {
    final value = _input.text.trim();
    if (value.isEmpty) {
      showMessage('Paste a magnet link first.');
      return;
    }
    FocusScope.of(context).unfocus();
    _input.clear();
    await appEngine.addMagnet(value);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      showMessage('Your clipboard is empty.');
      return;
    }
    _input.text = text;
    if (text.toLowerCase().startsWith('magnet:?')) await _submit();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[appEngine, appLibrary]),
      builder: (context, _) {
        final engine = appEngine;
        final torrent = engine.activeTorrent;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            screenHeading(
              kicker: 'PLAY THE PIECES.',
              title: "Stream what's yours.",
              subtitle:
                  'Paste a magnet link. Playback starts as soon as the opening '
                  'pieces land — no waiting for the full download.',
            ),
            const SizedBox(height: 20),
            _magnetInput(),
            if (engine.error != null) ...[
              const SizedBox(height: 16),
              _errorCard(engine.error!),
            ],
            if (engine.adding) ...[
              const SizedBox(height: 16),
              busyCard('Adding magnet…'),
            ],
            if (torrent != null) ...[
              const SizedBox(height: 16),
              _torrentCard(torrent),
            ],
            if (engine.buffering) ...[
              const SizedBox(height: 16),
              _bufferingCard(),
            ],
            if (engine.isPlaying) ...[
              const SizedBox(height: 16),
              _nowPlayingCard(),
            ],
            if (engine.activeFiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              _filesCard(),
            ],
            if (torrent == null && !engine.adding) ...[
              const SizedBox(height: 16),
              emptyCard(
                icon: Icons.bolt_rounded,
                title: 'Ready when you are',
                body: 'Nothing is streaming yet. Paste a magnet link above, or '
                    'open one from your browser — magnet links now open '
                    'straight into this app.',
              ),
            ],
            if (torrent != null) ...[
              const SizedBox(height: 16),
              _diagnostics(),
            ],
          ],
        );
      },
    );
  }

  Widget _magnetInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _input,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'magnet:?xt=urn:btih:…',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: appEngine.ready ? _submit : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start streaming'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Paste',
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Card(
      color: errorPanel,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: danger, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Something needs your attention',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  onPressed: appEngine.dismissError,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            Text(
              message,
              style: const TextStyle(height: 1.4, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (appEngine.playingFile != null)
                  OutlinedButton.icon(
                    onPressed: appEngine.retryLastFile,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                if (appEngine.bufferTimedOut && appEngine.stream != null)
                  OutlinedButton.icon(
                    onPressed: appEngine.openPlayer,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play anyway'),
                  ),
                if (appEngine.stream != null)
                  OutlinedButton.icon(
                    onPressed: appEngine.openExternalPlayer,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Another player'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _torrentCard(TorrentInfo torrent) {
    final engine = appEngine;
    final magnet = engine.activeMagnet;
    final saved = magnet != null && appLibrary.isSaved(magnet);
    final remaining = torrent.totalWanted - torrent.totalDone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      kickerText(
                        engine.stateLabelFor(torrent.id).toUpperCase(),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        engine.activeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: saved ? 'Remove from library' : 'Save to library',
                  onPressed: magnet == null
                      ? null
                      : () => appLibrary.toggleSaved(
                            MagnetEntry(
                              uri: magnet,
                              name: engine.activeName,
                              savedAt: DateTime.now().millisecondsSinceEpoch,
                            ),
                          ),
                  icon: Icon(
                    saved ? Icons.bookmark : Icons.bookmark_border,
                    color: saved ? lime : muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            progressBar(
              torrent.hasMetadata ? torrent.progress.clamp(0.0, 1.0) : null,
            ),
            const SizedBox(height: 8),
            Text(
              torrent.hasMetadata
                  ? '${(torrent.progress * 100).toStringAsFixed(1)}% · '
                      '${fmtBytes(torrent.totalDone)} of '
                      '${fmtBytes(torrent.totalWanted)} · '
                      '${fmtEta(remaining, torrent.downloadRate)} left'
                  : 'Asking DHT and trackers for metadata… '
                      '${engine.waitedLabelFor(torrent.id)} elapsed',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: statTile(
                    'Peers',
                    '${safeCount(torrent.numPeers)}',
                    Icons.people_alt_outlined,
                  ),
                ),
                Expanded(
                  child: statTile(
                    'Seeds',
                    '${safeCount(torrent.numSeeds)}',
                    Icons.cloud_download_outlined,
                  ),
                ),
                Expanded(
                  child: statTile(
                    'Down',
                    fmtSpeed(safeCount(torrent.downloadRate)),
                    Icons.south_rounded,
                  ),
                ),
                Expanded(
                  child: statTile(
                    'Up',
                    fmtSpeed(safeCount(torrent.uploadRate)),
                    Icons.north_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bufferingCard() {
    final engine = appEngine;
    final stream = engine.stream;
    final pct = stream == null ? 0.0 : stream.bufferPct.clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    engine.status.isEmpty ? 'Buffering…' : engine.status,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            progressBar(pct == 0 ? null : pct),
            const SizedBox(height: 8),
            Text(
              stream == null
                  ? 'Starting the stream server…'
                  : 'Buffer ${(pct * 100).toStringAsFixed(0)}% · '
                      '${stream.bufferPieces}/${stream.readaheadWindow} pieces · '
                      '${safeCount(stream.activePeers)} stream peers',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => appEngine.stopPlayback(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nowPlayingCard() {
    final file = appEngine.playingFile;
    return Card(
      color: panelRaised,
      child: ListTile(
        leading: const Icon(Icons.play_circle_rounded, color: lime, size: 32),
        title: Text(
          file == null ? 'Playing' : fileNameOf(file.name),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: const Text('Tap to return to the player'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _openPlayer,
      ),
    );
  }

  Widget _filesCard() {
    final engine = appEngine;
    final files = engine.activeFiles;
    final playable = engine.playableFiles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                kickerText('FILES'),
                const Spacer(),
                Text(
                  '${playable.length} playable of ${files.length}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final file in files) _fileTile(file),
          ],
        ),
      ),
    );
  }

  Widget _fileTile(FileInfo file) {
    final playing = appEngine.playingFile?.index == file.index;
    final canPlay = isPlayableFile(file);
    final icon = isVideoFile(file.name)
        ? Icons.movie_outlined
        : isAudioFile(file.name)
            ? Icons.audiotrack_outlined
            : isSubtitleFile(file.name)
                ? Icons.closed_caption_outlined
                : Icons.insert_drive_file_outlined;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: canPlay ? lime : muted),
      title: Text(
        fileNameOf(file.name),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: playing ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        fmtBytes(file.size),
        style: const TextStyle(color: muted, fontSize: 11),
      ),
      trailing: canPlay
          ? IconButton(
              tooltip: playing ? 'Playing' : 'Play this file',
              onPressed: playing ? _openPlayer : () => appEngine.startStream(file),
              icon: Icon(
                playing
                    ? Icons.graphic_eq_rounded
                    : Icons.play_circle_outline_rounded,
                color: lime,
              ),
            )
          : null,
    );
  }

  Widget _diagnostics() {
    final engine = appEngine;
    final torrent = engine.activeTorrent;
    final stream = engine.stream;

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Text(
            'Diagnostics',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          subtitle: Text(
            'libtorrent ${engine.version}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          children: [
            infoRow('Torrent id', '${torrent?.id ?? '—'}'),
            infoRow('State', torrent == null ? '—' : engine.stateLabelFor(torrent.id)),
            infoRow('Metadata', torrent?.hasMetadata == true ? 'yes' : 'no'),
            infoRow('Waiting', engine.waitedLabelFor(engine.activeTorrentId)),
            infoRow(
              'Re-announces',
              '${engine.reannounces[engine.activeTorrentId] ?? 0}',
            ),
            infoRow('Pieces', torrent == null ? '—' : '${torrent.numPieces}'),
            infoRow('Uploaded', fmtBytes(torrent?.totalUploaded ?? 0)),
            infoRow('Stream id', '${stream?.id ?? '—'}'),
            infoRow(
              'Stream state',
              stream == null ? '—' : stream.streamState.name,
            ),
            infoRow('Read head', fmtBytes(stream?.readHead ?? 0)),
            infoRow(
              'Read-ahead',
              stream == null
                  ? '—'
                  : '${stream.bufferPieces}/${stream.readaheadWindow} pieces',
            ),
            infoRow('Stream URL', stream?.url ?? '—'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: stream == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: stream.url));
                          showMessage('Stream URL copied.');
                        },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy URL'),
                ),
                OutlinedButton.icon(
                  onPressed: stream == null ? null : appEngine.probeStream,
                  icon: const Icon(Icons.network_check_rounded, size: 16),
                  label: const Text('Test stream'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
