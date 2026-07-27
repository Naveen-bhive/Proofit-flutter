import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Wraps the package's official button so the design stays compliant with
/// Apple's Human Interface Guidelines (required — a custom-styled button is
/// one of the more common App Review rejection reasons for this feature).
class AppleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const AppleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: SignInWithAppleButton(
        onPressed: isLoading ? () {} : (onPressed ?? () {}),
        style: SignInWithAppleButtonStyle.white,
        borderRadius: BorderRadius.circular(14),
        height: 56,
      ),
    );
  }
}
