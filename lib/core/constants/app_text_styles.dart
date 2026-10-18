import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  /// Display font for page titles and card headings (Poppins in the designs).
  static const display = 'Poppins';

  static const h1 = TextStyle(fontFamily: display, fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.5);
  static const h2 = TextStyle(fontFamily: display, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3);
  static const h3 = TextStyle(fontFamily: display, fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text);
  static const pageTitle = TextStyle(fontFamily: display, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3);
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.light);
  static const bodySmall = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.silver);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 1.0);
  static const fieldLabel = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text);
  static const button = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.white);
}
