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

ThemeData buildMagnetTheme({Brightness brightness = Brightness.dark}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? ink : const Color(0xFFF4F8F5);
  final surface = dark ? panel : Colors.white;
  final raised = dark ? panelRaised : const Color(0xFFE7F0EA);
  final border = dark ? line : const Color(0xFFD0DED5);
  final text = dark ? Colors.white : const Color(0xFF173127);
  final secondary = dark ? muted : const Color(0xFF5C7469);
  final progressTrack = dark ? track : const Color(0xFFD6E5DB);
  final scheme = ColorScheme.fromSeed(
    seedColor: lime,
    brightness: brightness,
    surface: background,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: raised,
      contentTextStyle: TextStyle(color: text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: lime, width: 1.4),
      ),
      hintStyle: TextStyle(color: secondary),
    ),
    listTileTheme: ListTileThemeData(
      textColor: text,
      iconColor: secondary,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: lime,
      inactiveTrackColor: progressTrack,
      thumbColor: lime,
    ),
    dividerTheme: DividerThemeData(color: border),
  );
}
