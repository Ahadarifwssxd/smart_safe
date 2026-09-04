import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design_tokens.dart';

class ThemeColors {
  final Color bg;
  final Color bg2;
  final Color bg3;
  final Color nav;
  final Color border;

  final Color accent;
  final Color accentLight;
  final Color accentDark;

  final Color textPrimary;
  final Color textMuted;
  final Color textDim;

  final Color success;
  final Color warning;

  // Legacy mappings for safe compilation during refactoring
  final Color red;
  final Color redLight;
  final Color teal;
  final Color tealLight;
  final Color amber;
  final Color purple;
  final Color green;
  final Color white;
  final Color offW;
  final Color muted;
  final Color dim;
  final Color blue;
  final Color glow;
  final Color yellow;
  final Color orange;

  const ThemeColors({
    required this.bg,
    required this.bg2,
    required this.bg3,
    required this.nav,
    required this.border,
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.textPrimary,
    required this.textMuted,
    required this.textDim,
    required this.success,
    required this.warning,
    required this.red,
    required this.redLight,
    required this.teal,
    required this.tealLight,
    required this.amber,
    required this.purple,
    required this.green,
    required this.white,
    required this.offW,
    required this.muted,
    required this.dim,
    required this.blue,
    required this.glow,
    required this.yellow,
    required this.orange,
  });
}

class AppColors {
  static Color get bg => AppTheme.colors.bg;
  static Color get bg2 => AppTheme.colors.bg2;
  static Color get bg3 => AppTheme.colors.bg3;
  static Color get nav => AppTheme.colors.nav;
  static Color get border => AppTheme.colors.border;

  static Color get accent => AppTheme.colors.accent;
  static Color get accentLight => AppTheme.colors.accentLight;
  static Color get accentDark => AppTheme.colors.accentDark;

  static Color get textPrimary => AppTheme.colors.textPrimary;
  static Color get textMuted => AppTheme.colors.textMuted;
  static Color get textDim => AppTheme.colors.textDim;

  static Color get success => AppTheme.colors.success;
  static Color get warning => AppTheme.colors.warning;

  // New spacing constants (4pt grid)
  static const double spaceXs  = 4.0;
  static const double spaceSm  = 8.0;
  static const double spaceMd  = 16.0;
  static const double spaceLg  = 24.0;
  static const double spaceXl  = 32.0;
  static const double space2xl = 48.0;

  // Legacy compatibility mappings
  static Color get red => AppTheme.colors.red;
  static Color get redLight => AppTheme.colors.redLight;
  static Color get teal => AppTheme.colors.teal;
  static Color get tealLight => AppTheme.colors.tealLight;
  static Color get amber => AppTheme.colors.amber;
  static Color get purple => AppTheme.colors.purple;
  static Color get green => AppTheme.colors.green;
  static Color get white => AppTheme.colors.white;
  static Color get offW => AppTheme.colors.offW;
  static Color get offWhite => AppTheme.colors.offW;
  static Color get muted => AppTheme.colors.muted;
  static Color get dim => AppTheme.colors.dim;
  static Color get blue => AppTheme.colors.blue;
  static Color get glow => AppTheme.colors.glow;
  static Color get card => AppTheme.colors.bg2;
  static Color get panel => AppTheme.colors.bg3;
  static Color get yellow => AppTheme.colors.yellow;
  static Color get orange => AppTheme.colors.orange;

  static Gradient get sosGradient => AppTheme.sosGradient;
}

class C {
  static Color get bg => AppTheme.colors.bg;
  static Color get bg2 => AppTheme.colors.bg2;
  static Color get bg3 => AppTheme.colors.bg3;
  static Color get nav => AppTheme.colors.nav;
  static Color get border => AppTheme.colors.border;

  static Color get accent => AppTheme.colors.accent;
  static Color get accentLight => AppTheme.colors.accentLight;
  static Color get accentDark => AppTheme.colors.accentDark;

  static Color get textPrimary => AppTheme.colors.textPrimary;
  static Color get textMuted => AppTheme.colors.textMuted;
  static Color get textDim => AppTheme.colors.textDim;

  static Color get success => AppTheme.colors.success;
  static Color get warning => AppTheme.colors.warning;

  // New spacing constants (4pt grid)
  static const double spaceXs  = 4.0;
  static const double spaceSm  = 8.0;
  static const double spaceMd  = 16.0;
  static const double spaceLg  = 24.0;
  static const double spaceXl  = 32.0;
  static const double space2xl = 48.0;

  // Legacy compatibility mappings
  static Color get red => AppTheme.colors.red;
  static Color get redLight => AppTheme.colors.redLight;
  static Color get teal => AppTheme.colors.teal;
  static Color get tealLight => AppTheme.colors.tealLight;
  static Color get amber => AppTheme.colors.amber;
  static Color get purple => AppTheme.colors.purple;
  static Color get green => AppTheme.colors.green;
  static Color get white => AppTheme.colors.white;
  static Color get offW => AppTheme.colors.offW;
  static Color get muted => AppTheme.colors.muted;
  static Color get dim => AppTheme.colors.dim;
  static Color get blue => AppTheme.colors.blue;
  static Color get glow => AppTheme.colors.glow;
  static Color get card => AppTheme.colors.bg2;
  static Color get panel => AppTheme.colors.bg3;
  static Color get offWhite => AppTheme.colors.offW;
  static Color get yellow => AppTheme.colors.yellow;
  static Color get orange => AppTheme.colors.orange;
}

class AppTheme {
  // Default to LIGHT theme — clean, modern, judge-friendly. Users can toggle to
  // dark, and their choice is remembered.
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

  /// The user's chosen APP theme (light by default). The admin dashboard always
  /// renders dark regardless — this is only the user-app preference.
  static ThemeMode userAppMode = ThemeMode.light;

  static bool get isDark => themeNotifier.value == ThemeMode.dark;

  /// Load the saved app theme at startup.
  static Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dark = prefs.getBool('app_dark_mode') ?? false;
      userAppMode = dark ? ThemeMode.dark : ThemeMode.light;
      themeNotifier.value = userAppMode;
    } catch (_) {}
  }

  /// Set + persist the user's app theme choice.
  static void setUserAppMode(ThemeMode mode) {
    userAppMode = mode;
    themeNotifier.value = mode;
    SharedPreferences.getInstance()
        .then((p) => p.setBool('app_dark_mode', mode == ThemeMode.dark))
        .catchError((_) => false);
  }

  static void toggle() {
    setUserAppMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  // Radius Constants
  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 20.0;
  static const radiusXl = 28.0;

  static ThemeColors get colors => isDark ? _darkColors : _lightColors;

  static const _darkColors = ThemeColors(
    bg: Color(0xFF0B0B12),
    bg2: Color(0xFF15151F),
    bg3: Color(0xFF1E1E2C),
    nav: Color(0xFF090910),
    border: Color(0xFF2A2A3A),
    // Primary brand = INDIGO (brighter on dark bg for contrast).
    accent: Color(0xFF818CF8),
    accentLight: Color(0xFFA5B4FC),
    accentDark: Color(0xFF4F46E5),
    textPrimary: Color(0xFFF1F5F9),
    textMuted: Color(0xFF9A9AA6),
    textDim: Color(0xFF63636E),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),

    // EMERGENCY red — reserved for SOS / crash / shake / alerts (safety identity).
    red: Color(0xFFEF4444),
    redLight: Color(0xFFFCA5A5),
    teal: Color(0xFF818CF8),
    tealLight: Color(0xFFA5B4FC),
    amber: Color(0xFFF59E0B),
    purple: Color(0xFF818CF8),
    green: Color(0xFF22C55E),
    white: Color(0xFFF1F5F9),
    offW: Color(0xFF71717A),
    muted: Color(0xFF71717A),
    dim: Color(0xFF52525B),
    blue: Color(0xFF818CF8),
    glow: Color(0xFF818CF8),
    yellow: Color(0xFFEAB308),
    orange: Color(0xFFF97316),
  );

  static const _lightColors = ThemeColors(
    bg: Color(0xFFF6F7FB),
    bg2: Color(0xFFFFFFFF),
    bg3: Color(0xFFEEF0F6),
    nav: Color(0xFFFFFFFF),
    border: Color(0xFFDDE0EA),
    // Primary brand = INDIGO.
    accent: Color(0xFF6366F1),
    accentLight: Color(0xFFA5B4FC),
    accentDark: Color(0xFF4338CA),
    // Refined dark slate (not pure/near black) — softer + more premium on the
    // eyes app-wide, while staying bold and prominent on the light background.
    textPrimary: Color(0xFF2B2B3C),
    textMuted: Color(0xFF64647A),
    textDim: Color(0xFF9A9AB0),
    success: Color(0xFF16A34A),
    warning: Color(0xFFEA8C00),

    // EMERGENCY red — reserved for SOS / crash / shake / alerts (safety identity).
    red: Color(0xFFEF4444),
    redLight: Color(0xFFFCA5A5),
    teal: Color(0xFF6366F1),
    tealLight: Color(0xFFA5B4FC),
    amber: Color(0xFFEA8C00),
    purple: Color(0xFF6366F1),
    green: Color(0xFF16A34A),
    white: Color(0xFF1A1A24),
    offW: Color(0xFF64647A),
    muted: Color(0xFF64647A),
    dim: Color(0xFF9A9AB0),
    blue: Color(0xFF6366F1),
    glow: Color(0xFF6366F1),
    yellow: Color(0xFFEAB308),
    orange: Color(0xFFF97316),
  );

  // Deep, serious crimson for the SOS button / shield — reads as urgent and
  // professional (not a bright "cartoon" red), and stays consistent app-wide.
  static Gradient get sosGradient => const LinearGradient(
        colors: [Color(0xFFF87171), Color(0xFFEF4444)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Gradient get primaryGradient => LinearGradient(
        colors: [colors.accent, colors.accentDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Gradient get tealGradient => LinearGradient(
        colors: [colors.accent, colors.accentLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Gradient get cardGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.bg2,
          colors.bg3,
        ],
      );

  static Gradient get heroGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colors.accent.withValues(alpha: 0.15),
          colors.bg,
        ],
      );

  static List<BoxShadow> cardShadow([Color? tint]) => isDark
      ? [
          BoxShadow(
            color: (tint ?? colors.accent).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ]
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ];

  static List<BoxShadow> glowShadow(Color color, {double blur = 28}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.45),
          blurRadius: blur,
          spreadRadius: 2,
        ),
      ];

  static TextStyle get displayFont => DesignTokens.display;
  static TextStyle get bodyFont => DesignTokens.body;

  static TextTheme _buildTextTheme({required Brightness brightness}) {
    final c = brightness == Brightness.dark ? _darkColors : _lightColors;
    final base = GoogleFonts.interTextTheme(
      brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );
    return base.copyWith(
      displayLarge: DesignTokens.display.copyWith(color: c.textPrimary),
      headlineMedium: DesignTokens.h1.copyWith(color: c.textPrimary),
      titleLarge: DesignTokens.h2.copyWith(color: c.textPrimary),
      titleMedium: DesignTokens.h3.copyWith(color: c.textPrimary),
      bodyLarge: DesignTokens.bodyStrong.copyWith(color: c.textMuted),
      bodyMedium: DesignTokens.body.copyWith(color: c.textMuted),
      labelLarge: DesignTokens.label.copyWith(color: c.textPrimary),
      labelSmall: DesignTokens.caption.copyWith(color: c.textMuted),
    );
  }

  // Memoized ThemeData — `dark`/`light` used to be getters that rebuilt the
  // ENTIRE theme (≈20 sub-themes + text theme + gradients) on every access,
  // and they're read on every MaterialApp rebuild. Built once, reused forever.
  static ThemeData? _darkTheme;
  static ThemeData? _lightTheme;

  static ThemeData get dark => _darkTheme ??= _buildThemeData(Brightness.dark);
  static ThemeData get light => _lightTheme ??= _buildThemeData(Brightness.light);

  static ThemeData get themeData => isDark ? dark : light;

  static ThemeData _buildThemeData(Brightness brightness) {
    final c = brightness == Brightness.dark ? _darkColors : _lightColors;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accent,
      onSecondary: Colors.white,
      surface: c.bg2,
      onSurface: c.textPrimary,
      // Errors are red everywhere (validation, error states) — clear and standard.
      error: c.red,
      onError: Colors.white,
      tertiary: c.accent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: GoogleFonts.inter().fontFamily,
      scaffoldBackgroundColor: c.bg,
      colorScheme: scheme,
      textTheme: _buildTextTheme(brightness: brightness),
      dividerColor: c.border.withValues(alpha: 0.6),
      splashColor: c.accent.withValues(alpha: 0.12),
      highlightColor: c.accent.withValues(alpha: 0.06),
      // One smooth slide-up + fade for EVERY route push across the app, so
      // plain MaterialPageRoute screens feel as polished as darkRoute ones.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: _SmoothPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _SmoothPageTransitionsBuilder(),
          TargetPlatform.linux: _SmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: _SmoothPageTransitionsBuilder(),
          TargetPlatform.windows: _SmoothPageTransitionsBuilder(),
        },
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.bg.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(DesignTokens.radius32),
            bottomRight: Radius.circular(DesignTokens.radius32),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.bg2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.0),
          side: BorderSide(color: c.border.withValues(alpha: 0.7)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: DesignTokens.h2.copyWith(color: c.textPrimary),
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // A soft accent-tinted shadow gives buttons a premium "floating" feel.
          elevation: 3,
          shadowColor: c.accent.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space24,
            vertical: 15.0,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14.0)),
          ),
          backgroundColor: c.accent,
          foregroundColor: Colors.white,
          textStyle: DesignTokens.bodyStrong,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accent,
          side: BorderSide(color: c.accent.withValues(alpha: 0.5)),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14.0)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.bg3.withValues(alpha: 0.65),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space16, 
          vertical: DesignTokens.space16,
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14.0)),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14.0)),
          borderSide: BorderSide(color: c.border.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14.0)),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        // Validation errors are RED (universal convention) so a required/invalid
        // field is instantly obvious — border AND the message text below it.
        errorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14.0)),
          borderSide: BorderSide(color: c.red, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14.0)),
          borderSide: BorderSide(color: c.red, width: 1.6),
        ),
        errorStyle: DesignTokens.body.copyWith(
          color: c.red,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        labelStyle: DesignTokens.body.copyWith(color: c.textMuted),
        hintStyle: DesignTokens.body.copyWith(color: c.textMuted.withValues(alpha: 0.85)),
        prefixIconColor: c.textMuted,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.bg3,
        contentTextStyle: DesignTokens.bodyStrong.copyWith(color: c.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14.0)),
          side: BorderSide(color: c.border),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.textDim,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.textDim,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.bg2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(DesignTokens.radius32)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14.0)),
          side: BorderSide(color: c.border),
        ),
      ),
      // ── Global premium consistency touches ────────────────────────────────
      // Every spinner / loader across the app now uses the brand accent, so
      // loading states feel on-brand instead of default blue.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.bg3,
        circularTrackColor: c.bg3.withValues(alpha: 0.4),
      ),
      // Themed tooltips (dark card + border) instead of the default black slab.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        textStyle: DesignTokens.body.copyWith(color: c.textPrimary, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      // Consistent chips (choice/filter) matching the card system.
      chipTheme: ChipThemeData(
        backgroundColor: c.bg3,
        selectedColor: c.accent.withValues(alpha: 0.18),
        side: BorderSide(color: c.border),
        labelStyle: DesignTokens.body.copyWith(color: c.textPrimary, fontSize: 12.5),
        secondaryLabelStyle: DesignTokens.body.copyWith(color: c.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      // Selected list rows / tiles pick up the brand accent tint.
      listTileTheme: ListTileThemeData(
        iconColor: c.textMuted,
        selectedColor: c.accent,
        selectedTileColor: c.accent.withValues(alpha: 0.10),
      ),
    );
  }
}

/// App-wide page transition: a gentle slide-up + fade for the incoming screen.
/// Used by [AppTheme] so every navigation (even plain MaterialPageRoute) is
/// smooth and consistent.
class _SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
