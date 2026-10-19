// Design tokens from docs/ui/UI-SPEC.md §1 (measured from Gemini Notebook).
import 'package:flutter/material.dart';

@immutable
class VTokens extends ThemeExtension<VTokens> {
  final Color bg, panel, tonal, text, textStrong, textTitle, textMuted, iconMuted, outline, divider;
  final Color primary, primaryTonal, onPrimaryTonal, link, sourceGuide, unreadDot, success, error, scrim;
  final Color citationBg, citationText;

  const VTokens({
    required this.bg,
    required this.panel,
    required this.tonal,
    required this.text,
    required this.textStrong,
    required this.textTitle,
    required this.textMuted,
    required this.iconMuted,
    required this.outline,
    required this.divider,
    required this.primary,
    required this.primaryTonal,
    required this.onPrimaryTonal,
    required this.link,
    required this.sourceGuide,
    required this.unreadDot,
    required this.success,
    required this.error,
    required this.scrim,
    required this.citationBg,
    required this.citationText,
  });

  static const dark = VTokens(
    bg: Color(0xFF0F0F0F),
    panel: Color(0xFF1F1F1F),
    tonal: Color(0xFF171717),
    text: Color(0xFFC7C7C7),
    textStrong: Color(0xFFE6E6E6),
    textTitle: Color(0xFFF2F2F2),
    textMuted: Color(0x8CFFFFFF),
    iconMuted: Color(0xFFABABAB),
    outline: Color(0x1FFFFFFF),
    divider: Color(0xFF37383B),
    primary: Color(0xFF4259FF),
    primaryTonal: Color(0xFF1F3B9B),
    onPrimaryTonal: Color(0xFFFFFFFF),
    link: Color(0xFFC3CAFC),
    sourceGuide: Color(0xFF2F334B),
    unreadDot: Color(0xFF3186FF),
    success: Color(0xFF80DA88),
    error: Color(0xFFF2B8B5),
    scrim: Color(0x99000000),
    citationBg: Color(0xFF171717),
    citationText: Color(0xFFABABAB),
  );

  static const light = VTokens(
    bg: Color(0xFFFAF9F9),
    panel: Color(0xFFFFFFFF),
    tonal: Color(0xFFF2F0F0),
    text: Color(0xFF303030),
    textStrong: Color(0xFF000000),
    textTitle: Color(0xFF1B1B1C),
    textMuted: Color(0x8C000000),
    iconMuted: Color(0xFF5E5E5E),
    outline: Color(0x14000000),
    divider: Color(0xFFE0E0E0),
    primary: Color(0xFF4259FF),
    primaryTonal: Color(0xFF9DD2FF),
    onPrimaryTonal: Color(0xFF000000),
    link: Color(0xFF3346CC),
    sourceGuide: Color(0xFFE8EAF8),
    unreadDot: Color(0xFF3186FF),
    success: Color(0xFF1E8E3E),
    error: Color(0xFFB3261E),
    scrim: Color(0x52000000),
    citationBg: Color(0xFFF2F0F0),
    citationText: Color(0xFF5E5E5E),
  );

  @override
  VTokens copyWith() => this;

  @override
  VTokens lerp(ThemeExtension<VTokens>? other, double t) => t < .5 ? this : (other as VTokens? ?? this);
}

extension VTokensX on BuildContext {
  VTokens get v => Theme.of(this).extension<VTokens>()!;
}

/// Studio output types: label, icon, dark tint, light tint (UI-SPEC §1.4).
enum StudioType {
  audio('Audio Overview', Icons.graphic_eq_rounded, Color(0xFF76A0FF), Color(0xFF2E64DE)),
  slides('Slide Deck', Icons.tablet_rounded, Color(0xFFF872B9), Color(0xFFC43D92)),
  video('Video Overview', Icons.videocam_outlined, Color(0xFF3FDDA0), Color(0xFF0AAC6E)),
  mindmap('Mind Map', Icons.account_tree_outlined, Color(0xFFA47DFF), Color(0xFF6858C7)),
  report('Reports', Icons.auto_awesome_mosaic_outlined, Color(0xFFF872B9), Color(0xFFC43D92)),
  flashcards('Flashcards', Icons.style_outlined, Color(0xFFECDF77), Color(0xFFFF8104)),
  quiz('Quiz', Icons.quiz_outlined, Color(0xFF4DD2E1), Color(0xFF167F9B)),
  infographic('Infographic', Icons.stacked_bar_chart_rounded, Color(0xFFECDF77), Color(0xFFFF8104)),
  table('Data Table', Icons.table_view_outlined, Color(0xFF76A0FF), Color(0xFF2E64DE));

  final String label;
  final IconData icon;
  final Color dark, light;
  const StudioType(this.label, this.icon, this.dark, this.light);
  Color tint(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

const _fallbackFonts = ['Google Sans', 'Roboto Flex', 'Roboto', 'Segoe UI'];

TextStyle vText(double size, double height, {FontWeight weight = FontWeight.w400, Color? color}) => TextStyle(
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      color: color,
      fontFamily: 'Google Sans Flex',
      fontFamilyFallback: _fallbackFonts,
    );

ThemeData buildTheme(Brightness b) {
  final t = b == Brightness.dark ? VTokens.dark : VTokens.light;
  final scheme = ColorScheme.fromSeed(seedColor: t.primary, brightness: b).copyWith(
    primary: t.primary,
    onPrimary: Colors.white,
    surface: t.bg,
    onSurface: t.text,
    surfaceContainer: t.panel,
    surfaceContainerHigh: t.panel,
    surfaceContainerLow: t.tonal,
    outline: t.outline,
    outlineVariant: t.divider,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    extensions: [t],
    textTheme: base.textTheme.apply(
      fontFamily: 'Google Sans Flex',
      fontFamilyFallback: _fallbackFonts,
      bodyColor: t.text,
      displayColor: t.textTitle,
    ),
    dividerColor: t.divider,
    dialogTheme: DialogThemeData(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      barrierColor: t.scrim,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: Colors.white,
        shape: pill,
        minimumSize: const Size(0, 40),
        textStyle: vText(15, 20, weight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.textStrong,
        side: BorderSide(color: t.outline),
        shape: pill,
        minimumSize: const Size(0, 36),
        textStyle: vText(15, 20, weight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.textStrong, shape: pill),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.outline)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.outline)),
      hintStyle: TextStyle(color: t.textMuted),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      side: BorderSide(color: t.iconMuted, width: 1.5),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.textStrong, borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(color: t.bg, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: t.textStrong),
  );
}
