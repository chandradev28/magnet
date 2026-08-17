import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the user can tune, persisted on device.
///
/// The cache numbers matter more than they look: `preloadPct` and
/// `readAheadPct` are percentages *of* the cache, so a large cache with a large
/// preload target can demand more data before playback than an ordinary swarm
/// can ever deliver.
class SettingsStore extends ChangeNotifier {
  static const _key = 'magnet.settings.v2';

  int cacheMb = 64;
  int preloadPct = 10;
  int readAheadPct = 40;
  int connections = 40;
  int preloadMb = 8;
  int disconnectTimeout = 600;
  int softGateSeconds = 12;
  int bufferTimeoutSeconds = 90;
  bool autoPlay = true;
  bool resumePlayback = true;
  bool injectTrackers = true;
  bool backgroundService = true;

  int get cacheBytes => cacheMb * 1024 * 1024;
  int get preloadBytes => preloadMb * 1024 * 1024;
  Duration get softGate => Duration(seconds: softGateSeconds);
  Duration get bufferTimeout => Duration(seconds: bufferTimeoutSeconds);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        cacheMb = json['cacheMb'] as int? ?? cacheMb;
        preloadPct = json['preloadPct'] as int? ?? preloadPct;
        readAheadPct = json['readAheadPct'] as int? ?? readAheadPct;
        connections = json['connections'] as int? ?? connections;
        preloadMb = json['preloadMb'] as int? ?? preloadMb;
        disconnectTimeout = json['disconnectTimeout'] as int? ?? disconnectTimeout;
        softGateSeconds = json['softGateSeconds'] as int? ?? softGateSeconds;
        bufferTimeoutSeconds =
            json['bufferTimeoutSeconds'] as int? ?? bufferTimeoutSeconds;
        autoPlay = json['autoPlay'] as bool? ?? autoPlay;
        resumePlayback = json['resumePlayback'] as bool? ?? resumePlayback;
        injectTrackers = json['injectTrackers'] as bool? ?? injectTrackers;
        backgroundService = json['backgroundService'] as bool? ?? backgroundService;
      }
    } catch (_) {
      // Defaults are good enough to stream.
    }
    notifyListeners();
  }

  Future<void> update({
    int? cacheMb,
    int? preloadPct,
    int? readAheadPct,
    int? connections,
    int? preloadMb,
    int? disconnectTimeout,
    int? softGateSeconds,
    int? bufferTimeoutSeconds,
    bool? autoPlay,
    bool? resumePlayback,
    bool? injectTrackers,
    bool? backgroundService,
  }) async {
    if (cacheMb != null) this.cacheMb = cacheMb;
    if (preloadPct != null) this.preloadPct = preloadPct;
    if (readAheadPct != null) this.readAheadPct = readAheadPct;
    if (connections != null) this.connections = connections;
    if (preloadMb != null) this.preloadMb = preloadMb;
    if (disconnectTimeout != null) this.disconnectTimeout = disconnectTimeout;
    if (softGateSeconds != null) this.softGateSeconds = softGateSeconds;
    if (bufferTimeoutSeconds != null) {
      this.bufferTimeoutSeconds = bufferTimeoutSeconds;
    }
    if (autoPlay != null) this.autoPlay = autoPlay;
    if (resumePlayback != null) this.resumePlayback = resumePlayback;
    if (injectTrackers != null) this.injectTrackers = injectTrackers;
    if (backgroundService != null) this.backgroundService = backgroundService;
    notifyListeners();
    await _save();
  }

  Future<void> restoreDefaults() async {
    cacheMb = 64;
    preloadPct = 10;
    readAheadPct = 40;
    connections = 40;
    preloadMb = 8;
    disconnectTimeout = 600;
    softGateSeconds = 12;
    bufferTimeoutSeconds = 90;
    autoPlay = true;
    resumePlayback = true;
    injectTrackers = true;
    backgroundService = true;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(<String, dynamic>{
          'cacheMb': cacheMb,
          'preloadPct': preloadPct,
          'readAheadPct': readAheadPct,
          'connections': connections,
          'preloadMb': preloadMb,
          'disconnectTimeout': disconnectTimeout,
          'softGateSeconds': softGateSeconds,
          'bufferTimeoutSeconds': bufferTimeoutSeconds,
          'autoPlay': autoPlay,
          'resumePlayback': resumePlayback,
          'injectTrackers': injectTrackers,
          'backgroundService': backgroundService,
        }),
      );
    } catch (_) {
      // Storage failures must never break playback.
    }
  }
}
