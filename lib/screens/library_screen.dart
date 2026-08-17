import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../library_store.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appLibrary,
      builder: (context, _) {
        final saved = appLibrary.saved;
        final history = appLibrary.history;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            screenHeading(
              kicker: 'YOUR LIBRARY',
              title: 'Saved for later.',
              subtitle: 'Bookmarked magnets and everything you have opened. '
                  'Tap any item to stream it again from where you stopped.',
            ),
            const SizedBox(height: 20),
            if (saved.isEmpty && history.isEmpty)
              emptyCard(
                icon: Icons.bookmark_border_rounded,
                title: 'Nothing saved yet',
                body: 'Bookmark a torrent from the Stream tab and it will '
                    'wait for you here.',
              ),
            if (saved.isNotEmpty) ...[
              _sectionHeader('SAVED', '${saved.length}'),
              for (final entry in saved) _entryTile(context, entry, true),
              const SizedBox(height: 18),
            ],
            if (history.isNotEmpty) ...[
              _sectionHeader(
                'RECENT',
                '${history.length}',
                onClear: appLibrary.clearHistory,
              ),
              for (final entry in history) _entryTile(context, entry, false),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title, String count, {VoidCallback? onClear}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          kickerText(title),
          const SizedBox(width: 8),
          Text(count, style: const TextStyle(color: muted, fontSize: 12)),
          const Spacer(),
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }

  Widget _entryTile(BuildContext context, MagnetEntry entry, bool saved) {
    final resumeAt = appLibrary.bestPositionFor(entry.uri);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: panelRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.movie_outlined, color: lime, size: 20),
        ),
        title: Text(
          entry.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            resumeAt > 10
                ? '${fmtAgo(entry.savedAt)} · resume at '
                    '${fmtClock(Duration(seconds: resumeAt))}'
                : fmtAgo(entry.savedAt),
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'save',
              child: Text(saved ? 'Remove from saved' : 'Save'),
            ),
            if (resumeAt > 10)
              const PopupMenuItem<String>(
                value: 'forget',
                child: Text('Forget position'),
              ),
            if (!saved)
              const PopupMenuItem<String>(
                value: 'remove',
                child: Text('Remove from recent'),
              ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'save':
                appLibrary.toggleSaved(entry);
              case 'forget':
                appLibrary.forgetPositions(entry.uri);
              case 'remove':
                appLibrary.removeHistory(entry.uri);
            }
          },
        ),
        onTap: () {
          selectedTab.value = 0;
          appEngine.addMagnet(entry.uri);
        },
      ),
    );
  }
}
