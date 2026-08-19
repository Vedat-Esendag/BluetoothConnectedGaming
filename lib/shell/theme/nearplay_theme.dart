import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:flutter/material.dart';

/// Builds the app's [ThemeData] from NearPlay's tokens.
///
/// Every Material default that would otherwise show through — the purple seed
/// palette, the stock type ramp, square-ish corners — is replaced here, so a
/// widget that does not style itself still comes out looking like NearPlay
/// rather than like a fresh `flutter create`.
ThemeData buildNearPlayTheme() {
  const scheme = ColorScheme.dark(
    primary: NearPlayColors.brass,
    onPrimary: NearPlayColors.onBrass,
    primaryContainer: NearPlayColors.brassDeep,
    onPrimaryContainer: NearPlayColors.onBrass,
    secondary: NearPlayColors.connected,
    onSecondary: NearPlayColors.canvas,
    surface: NearPlayColors.surface,
    onSurface: NearPlayColors.textPrimary,
    surfaceContainerHighest: NearPlayColors.surfaceRaised,
    onSurfaceVariant: NearPlayColors.textSecondary,
    outline: NearPlayColors.border,
    error: NearPlayColors.alert,
    onError: NearPlayColors.canvas,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: NearPlayColors.canvas,
    canvasColor: NearPlayColors.canvas,
    dividerColor: NearPlayColors.border,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      displaySmall: NearPlayText.display,
      headlineMedium: NearPlayText.title,
      titleLarge: NearPlayText.title,
      titleMedium: NearPlayText.subtitle,
      bodyMedium: NearPlayText.body,
      bodySmall: NearPlayText.caption,
      labelLarge: NearPlayText.label,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: NearPlayColors.canvas,
      foregroundColor: NearPlayColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: NearPlayText.title,
    ),
    cardTheme: const CardThemeData(
      color: NearPlayColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: NearPlayRadius.cardBorder,
        side: BorderSide(color: NearPlayColors.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: NearPlayColors.textSecondary,
      titleTextStyle: NearPlayText.subtitle,
      subtitleTextStyle: NearPlayText.body,
      contentPadding: EdgeInsets.symmetric(
        horizontal: NearPlaySpacing.lg,
        vertical: NearPlaySpacing.sm,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NearPlayColors.brass,
        foregroundColor: NearPlayColors.onBrass,
        textStyle: NearPlayText.label,
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(
          borderRadius: NearPlayRadius.cardBorder,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NearPlayColors.textPrimary,
        textStyle: NearPlayText.label,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: NearPlayColors.border),
        shape: const RoundedRectangleBorder(
          borderRadius: NearPlayRadius.cardBorder,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: NearPlayColors.brass,
        textStyle: NearPlayText.label,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: NearPlayColors.surface,
      hintStyle: NearPlayText.body,
      labelStyle: NearPlayText.body,
      contentPadding: EdgeInsets.symmetric(
        horizontal: NearPlaySpacing.lg,
        vertical: NearPlaySpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: NearPlayRadius.cardBorder,
        borderSide: BorderSide(color: NearPlayColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: NearPlayRadius.cardBorder,
        borderSide: BorderSide(color: NearPlayColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: NearPlayRadius.cardBorder,
        borderSide: BorderSide(color: NearPlayColors.brass, width: 2),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: NearPlayColors.surfaceRaised,
      side: BorderSide(color: NearPlayColors.border),
      labelStyle: NearPlayText.label,
      shape: RoundedRectangleBorder(
        borderRadius: NearPlayRadius.pillBorder,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: NearPlaySpacing.md,
        vertical: NearPlaySpacing.sm,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: NearPlayColors.brass,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: NearPlayColors.surfaceRaised,
      contentTextStyle: NearPlayText.body,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
