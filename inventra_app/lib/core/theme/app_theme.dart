import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Soft White (Light) ───
  static const Color lightBg = Color(0xFFEFF3F0);
  static const Color lightPanel = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF5F8F6);
  static const Color lightBorder = Color(0xFFDDE3DF);
  static const Color lightTextMain = Color(0xFF2B3674);
  static const Color lightTextMuted = Color(0xFF8F9BBA);

  // ─── Dark Mode (Neutral Gray) ───
  static const Color darkBg = Color(0xFF1C1C1E);
  static const Color darkPanel = Color(0xFF2C2C2E);
  static const Color darkCard = Color(0xFF3A3A3C);
  static const Color darkBorder = Color(0xFF48484A);
  static const Color darkTextMain = Color(0xFFE5E5EA);
  static const Color darkTextMuted = Color(0xFF98989D);

  // ─── Shared Accents ───
  static Color primaryAccent = const Color(0xFF4318FF);
  static const Color secondaryAccent = Color(0xFF01B574);
  static const Color dangerAccent = Color(0xFFEE5D50);
  static const Color warningAccent = Color(0xFFFFB547);
  static const Color infoAccent = Color(0xFF3B82F6);
  static const Color successAccent = secondaryAccent;

  // Readable accent for text on dark backgrounds
  static bool _isDark = false;
  static Color get accentText => primaryAccent;

  // ─── Dynamic colors (set by current theme) ───
  static Color darkBackground = lightBg;
  static Color panelBackground = lightPanel;
  static Color cardBackground = lightCard;
  static Color borderBright = lightBorder;
  static Color textMain = lightTextMain;
  static Color textMuted = lightTextMuted;

  static void setDarkMode(bool dark) {
    _isDark = dark;
    if (dark) {
      darkBackground = darkBg;
      panelBackground = darkPanel;
      cardBackground = darkCard;
      borderBright = darkBorder;
      textMain = darkTextMain;
      textMuted = darkTextMuted;
      primaryAccent = const Color(0xFF6A4BFB); // Lighter tone for dark mode readability
    } else {
      darkBackground = lightBg;
      panelBackground = lightPanel;
      cardBackground = lightCard;
      borderBright = lightBorder;
      textMain = lightTextMain;
      textMuted = lightTextMuted;
      primaryAccent = const Color(0xFF4318FF);
    }
  }

  static ThemeData get lightTheme => _buildTheme(false);
  static ThemeData get darkTheme => _buildTheme(true);

  static ThemeData _buildTheme(bool isDark) {
    final bg = isDark ? darkBg : lightBg;
    final panel = isDark ? darkPanel : lightPanel;
    final card = isDark ? darkCard : lightCard;
    final border = isDark ? darkBorder : lightBorder;
    final txt = isDark ? darkTextMain : lightTextMain;
    final muted = isDark ? darkTextMuted : lightTextMuted;
    final base = isDark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: panel,
        error: dangerAccent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: panel,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: txt),
        iconTheme: IconThemeData(color: txt),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: txt),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: txt),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: txt),
        labelLarge: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w500, color: txt),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: GoogleFonts.robotoMono(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: txt,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primaryAccent, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: GoogleFonts.inter(color: muted, fontSize: 13),
        hintStyle: GoogleFonts.inter(color: muted, fontSize: 13),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(textStyle: GoogleFonts.inter(color: txt)),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? primaryAccent : muted),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? primaryAccent.withOpacity(0.3) : border),
      ), dialogTheme: DialogThemeData(backgroundColor: panel),
    );
  }
}
