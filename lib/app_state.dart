import 'package:flutter/foundation.dart';

import 'engine_controller.dart';
import 'library_store.dart';
import 'settings_store.dart';

/// Single set of long lived objects. The engine outlives every screen, so it is
/// deliberately not owned by a widget.
final SettingsStore appSettings = SettingsStore();
final LibraryStore appLibrary = LibraryStore();
final EngineController appEngine = EngineController(
  settings: appSettings,
  store: appLibrary,
);

/// Which bottom tab is showing. Any screen can change it.
final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);
