import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Keep only preferences that change the user-facing playback experience.
/// Engine tuning stays internal so a broken stream cannot be hidden behind a
/// wall of sliders and diagnostics.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettings,
      builder: (context, _) {
        final settings = appSettings;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            screenHeading(
              kicker: 'SETTINGS',
              title: 'Preferences.',
              subtitle: 'Simple controls for playback and appearance.',
            ),
            const SizedBox(height: 20),
            _card('PLAYBACK', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.autoPlay,
                onChanged: (value) => settings.update(autoPlay: value),
                title: const Text('Play automatically'),
                subtitle: const Text(
                  'Open the first video when magnet metadata arrives',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.resumePlayback,
                onChanged: (value) => settings.update(resumePlayback: value),
                title: const Text('Resume playback'),
              ),
            ]),
            const SizedBox(height: 12),
            _card('APPEARANCE', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.darkMode,
                onChanged: (value) => settings.update(darkMode: value),
                title: const Text('Dark mode'),
              ),
            ]),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(Icons.stream_rounded, color: lime),
                title: Text(
                  'Stream-only playback',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Only requested video pieces are fetched. No full download.',
                ),
              ),
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
}
