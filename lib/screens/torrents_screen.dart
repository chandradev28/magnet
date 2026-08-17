import 'package:flutter/material.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../app_state.dart';
import '../engine_controller.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Everything currently in the session. Streaming one file no longer means the
/// other torrents are invisible.
class TorrentsScreen extends StatelessWidget {
  const TorrentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appEngine,
      builder: (context, _) {
        final torrents = appEngine.torrents.values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            screenHeading(
              kicker: 'THE SWARM',
              title: 'Your torrents.',
              subtitle: 'Pause, resume or drop anything in the session. '
                  'Downloads keep running while you use other apps.',
            ),
            const SizedBox(height: 20),
            if (torrents.isEmpty)
              emptyCard(
                icon: Icons.dns_outlined,
                title: 'Nothing in the session',
                body: 'Add a magnet from the Stream tab and it will show up '
                    'here with live peers, speed and progress.',
              )
            else
              for (final torrent in torrents) ...[
                _torrentCard(context, torrent),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }

  Widget _torrentCard(BuildContext context, TorrentInfo torrent) {
    final engine = appEngine;
    final active = engine.activeTorrentId == torrent.id;
    final remaining = torrent.totalWanted - torrent.totalDone;
    final best = engine.bestFileFor(torrent.id);

    return Card(
      color: active ? panelRaised : panel,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    engine.nameOf[torrent.id] ?? torrent.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ),
                if (active) pillChip(Icons.bolt_rounded, 'Active'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              engine.stateLabelFor(torrent.id),
              style: const TextStyle(color: lime, fontSize: 12),
            ),
            const SizedBox(height: 12),
            progressBar(
              torrent.hasMetadata ? torrent.progress.clamp(0.0, 1.0) : null,
            ),
            const SizedBox(height: 8),
            Text(
              torrent.hasMetadata
                  ? '${(torrent.progress * 100).toStringAsFixed(1)}% · '
                      '${fmtBytes(torrent.totalDone)}/'
                      '${fmtBytes(torrent.totalWanted)} · '
                      '${fmtEta(remaining, torrent.downloadRate)} left'
                  : 'Waiting for metadata · '
                      '${engine.waitedLabelFor(torrent.id)} elapsed',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
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
            const Divider(height: 24),
            Row(
              children: [
                TextButton.icon(
                  onPressed: best == null
                      ? null
                      : () {
                          selectedTab.value = 0;
                          engine.startStream(best, torrentId: torrent.id);
                        },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Play'),
                ),
                TextButton.icon(
                  onPressed: () => engine.togglePause(torrent.id),
                  icon: Icon(
                    torrent.isPaused
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(torrent.isPaused ? 'Resume' : 'Pause'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Open in Stream tab',
                  onPressed: () {
                    engine.select(torrent.id);
                    selectedTab.value = 0;
                  },
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _confirmRemove(context, torrent),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: danger,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, TorrentInfo torrent) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove torrent?'),
        content: Text(
          appEngine.nameOf[torrent.id] ?? torrent.name,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Remove, keep files'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text(
              'Remove and delete',
              style: TextStyle(color: danger),
            ),
          ),
        ],
      ),
    );
    if (choice == null || choice == 'cancel') return;
    await appEngine.remove(torrent.id, deleteFiles: choice == 'delete');
  }
}
