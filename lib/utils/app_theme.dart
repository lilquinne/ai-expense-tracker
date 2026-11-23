// lib/utils/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme => ThemeData(
        popupMenuTheme: PopupMenuThemeData(
            color: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18))),
        dropdownMenuTheme: DropdownMenuThemeData(
            menuStyle: MenuStyle(
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18))),
                padding: const WidgetStatePropertyAll(EdgeInsets.all(8)))),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: darkTheme.elevatedButtonTheme.style?.copyWith(
                backgroundColor: const WidgetStatePropertyAll(primary))),
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Sora',
        textTheme: darkTheme.textTheme.apply(
            bodyColor: const Color(0xFF4B2D1C),
            displayColor: const Color(0xFF4B2D1C)),
        scaffoldBackgroundColor: const Color(0xFFFFF9ED),
        colorScheme: ColorScheme.fromSeed(
            seedColor: primary,
            brightness: Brightness.light,
            primary: primary,
            secondary: const Color(0xFFEBC85E),
            surface: const Color(0xFFFFFDF6)),
        appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFFFF9ED),
            titleTextStyle: TextStyle(
                fontFamily: 'Sora',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B2D1C))),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF5EBD8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none)),
        cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16))),
      );
  // Brand Colors
  static const Color primary = Color(0xFF79502F);
  static const Color primaryLight = Color(0xFFAA784C);
  static const Color primaryDark = Color(0xFF56341F);
  static const Color accent = Color(0xFF64836A);
  static const Color accentDark = Color(0xFF47684F);

  static const Color incomeColor = Color(0xFF64836A);
  static const Color expenseColor = Color(0xFFFF6B6B);
  static const Color warningColor = Color(0xFFFFB347);

  // Backgrounds
  static const Color bgDark = Color(0xFF0F1023);
  static const Color bgCard = Color(0xFF1A1A35);
  static const Color bgCardLight = Color(0xFF252545);
  static const Color bgSurface = Color(0xFF20203D);

  // Text
  static const Color textPrimary = Color(0xFFF4F3FF);
  static const Color textSecondary = Color(0xFFB8B8D4);
  static const Color textMuted = Color(0xFF9999BB);

  static ThemeData get darkTheme {
    return ThemeData(
      popupMenuTheme: PopupMenuThemeData(
          color: bgCardLight,
          elevation: 8,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18))),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(8)))),
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      fontFamily: 'Sora',
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF9C8CFF),
        secondary: Color(0xFF64C8D5),
        surface: bgCard,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Sora',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCardLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3B3B60), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF9C8CFF), width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontFamily: 'Sora'),
        hintStyle: const TextStyle(color: textMuted, fontFamily: 'Sora'),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7965DB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgCard,
        selectedItemColor: Color(0xFF9C8CFF),
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w700),
        displayMedium: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w700),
        headlineLarge: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w600),
        headlineSmall: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w600),
        titleLarge: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w600),
        titleMedium: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(
            fontFamily: 'Sora', fontSize: 14, height: 1.45, color: textPrimary),
        bodyMedium: TextStyle(
            fontFamily: 'Sora',
            fontSize: 13,
            height: 1.4,
            color: textSecondary),
        bodySmall: TextStyle(fontFamily: 'Sora', color: textMuted),
        labelLarge: TextStyle(
            fontFamily: 'Sora',
            color: textPrimary,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

class AppPalette {
  AppPalette(this.light);
  final bool light;
  static AppPalette of(BuildContext context) =>
      AppPalette(Theme.of(context).brightness == Brightness.light);
  Color get primary => light ? AppTheme.primary : const Color(0xFF9C8CFF);
  LinearGradient get primaryGradient => LinearGradient(
      colors: light
          ? const [Color(0xFF79502F), Color(0xFF56341F)]
          : const [Color(0xFF7965DB), Color(0xFF454D9E)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight);
  Color get bgDark => light ? const Color(0xFFFFF9ED) : AppTheme.bgDark;
  Color get bgCard => light ? const Color(0xFFFFFDF6) : AppTheme.bgCard;
  Color get bgCardLight =>
      light ? const Color(0xFFF5EBD8) : AppTheme.bgCardLight;
  Color get bgSurface => light ? const Color(0xFFEFE0C5) : AppTheme.bgSurface;
  Color get textPrimary =>
      light ? const Color(0xFF4B2D1C) : AppTheme.textPrimary;
  Color get textSecondary =>
      light ? const Color(0xFF765E4B) : AppTheme.textSecondary;
  Color get textMuted => light ? const Color(0xFF806B58) : AppTheme.textMuted;
  Color get border => light ? const Color(0xFFE5D6BD) : const Color(0xFF3B3B60);
}

class AppGradients {
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF79502F), Color(0xFF56341F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF64836A), Color(0xFF47684F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient incomeGradient = LinearGradient(
    colors: [Color(0xFF64836A), Color(0xFF0097A7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient expenseGradient = LinearGradient(
    colors: [Color(0xFFFF6B6B), Color(0xFFCC4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1A1A35), Color(0xFF252545)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
