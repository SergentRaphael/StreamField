import 'package:flutter/material.dart';

const kBg = Color(0xFF0E1116);
const kSurface = Color(0xFF161B22);
const kSurface2 = Color(0xFF1F2630);
const kAccent = Color(0xFF3DDC97);
const kMuted = Color(0xFF8B949E);
const kDanger = Color(0xFFF85149);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kAccent,
    onPrimary: Colors.black,
    surface: kSurface,
  );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    // Surbrillance bien visible quand on navigue à la télécommande ou au clavier.
    focusColor: kAccent.withAlpha(60),
    hoverColor: Colors.white.withAlpha(12),
    dividerColor: Colors.white.withAlpha(25),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    listTileTheme: ListTileThemeData(
      shape: rounded,
      selectedColor: kAccent,
      selectedTileColor: kAccent.withAlpha(28),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: rounded,
      side: BorderSide.none,
      backgroundColor: kSurface,
      selectedColor: kAccent.withAlpha(45),
    ),
    popupMenuTheme: PopupMenuThemeData(color: kSurface2, shape: rounded),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
