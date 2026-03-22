import 'package:flutter/material.dart';

/// board-go Design System — "The Modern Tactician"
///
/// Light mint theme based on the screen.png design mockup.
/// Warm orange primary, sage-mint background, teal secondary.
///
/// Usage:
///   MaterialApp(
///     theme: AppTheme.light(),
///     ...
///   )
abstract final class AppTheme {
  // ---------------------------------------------------------------------------
  // Color tokens
  // ---------------------------------------------------------------------------

  // Core palette — derived from screen.png
  static const Color primary = Color(0xFFFF7C38);       // warm orange (CTA, nav active)
  static const Color secondary = Color(0xFF3EC9A0);     // teal (ready badge, online)
  static const Color tertiary = Color(0xFF5B8FF9);      // blue accent
  static const Color error = Color(0xFFE84B4B);         // red (danger, force-end)

  // Surface hierarchy — light mint tonal layering
  static const Color background = Color(0xFFEEF5EE);            // sage-mint base
  static const Color surfaceContainerLowest = Color(0xFFF8FBF8); // near-white
  static const Color surfaceContainerLow = Color(0xFFF3F8F3);    // very light mint
  static const Color surfaceContainer = Color(0xFFFFFFFF);       // white panel/card
  static const Color surfaceContainerHigh = Color(0xFFE8F0E8);   // light mint elevated
  static const Color surfaceContainerHighest = Color(0xFFDFEBDF); // stronger mint

  // Derived / semantic tokens
  static const Color primaryContainer = Color(0xFFFFEEE4);       // light orange tint
  static const Color secondaryContainer = Color(0xFFE0F7F0);     // light teal tint
  static const Color tertiaryContainer = Color(0xFFE8EFFD);      // light blue tint
  static const Color errorContainer = Color(0xFFFFECEC);         // light red tint

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF1A7A64);
  static const Color onTertiaryContainer = Color(0xFF2A4FA0);
  static const Color onError = Color(0xFFFFFFFF);

  /// All body text — dark navy for contrast on light surfaces.
  static const Color onSurface = Color(0xFF1C2033);

  /// Placeholder text, secondary metadata.
  static const Color onSurfaceMuted = Color(0xFF7A8099);

  /// Ghost borders — use at 20% opacity only.
  static const Color outlineVariant = Color(0xFFB0BDB0);

  // Status dot colors
  static const Color onlineDot = Color(0xFF4CAF50);     // bright green
  static const Color offlineDot = Color(0xFFB0B7C6);

  // ---------------------------------------------------------------------------
  // Typography
  // ---------------------------------------------------------------------------

  static TextTheme _buildTextTheme() {
    const displayFamily = 'PlusJakartaSans';
    const bodyFamily = 'Manrope';

    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 48,
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: onSurface,
      ),
      displaySmall: TextStyle(
        fontFamily: displayFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: onSurface,
      ),
      labelLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: onSurfaceMuted,
      ),
      bodyLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: onSurfaceMuted,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Component themes
  // ---------------------------------------------------------------------------

  static CardThemeData _cardTheme() {
    return CardThemeData(
      color: surfaceContainer,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      margin: EdgeInsets.zero,
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return surfaceContainerHigh;
          }
          return primary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return onSurfaceMuted;
          }
          return onPrimary;
        }),
        overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.15)),
        elevation: WidgetStateProperty.all(0),
        minimumSize: WidgetStateProperty.all(const Size(0, 56)),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Manrope',
          ),
        ),
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme() {
    final ghostBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: outlineVariant.withValues(alpha: 0.4),
        width: 1,
      ),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: primary, width: 1.5),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      constraints: const BoxConstraints(minHeight: 52),
      border: ghostBorder,
      enabledBorder: ghostBorder,
      focusedBorder: focusBorder,
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: error, width: 2),
      ),
      hintStyle: const TextStyle(
        color: onSurfaceMuted,
        fontSize: 16,
        fontFamily: 'Manrope',
      ),
      labelStyle: const TextStyle(
        color: onSurfaceMuted,
        fontSize: 14,
        fontFamily: 'Manrope',
      ),
    );
  }

  static AppBarTheme _appBarTheme() {
    return const AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.3,
      ),
    );
  }

  static SnackBarThemeData _snackBarTheme() {
    return SnackBarThemeData(
      backgroundColor: onSurface,
      contentTextStyle: const TextStyle(
        color: background,
        fontSize: 14,
        fontFamily: 'Manrope',
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  static DialogThemeData _dialogTheme() {
    return DialogThemeData(
      backgroundColor: surfaceContainer,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: onSurface,
        height: 1.6,
      ),
    );
  }

  static ListTileThemeData _listTileTheme() {
    return const ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: onSurface,
      iconColor: onSurfaceMuted,
      minTileHeight: 56,
    );
  }

  static DividerThemeData _dividerTheme() {
    return DividerThemeData(
      color: outlineVariant.withValues(alpha: 0.3),
      thickness: 1,
      space: 1,
    );
  }

  static IconButtonThemeData _iconButtonTheme() {
    return IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(onSurfaceMuted),
        minimumSize: WidgetStateProperty.all(const Size(48, 48)),
        iconSize: WidgetStateProperty.all(22),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Public factory
  // ---------------------------------------------------------------------------

  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: error,
      onError: onError,
      errorContainer: errorContainer,
      onErrorContainer: error,
      surface: surfaceContainer,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceMuted,
      outline: outlineVariant,
      outlineVariant: outlineVariant.withValues(alpha: 0.3),
      shadow: Colors.black,
      inverseSurface: onSurface,
      onInverseSurface: background,
      inversePrimary: primaryContainer,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: _buildTextTheme(),
      cardTheme: _cardTheme(),
      elevatedButtonTheme: _elevatedButtonTheme(),
      inputDecorationTheme: _inputDecorationTheme(),
      appBarTheme: _appBarTheme(),
      snackBarTheme: _snackBarTheme(),
      dialogTheme: _dialogTheme(),
      listTileTheme: _listTileTheme(),
      dividerTheme: _dividerTheme(),
      iconButtonTheme: _iconButtonTheme(),
      splashColor: primary.withValues(alpha: 0.08),
      highlightColor: primary.withValues(alpha: 0.04),
    );
  }

  /// Backwards-compatible alias — prefer [light()].
  static ThemeData dark() => light();
}
