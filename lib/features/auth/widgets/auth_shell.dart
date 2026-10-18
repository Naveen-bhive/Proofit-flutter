import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

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
      backgroundColor: onBack != null ? AppColors.page : AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.light),
                ),
              )
            else
              const SizedBox(height: 48),
            if (showWordmark) ...[
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: MediaQuery.of(context).size.width * 0.58,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h1.copyWith(fontSize: 26),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
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
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4F9),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(color: Color(0x1F0F172A), blurRadius: 24, offset: Offset(0, 12)),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(fillColor: AppColors.white),
                ),
                child: child,
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 28),
              footer!,
            ],
          ]),
        ),
      ),
    );
  }
}

/// Label shown above an auth text field, with an optional trailing action.
class AuthFieldLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const AuthFieldLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(children: [
        Text(text, style: const TextStyle(color: AppColors.light, fontSize: 14.5, fontWeight: FontWeight.w500)),
        const Spacer(),
        if (trailing != null) trailing!,
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
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('OR', style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
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
        color: AppColors.redSoft,
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
