import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_state.dart';
import 'messenger.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await appSettings.load();
  await appLibrary.load();
  runApp(const MagnetApp());
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
