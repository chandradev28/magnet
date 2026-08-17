import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_state.dart';
import 'engine_controller.dart';
import 'messenger.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

void main() {
  // libtorrent and libmpv report their real failures - tracker errors,
  // listen-port failures, DHT trouble, codec problems - through print(), with
  // no API to read them back. Run the app inside a Zone that copies those
  // lines into the engine log so Diagnostics can show why a magnet never
  // found a peer, instead of leaving us to guess.
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      MediaKit.ensureInitialized();
      await appSettings.load();
      await appLibrary.load();
      runApp(const MagnetApp());
    },
    (error, stack) => logNativeLine('Unhandled error: $error'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        logNativeLine(line);
      },
    ),
  );
}

class MagnetApp extends StatelessWidget {
  const MagnetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'magnet',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: buildMagnetTheme(),
      home: const HomeShell(),
    );
  }
}
