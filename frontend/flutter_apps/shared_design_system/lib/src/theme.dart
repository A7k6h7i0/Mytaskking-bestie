import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

/// Premium, Lark-grade Material 3 theme. Mirrors the React web design tokens.
class BestieTheme {
  static ThemeData light() => _build(brightness: Brightness.light);
  static ThemeData dark() => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    // Palette resolves per-brightness so the same theme reads through tokens.
    final cBg = isDark ? BestieTokens.cBgDark : BestieTokens.cBg;
    final cSurface = isDark ? BestieTokens.cSurfaceDark : BestieTokens.cSurface;
    final cSurface1 =
        isDark ? BestieTokens.cSurface1Dark : BestieTokens.cSurface1;
    final cSurface2 =
        isDark ? BestieTokens.cSurface2Dark : BestieTokens.cSurface2;
    final cSurface3 =
        isDark ? BestieTokens.cSurface3Dark : BestieTokens.cSurface3;
    final cBorder = isDark ? BestieTokens.cBorderDark : BestieTokens.cBorder;
    final cBorderStrong =
        isDark ? BestieTokens.cBorderStrongDark : BestieTokens.cBorderStrong;
    final cText = isDark ? BestieTokens.cTextDark : BestieTokens.cText;
    final cTextSoft =
        isDark ? BestieTokens.cTextSoftDark : BestieTokens.cTextSoft;
    final cTextMuted =
        isDark ? BestieTokens.cTextMutedDark : BestieTokens.cTextMuted;
    final cBrandSoft =
        isDark ? BestieTokens.cBrandSoftDark : BestieTokens.cBrandSoft;
    final cAccentSoft =
        isDark ? BestieTokens.cAccentSoftDark : BestieTokens.cAccentSoft;
    final cDangerSoft =
        isDark ? BestieTokens.cDangerSoftDark : BestieTokens.cDangerSoft;

    final baseText = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: cText,
      displayColor: cText,
    );

    final text = baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
          fontWeight: BestieTokens.fwBold, letterSpacing: BestieTokens.lsTight),
      displayMedium: baseText.displayMedium?.copyWith(
          fontWeight: BestieTokens.fwBold, letterSpacing: BestieTokens.lsTight),
      displaySmall: baseText.displaySmall?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsTight),
      headlineLarge: baseText.headlineLarge?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsTight),
      headlineMedium: baseText.headlineMedium?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsSnug),
      headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsSnug),
      titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsSnug),
      titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsNormal),
      titleSmall: baseText.titleSmall?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsNormal),
      bodyLarge: baseText.bodyLarge?.copyWith(
          letterSpacing: BestieTokens.lsNormal, height: 1.5, fontSize: 15.5),
      bodyMedium: baseText.bodyMedium?.copyWith(
          letterSpacing: BestieTokens.lsNormal, height: 1.5, fontSize: 14.5),
      bodySmall: baseText.bodySmall?.copyWith(
          color: cTextMuted,
          letterSpacing: BestieTokens.lsNormal,
          fontSize: 12.5),
      labelLarge: baseText.labelLarge?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsNormal),
      labelMedium: baseText.labelMedium?.copyWith(
          fontWeight: BestieTokens.fwSemibold,
          letterSpacing: BestieTokens.lsNormal),
      labelSmall: baseText.labelSmall
          ?.copyWith(fontWeight: BestieTokens.fwSemibold, letterSpacing: 0.4),
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: BestieTokens.cBrand,
      brightness: brightness,
    ).copyWith(
      primary: BestieTokens.cBrand,
      onPrimary: BestieTokens.cTextInvert,
      primaryContainer: cBrandSoft,
      onPrimaryContainer:
          isDark ? BestieTokens.cTextDark : BestieTokens.cBrandStrong,
      secondary: BestieTokens.cAccent,
      onSecondary: BestieTokens.cTextInvert,
      secondaryContainer: cAccentSoft,
      surface: cSurface,
      onSurface: cText,
      surfaceContainerLowest: cSurface1,
      surfaceContainerLow: cSurface1,
      surfaceContainer: cSurface2,
      surfaceContainerHigh: cSurface3,
      outline: cBorderStrong,
      outlineVariant: cBorder,
      error: BestieTokens.cDanger,
      errorContainer: cDangerSoft,
      onSurfaceVariant: cTextMuted,
    );

    final overlay = isDark
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          );

    return base.copyWith(
      scaffoldBackgroundColor: cSurface,
      colorScheme: colorScheme,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _PremiumPageTransitionBuilder(),
        TargetPlatform.iOS: _PremiumPageTransitionBuilder(),
        TargetPlatform.macOS: _PremiumPageTransitionBuilder(),
        TargetPlatform.windows: _PremiumPageTransitionBuilder(),
        TargetPlatform.linux: _PremiumPageTransitionBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: cSurface.withOpacity(0.78),
        foregroundColor: cText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        titleTextStyle: text.titleLarge
            ?.copyWith(fontWeight: BestieTokens.fwBold, color: cText),
        systemOverlayStyle: overlay,
        toolbarHeight: BestieTokens.topbarH,
      ),
      cardTheme: CardThemeData(
        color: cSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rLg),
          side: BorderSide(color: cBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cSurface,
        hintStyle:
            TextStyle(color: cTextMuted, fontWeight: BestieTokens.fwRegular),
        labelStyle:
            TextStyle(color: cTextSoft, fontWeight: BestieTokens.fwMedium),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: BorderSide(color: cBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: BorderSide(color: cBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cBrand, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cDanger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cDanger, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BestieTokens.cBrand,
          foregroundColor: BestieTokens.cTextInvert,
          elevation: 0,
          shadowColor: BestieTokens.cBrand.withOpacity(0.25),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BestieTokens.rSm)),
          textStyle: const TextStyle(
              fontWeight: BestieTokens.fwSemibold,
              letterSpacing: BestieTokens.lsNormal),
          animationDuration: BestieTokens.dur,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BestieTokens.cBrand,
          foregroundColor: BestieTokens.cTextInvert,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BestieTokens.rSm)),
          textStyle: const TextStyle(fontWeight: BestieTokens.fwSemibold),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor:
              isDark ? BestieTokens.cBrand400 : BestieTokens.cBrandStrong,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BestieTokens.rSm)),
          textStyle: const TextStyle(fontWeight: BestieTokens.fwSemibold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cText,
          side: BorderSide(color: cBorderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BestieTokens.rSm)),
          textStyle: const TextStyle(fontWeight: BestieTokens.fwSemibold),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cSurface2,
        side: BorderSide(color: cBorder),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rPill)),
      ),
      dividerTheme: DividerThemeData(
        color: cBorder,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cSurface,
        elevation: 0,
        height: 64,
        indicatorColor: cBrandSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight:
                selected ? BestieTokens.fwSemibold : BestieTokens.fwMedium,
            color: selected
                ? (isDark ? BestieTokens.cBrand400 : BestieTokens.cBrandStrong)
                : cTextMuted,
            letterSpacing: BestieTokens.lsNormal,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected
                ? (isDark ? BestieTokens.cBrand400 : BestieTokens.cBrandStrong)
                : cTextMuted,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cSurface,
        modalElevation: 24,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
        ),
        clipBehavior: Clip.antiAlias,
        dragHandleColor: cBorderStrong,
        dragHandleSize: const Size(40, 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rXl),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : cText).withOpacity(0.92),
          borderRadius: BorderRadius.circular(BestieTokens.rXs),
        ),
        textStyle: TextStyle(
            color: isDark ? cText : Colors.white,
            fontSize: 12,
            fontWeight: BestieTokens.fwMedium),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? cSurface3 : cText,
        contentTextStyle: TextStyle(
            color: isDark ? cText : Colors.white,
            fontWeight: BestieTokens.fwMedium),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rSm)),
        elevation: 8,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : cSurface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? BestieTokens.cBrand
              : cBorderStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: BestieTokens.cBrand,
        linearTrackColor: cSurface2,
      ),
      dividerColor: cBorder,
    );
  }
}

/// Premium page transition — fade + small slide. Smoother than the default
/// platform transitions and consistent across desktop + mobile.
class _PremiumPageTransitionBuilder extends PageTransitionsBuilder {
  const _PremiumPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: BestieTokens.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
