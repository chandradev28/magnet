import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MagnetEntry {
  const MagnetEntry({
    required this.uri,
    required this.name,
    required this.savedAt,
  });

  factory MagnetEntry.fromJson(Map<String, dynamic> json) => MagnetEntry(
        uri: json['uri'] as String? ?? '',
        name: json['name'] as String? ?? 'Magnet',
        savedAt: json['savedAt'] as int? ?? 0,
      );

  final String uri;
  final String name;
  final int savedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uri': uri,
        'name': name,
        'savedAt': savedAt,
      };
}

/// Resume positions are keyed by info-hash, not by the full magnet, so the same
/// content still resumes when the tracker list in the link differs.
String infoHashOf(String magnet) {
  final match = RegExp(r'xt=urn:btih:([a-zA-Z0-9]+)').firstMatch(magnet);
  return (match?.group(1) ?? magnet).toLowerCase();
}

class LibraryStore extends ChangeNotifier {
  static const _savedKey = 'magnet.saved.v2';
  static const _historyKey = 'magnet.history.v2';
  static const _positionsKey = 'magnet.positions.v1';

  List<MagnetEntry> saved = <MagnetEntry>[];
  List<MagnetEntry> history = <MagnetEntry>[];
  Map<String, int> positions = <String, int>{};

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = _decode(prefs.getString(_savedKey));
      history = _decode(prefs.getString(_historyKey));
      final rawPositions = prefs.getString(_positionsKey);
      if (rawPositions != null && rawPositions.isNotEmpty) {
        final decoded = jsonDecode(rawPositions) as Map<String, dynamic>;
        positions = decoded.map(
          (key, value) => MapEntry(key, value is int ? value : 0),
        );
      }
    } catch (_) {
      // First run, or no platform channel (tests).
    }
    notifyListeners();
  }

  List<MagnetEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <MagnetEntry>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MagnetEntry.fromJson)
          .where((entry) => entry.uri.isNotEmpty)
          .toList();
    } catch (_) {
      return <MagnetEntry>[];
    }
  }

  bool isSaved(String uri) => saved.any((entry) => entry.uri == uri);

  Future<void> toggleSaved(MagnetEntry entry) async {
    if (isSaved(entry.uri)) {
      saved.removeWhere((item) => item.uri == entry.uri);
    } else {
      saved.insert(0, entry);
    }
    notifyListeners();
    await _save();
  }

  Future<void> addHistory(MagnetEntry entry) async {
    history = <MagnetEntry>[
      entry,
      ...history.where((item) => item.uri != entry.uri),
    ].take(60).toList();
    notifyListeners();
    await _save();
  }

  Future<void> removeHistory(String uri) async {
    history.removeWhere((item) => item.uri == uri);
    notifyListeners();
    await _save();
  }

  Future<void> clearHistory() async {
    history = <MagnetEntry>[];
    notifyListeners();
    await _save();
  }

  int positionFor(String uri, int fileIndex) =>
      positions['${infoHashOf(uri)}:$fileIndex'] ?? 0;

  int bestPositionFor(String uri) {
    final prefix = '${infoHashOf(uri)}:';
    var best = 0;
    positions.forEach((key, value) {
      if (key.startsWith(prefix) && value > best) best = value;
    });
    return best;
  }

  Future<void> remember(String uri, int fileIndex, int seconds) async {
    positions['${infoHashOf(uri)}:$fileIndex'] = seconds;
    await _save();
  }

  Future<void> forgetPositions(String uri) async {
    final prefix = '${infoHashOf(uri)}:';
    positions.removeWhere((key, value) => key.startsWith(prefix));
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _savedKey,
        jsonEncode(saved.map((entry) => entry.toJson()).toList()),
      );
      await prefs.setString(
        _historyKey,
        jsonEncode(history.map((entry) => entry.toJson()).toList()),
      );
      await prefs.setString(_positionsKey, jsonEncode(positions));
    } catch (_) {
      // Ignore storage failures.
    }
  }
}
