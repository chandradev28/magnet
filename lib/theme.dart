import 'package:flutter/material.dart';

const ink = Color(0xFF07110E);
const panel = Color(0xFF10221D);
const panelRaised = Color(0xFF142B24);
const line = Color(0xFF244138);
const lime = Color(0xFFA9FF62);
const muted = Color(0xFF8CA9A0);
const danger = Color(0xFFFF8A6B);
const track = Color(0xFF203C32);
const chipBorder = Color(0xFF2B4B3E);
const errorPanel = Color(0xFF2A1717);

ThemeData buildMagnetTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: lime,
    brightness: Brightness.dark,
    surface: ink,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: ink,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: ink,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: panelRaised,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: lime, width: 1.4),
      ),
      hintStyle: const TextStyle(color: muted),
    ),
    cardTheme: CardThemeData(
      color: panel,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: line),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: Colors.white,
      iconColor: muted,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: lime,
      inactiveTrackColor: track,
      thumbColor: lime,
    ),
    dividerTheme: const DividerThemeData(color: line),
  );
}
