import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Inter',
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.dark,
      primaryColor: AppColors.brand,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brand,
        onPrimary: AppColors.white,
        secondary: AppColors.brand,
        surface: AppColors.white,
        onSurface: AppColors.text,
        surfaceTint: Colors.transparent,
        error: AppColors.red,
        outline: AppColors.border,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.dark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Icon brightness only — no explicit bar colors. Setting statusBarColor/
        // systemNavigationBarColor (as the SystemUiOverlayStyle presets do)
        // forces Flutter to call the deprecated Window.setStatusBarColor/
        // setNavigationBarColor APIs on every AppBar build; edge-to-edge mode
        // already keeps the bars transparent without them.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: AppTextStyles.pageTitle,
        iconTheme: IconThemeData(color: AppColors.text),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.brand.withValues(alpha: 0.45),
          disabledForegroundColor: AppColors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.white,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.dark3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.silver),
        hintStyle: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w400),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.white,
        showDragHandle: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: AppTextStyles.h3,
        contentTextStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.silver, height: 1.5),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.text,
        contentTextStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.brand,
        unselectedLabelColor: AppColors.silver,
        indicatorColor: AppColors.brand,
        dividerColor: AppColors.border,
        labelStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.brand,
        side: BorderSide(color: AppColors.border),
        shape: StadiumBorder(),
        labelStyle: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.light),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
        linearTrackColor: AppColors.dark4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(AppColors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.brand : AppColors.border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.borderSoft, thickness: 1, space: 1),
    );
  }

  /// Kept for call sites that still reference the old name.
  static ThemeData get dark => light;
}
