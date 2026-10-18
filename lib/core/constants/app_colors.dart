import 'package:flutter/material.dart';

/// Light design-system palette (see `redesign/`).
///
/// The legacy names (`dark`, `dark2`, `silver`, ...) are kept so existing
/// screens keep compiling; they now map to their light-theme equivalents:
/// `dark*` are surfaces, `text`/`light`/`silver`/`muted` are the text ramp.
class AppColors {
  // Brand
  static const brand = Color(0xFF2563EB);
  static const brandDark = Color(0xFF1D4ED8);
  static const brandSoft = Color(0xFFEFF6FF);
  static const brandBorder = Color(0xFFBFDBFE);
  static const indigo = Color(0xFF4F46E5);
  static const brand2 = Color(0xFF5FDC3A);
  static const navy = Color(0xFF062B68);

  // Surfaces
  static const dark = Color(0xFFFFFFFF); // scaffold
  static const dark2 = Color(0xFFFFFFFF); // card / sheet
  static const dark3 = Color(0xFFF8FAFC); // input fill, subtle panel
  static const dark4 = Color(0xFFF1F5F9); // chips, pressed, tracks
  static const card = Color(0xFFFFFFFF);
  static const page = Color(0xFFF8FAFC); // grey page (staff lists)
  static const border = Color(0xFFE2E8F0);
  static const borderSoft = Color(0xFFF1F5F9);

  // Text ramp
  static const text = Color(0xFF0F172A); // headings / primary
  static const light = Color(0xFF334155); // body
  static const silver = Color(0xFF64748B); // secondary
  static const muted = Color(0xFF94A3B8); // hints / captions
  static const white = Color(0xFFFFFFFF); // on coloured fills

  // Status
  static const green = Color(0xFF10B981);
  static const greenDark = Color(0xFF059669);
  static const greenSoft = Color(0xFFECFDF5);
  static const yellow = Color(0xFFF59E0B);
  static const amberDark = Color(0xFFB45309);
  static const amberSoft = Color(0xFFFFFBEB);
  static const red = Color(0xFFE11D48);
  static const redSoft = Color(0xFFFFF1F2);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF7C3AED);
  static const orange = Color(0xFFF97316);

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF4F46E5)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Soft drop shadow used on cards, pills and round icon buttons.
  static const cardShadow = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const softShadow = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 6, offset: Offset(0, 2)),
  ];
  static List<BoxShadow> glow(Color c) => [
        BoxShadow(color: c.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6)),
      ];
}
