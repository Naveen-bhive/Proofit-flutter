import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class AuthShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showWordmark;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onBack;

  const AuthShell({
    super.key,
    required this.title,
    this.subtitle,
    this.showWordmark = true,
    required this.child,
    this.footer,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Stack(children: [
        Positioned(
          top: -120,
          left: -80,
          right: -80,
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  AppColors.brand.withValues(alpha: 0.18),
                  AppColors.dark.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.silver),
                  ),
                )
              else
                const SizedBox(height: 8),
              if (showWordmark) ...[
                Center(
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: MediaQuery.of(context).size.width * 0.52,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 28),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                  letterSpacing: -0.5,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.silver,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.dark2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: child,
              ),
              if (footer != null) ...[
                const SizedBox(height: 24),
                footer!,
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Row(children: [
        Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
        Expanded(child: Divider(color: AppColors.border)),
      ]),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: AppColors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(color: AppColors.red, fontSize: 13))),
      ]),
    );
  }
}
