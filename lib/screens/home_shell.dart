import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../messenger.dart';
import '../native_bridge.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'stream_screen.dart';
import 'torrents_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  StreamSubscription<String>? _linkSub;

  @override
  void initState() {
    super.initState();
    appEngine.init();
    _wireMagnetIntents();
  }

  /// Magnet links tapped in a browser, or shared from another app, arrive here.
  Future<void> _wireMagnetIntents() async {
    final initial = await NativeBridge.initialLink();
    if (initial != null && initial.trim().isNotEmpty) _handleLink(initial);
    _linkSub = NativeBridge.links().listen(_handleLink);
  }

  void _handleLink(String link) {
    final value = link.trim();
    if (value.isEmpty) return;
    selectedTab.value = 0;
    showMessage('Magnet received from another app.');
    appEngine.addMagnet(value);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: selectedTab,
      builder: (context, tab, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: const SizedBox.shrink(),
            actions: [
              IconButton(
                tooltip:
                    appSettings.darkMode ? 'Use light mode' : 'Use dark mode',
                onPressed: () => appSettings.update(
                  darkMode: !appSettings.darkMode,
                ),
                icon: Icon(
                  appSettings.darkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: IndexedStack(
              index: tab,
              children: const <Widget>[
                StreamScreen(),
                TorrentsScreen(),
                LibraryScreen(),
                SettingsScreen(),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (index) => selectedTab.value = index,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            indicatorColor:
                Theme.of(context).colorScheme.primary.withOpacity(.18),
            destinations: const <Widget>[
              NavigationDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle),
                label: 'Stream',
              ),
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns),
                label: 'Torrents',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmark_border),
                selectedIcon: Icon(Icons.bookmark),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
