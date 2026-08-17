import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../messenger.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Every knob that affects whether a stream actually starts, in one place.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[appSettings, appEngine]),
      builder: (context, _) {
        final settings = appSettings;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            screenHeading(
              kicker: 'TUNING',
              title: 'Settings.',
              subtitle: 'Preload and read-ahead are percentages of the cache. '
                  'Smaller values start playback sooner on thin swarms.',
            ),
            const SizedBox(height: 20),
            _card('PLAYBACK', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.darkMode,
                onChanged: (value) => settings.update(darkMode: value),
                title: const Text('Dark mode'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.autoPlay,
                onChanged: (value) => settings.update(autoPlay: value),
                title: const Text('Start playing automatically'),
                subtitle: const Text(
                  'Picks the largest playable file as soon as metadata arrives',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.resumePlayback,
                onChanged: (value) => settings.update(resumePlayback: value),
                title: const Text('Resume where I stopped'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.backgroundService,
                onChanged: (value) => settings.update(backgroundService: value),
                title: const Text('Keep the stream alive in background'),
                subtitle: const Text(
                  'Keeps the player session active with a notification',
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _card('SWARM', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.injectTrackers,
                onChanged: (value) => settings.update(injectTrackers: value),
                title: const Text('Add extra public trackers'),
                subtitle: const Text(
                  'Improves peer discovery for magnets with few trackers',
                ),
              ),
              _slider(
                label: 'Peer connections',
                value: settings.connections.toDouble(),
                min: 10,
                max: 200,
                divisions: 19,
                display: '${settings.connections}',
                onChanged: (value) =>
                    settings.update(connections: value.round()),
              ),
              _slider(
                label: 'Idle peer timeout',
                value: settings.disconnectTimeout.toDouble(),
                min: 60,
                max: 1200,
                divisions: 19,
                display: '${settings.disconnectTimeout}s',
                onChanged: (value) =>
                    settings.update(disconnectTimeout: value.round()),
              ),
            ]),
            const SizedBox(height: 12),
            _card('BUFFER', [
              _slider(
                label: 'Stream cache',
                value: settings.cacheMb.toDouble(),
                min: 16,
                max: 512,
                divisions: 31,
                display: '${settings.cacheMb} MB',
                onChanged: (value) => settings.update(cacheMb: value.round()),
              ),
              _slider(
                label: 'Preload target',
                value: settings.preloadPct.toDouble(),
                min: 2,
                max: 90,
                divisions: 44,
                display: '${settings.preloadPct}% of cache',
                onChanged: (value) =>
                    settings.update(preloadPct: value.round()),
              ),
              _slider(
                label: 'Read-ahead window',
                value: settings.readAheadPct.toDouble(),
                min: 10,
                max: 95,
                divisions: 17,
                display: '${settings.readAheadPct}% of cache',
                onChanged: (value) =>
                    settings.update(readAheadPct: value.round()),
              ),
              _slider(
                label: 'Head preload',
                value: settings.preloadMb.toDouble(),
                min: 1,
                max: 64,
                divisions: 63,
                display: '${settings.preloadMb} MB',
                onChanged: (value) => settings.update(preloadMb: value.round()),
              ),
              _slider(
                label: 'Start playback after',
                value: settings.softGateSeconds.toDouble(),
                min: 3,
                max: 60,
                divisions: 19,
                display: '${settings.softGateSeconds}s of head data',
                onChanged: (value) =>
                    settings.update(softGateSeconds: value.round()),
              ),
              _slider(
                label: 'Give up buffering after',
                value: settings.bufferTimeoutSeconds.toDouble(),
                min: 30,
                max: 300,
                divisions: 27,
                display: '${settings.bufferTimeoutSeconds}s',
                onChanged: (value) =>
                    settings.update(bufferTimeoutSeconds: value.round()),
              ),
            ]),
            const SizedBox(height: 12),
            _card('ENGINE', [
              infoRow('libtorrent', appEngine.version),
              infoRow('Status', appEngine.ready ? 'ready' : 'starting'),
              infoRow('Torrents', '${appEngine.torrents.length}'),
              const SizedBox(height: 8),
              Container(
                height: 190,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: line),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    appEngine.logText.isEmpty
                        ? 'No log lines yet.'
                        : appEngine.logText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: appEngine.logText),
                      );
                      showMessage('Session log copied.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy log'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await settings.restoreDefaults();
                      appEngine.applySettings();
                      showMessage('Defaults restored.');
                    },
                    child: const Text('Restore defaults'),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 18),
            const Text(
              'Only stream content you are authorised to access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        );
      },
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kickerText(title),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
            Text(display, style: const TextStyle(color: lime, fontSize: 12)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: (_) => appEngine.applySettings(),
        ),
      ],
    );
  }
}
