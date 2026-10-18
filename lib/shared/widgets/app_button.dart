import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final Color? color;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    if (isOutlined) {
      return OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: shape,
          backgroundColor: AppColors.white,
          side: BorderSide(color: color?.withValues(alpha: 0.6) ?? AppColors.border),
          foregroundColor: color ?? AppColors.text,
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
        ),
      );
    }
    final bg = color ?? AppColors.brand;
    final enabled = onPressed != null && !isLoading;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled ? AppColors.glow(bg) : null,
      ),
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: icon != null ? Icon(icon, size: 19) : const SizedBox.shrink(),
        label: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          disabledForegroundColor: AppColors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: shape,
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
