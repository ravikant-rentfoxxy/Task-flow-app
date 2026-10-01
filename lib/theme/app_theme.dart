import 'package:flutter/material.dart';

/// Lime-on-navy tokens shared by every screen.
class Brand {
  static const bg = Color(0xFFF8F9FA);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2E8F0);
  static const ink = Color(0xFF111827);
  static const inkSoft = Color(0xFF374151);
  static const muted = Color(0xFF6B7280);
  static const faint = Color(0xFF9CA3AF);
  static const primary = Color(0xFF0F172A);
  static const primaryDeep = Color(0xFF0F172A);
  static const primarySoft = Color(0xFFF4FCE3);
  static const field = Color(0xFFF3F4F6);
  static const sky = Color(0xFF2B9BE8);
  static const skySoft = Color(0xFFDDEFFC);
  static const red = Color(0xFFC81E1E);
  static const redSoft = Color(0xFFFDE8E8);
  static const redPanel = Color(0xFFFCEEF0);
  static const amber = Color(0xFFB7791F);
  static const amberSoft = Color(0xFFFEF3D7);
  static const slate = Color(0xFF5B6170);
  static const slateSoft = Color(0xFFEAEDF2);
  static const green = Color(0xFF15803D);
  static const greenSoft = Color(0xFFDCF7E6);

  // Lime-on-navy tokens (dashboard redesign).
  static const lime = Color(0xFFD4F436);
  static const limeDim = Color(0xFFC2E22F);
  static const limeLight = Color(0xFFF4FCE3);
  static const navy = Color(0xFF0F172A);
  static const surface = Color(0xFFF8F9FA);
  static const surfaceLow = Color(0xFFF3F4F6);
  static const surfaceMid = Color(0xFFEAEDF2);
  static const outline = Color(0xFFE2E8F0);
  static const onVariant = Color(0xFF475569);

  static const radius = 18.0;

  static List<BoxShadow> get shadow => [
    BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4)),
  ];
}

/// TaskFlow light palette, aligned with [Brand]: light grey background, ink text,
/// navy primary with lime accents, coral reserved for urgency.
class TF {
  static const paper = Brand.bg;
  static const surface = Color(0xFFFFFFFF);
  static const sunken = Brand.field;
  static const line = Brand.line;
  static const ink = Brand.ink;
  static const inkSoft = Brand.inkSoft;
  static const muted = Brand.muted;
  static const faint = Brand.faint;

  static const primary = Brand.primary;
  static const primarySoft = Brand.primarySoft;
  static const primaryDeep = Brand.primaryDeep;

  static const coral = Color(0xFFE8553B);
  static const coralSoft = Color(0xFFFDECE7);
  static const amber = Color(0xFFD9901A);
  static const amberSoft = Color(0xFFFBF1DD);
  static const sky = Color(0xFF2F7FC1);
  static const skySoft = Color(0xFFE5F0FA);
  static const violet = Color(0xFF6D5BD0);
  static const violetSoft = Color(0xFFEEEBFB);
  static const green = Color(0xFF1E9E61);
  static const greenSoft = Color(0xFFE2F5EA);

  static const radius = Brand.radius;
  static const radiusSm = 10.0;

  static ({Color fg, Color bg}) status(String s) => switch (s) {
        'ASSIGNED' => (fg: const Color(0xFFC2410C), bg: const Color(0xFFFFEEE2)),
        'DISCUSS' => (fg: violet, bg: violetSoft),
        'ACKNOWLEDGED' => (fg: sky, bg: skySoft),
        'IN_PROGRESS' => (fg: primary, bg: primarySoft),
        'WAITING_FOR_INPUT' => (fg: const Color(0xFF0E7490), bg: const Color(0xFFE0F4F8)),
        'INPUT_PROVIDED' => (fg: const Color(0xFF4D7C0F), bg: const Color(0xFFEDF6DD)),
        'DONE' => (fg: green, bg: greenSoft),
        'CANCELLED' => (fg: muted, bg: sunken),
        'REJECTED' => (fg: const Color(0xFFBE123C), bg: const Color(0xFFFDE8EE)),
        'ESCALATED' => (fg: coral, bg: coralSoft),
        _ => (fg: muted, bg: sunken),
      };

  static Color priority(String p) => switch (p) {
        'URGENT' => coral,
        'HIGH' => amber,
        'NORMAL' => muted,
        _ => faint,
      };

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: ink,
      error: coral,
    ).copyWith(
      surfaceContainerLowest: surface,
      surfaceContainerLow: paper,
      surfaceContainer: sunken,
      outline: line,
      outlineVariant: line,
      primaryContainer: primarySoft,
      onPrimaryContainer: primaryDeep,
    );

    const text = TextTheme(
      displaySmall: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: ink),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: ink),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: ink),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: ink),
      titleSmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
      bodyLarge: TextStyle(fontSize: 14, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontSize: 13, height: 1.45, color: inkSoft),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, color: muted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: inkSoft),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: muted),
    );

    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        shape: Border(bottom: BorderSide(color: line)),
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: line),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: rounded,
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: const BorderSide(color: line),
          backgroundColor: surface,
          shape: rounded,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: rounded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sunken,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: faint, fontSize: 13),
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: coral)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary,
        side: const BorderSide(color: line),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: inkSoft),
        secondaryLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.lime),
        checkmarkColor: Brand.lime,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Brand.navy : Brand.onVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Brand.navy : Brand.onVariant, size: 23),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: Brand.lime,
        selectedIconTheme: IconThemeData(color: Brand.navy),
        unselectedIconTheme: IconThemeData(color: Brand.onVariant),
        selectedLabelTextStyle: TextStyle(color: Brand.navy, fontWeight: FontWeight.w700, fontSize: 11.5),
        unselectedLabelTextStyle: TextStyle(color: Brand.onVariant, fontSize: 11.5),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: line,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: line)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: faint, width: 1.5),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        indicatorColor: primary,
        dividerColor: line,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
      listTileTheme: const ListTileThemeData(iconColor: inkSoft),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}
