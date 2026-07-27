import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static const h1 = TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.white, letterSpacing: -1);
  static const h2 = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.white, letterSpacing: -0.5);
  static const h3 = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.white);
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.light);
  static const bodySmall = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.silver);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 1.2);
  static const button = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.white);
}
