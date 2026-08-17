import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to our own Kotlin code: incoming magnet: intents and the foreground
/// service that keeps the torrent session alive outside the app.
class NativeBridge {
  const NativeBridge._();

  static const MethodChannel _methods = MethodChannel('magnet/native');
  static const EventChannel _events = EventChannel('magnet/links');

  static bool get supported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// The magnet the app was cold-started with, if any.
  static Future<String?> initialLink() async {
    if (!supported) return null;
    try {
      return await _methods.invokeMethod<String>('getInitialLink');
    } catch (_) {
      return null;
    }
  }

  /// Magnets delivered while the app is already running.
  static Stream<String> links() {
    if (!supported) return Stream<String>.empty();
    return _events.receiveBroadcastStream().map((event) => '$event');
  }

  static Future<void> startService(String title, String body) async {
    if (!supported) return;
    try {
      await _methods.invokeMethod<void>('startService', <String, String>{
        'title': title,
        'body': body,
      });
    } catch (_) {
      // The service is a convenience, never a requirement.
    }
  }

  static Future<void> stopService() async {
    if (!supported) return;
    try {
      await _methods.invokeMethod<void>('stopService');
    } catch (_) {
      // Already gone.
    }
  }
}
