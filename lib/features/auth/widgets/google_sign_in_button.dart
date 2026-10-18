import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.label = 'Continue with Google',
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
              )
            else
              Image.asset(
                'assets/images/google_logo.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            const SizedBox(width: 12),
            Text(
              isLoading ? 'Connecting...' : label,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
      ),
    );
  }
}
