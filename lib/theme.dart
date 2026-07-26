import 'package:flutter/material.dart';

/// Palette. Exact values, not derived — see CLAUDE.md.
///
/// Only [accent] is a saturated color and it belongs to Confirm alone. Nothing
/// else on screen competes with it, and nothing is color-coded by progress or
/// performance.
abstract final class AppColors {
  static const accent = Color(0xFF008AC9);
  static const button = Color(0xFF006E9F);
  static const onAccent = Color(0xFFFFFFFF);

  static const background = Color(0xFF0D1113);
  static const surface = Color(0xFF181D21);
  static const border = Color(0xFF2F373E);

  static const textPrimary = Color(0xFFE4E9ED);
  static const textSecondary = Color(0xFF7D878F);

  /// Set numbers. Deliberately dimmer than [textSecondary] — the number a set
  /// row is keyed by should recede behind the weight and reps.
  static const textMuted = Color(0xFF5C666E);
}

/// Minimum tap target, applied to every interactive component below.
const double _minTapTarget = 56;

/// Monospace with tabular figures, declared once.
///
/// Tabular figures are what make set rows column-align: with proportional
/// digits a `1` and a `7` take different widths and notation drifts out of
/// alignment down a card.
const TextStyle _mono = TextStyle(
  fontFamilyFallback: <String>['SF Mono', 'Menlo', 'Roboto Mono', 'monospace'],
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

/// Monospace styles for numbers and collapsed notation.
///
/// Labels and exercise names use the system font and are not served from here.
abstract final class AppText {
  /// Collapsed set notation on session cards — `@45 123-8 4-7`.
  static final TextStyle notation = _mono.copyWith(
    fontSize: 16,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  /// Set number in a set row.
  static final TextStyle setNumber = _mono.copyWith(
    fontSize: 14,
    color: AppColors.textMuted,
  );

  /// Weight and reps field contents.
  static final TextStyle input = _mono.copyWith(
    fontSize: 18,
    color: AppColors.textPrimary,
  );
}

/// Seeding alone returns a washed-out tone-80 derivative, so every slot the app
/// actually paints with is overridden to the exact palette value.
final ColorScheme _darkScheme =
    ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.button,
      onPrimary: AppColors.onAccent,
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      surfaceContainer: AppColors.surface,
      surfaceContainerHighest: AppColors.surface,
      outline: AppColors.border,
      onSurfaceVariant: AppColors.textSecondary,
    );

OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(8)),
    borderSide: BorderSide(color: color, width: width),
  );
}

/// App theme.
///
/// Dark only, permanently. There is no light palette and none is planned — the
/// app pins [ThemeMode.dark] rather than following the system.
abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _darkScheme,
      scaffoldBackgroundColor: AppColors.background,
      // Not adaptivePlatformDensity — that pulls rows in under the tap-target
      // floor on desktop-class devices.
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(_minTapTarget, _minTapTarget),
          ),
          backgroundColor: const WidgetStatePropertyAll(AppColors.button),
          foregroundColor: const WidgetStatePropertyAll(AppColors.onAccent),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.onAccent.withValues(alpha: 0.12);
            }
            return null;
          }),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, _minTapTarget)),
          foregroundColor: const WidgetStatePropertyAll(AppColors.accent),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        constraints: const BoxConstraints(minHeight: _minTapTarget),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        hintStyle: AppText.input.copyWith(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: _inputBorder(AppColors.border),
        enabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(AppColors.accent, width: 2),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: _minTapTarget,
        textColor: AppColors.textPrimary,
        iconColor: AppColors.textSecondary,
        tileColor: Colors.transparent,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
