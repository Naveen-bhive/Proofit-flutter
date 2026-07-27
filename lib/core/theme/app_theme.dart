import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.dark,
    primaryColor: AppColors.brand,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.brand,
      secondary: AppColors.brand2,
      surface: AppColors.dark2,
      background: AppColors.dark,
      error: AppColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.dark,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.white),
      iconTheme: IconThemeData(color: AppColors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.white,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.dark3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.brand, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.silver),
      hintStyle: const TextStyle(color: AppColors.muted),
    ),
    cardTheme: CardThemeData(
      color: AppColors.dark2,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  );
}