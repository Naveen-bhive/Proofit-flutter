import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/auth_controller.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final bool isStaffInvite;
  const OtpScreen({super.key, this.isStaffInvite = false});
  // isStaffInvite defined above
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  bool _otpSent    = false;
  bool _loading    = false;
  String? _error;

  // FIX #14: Resend timer
  Timer? _resendTimer;
  int _resendCooldown = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() => _resendCooldown = 30);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) {
        t.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10) {
      setState(() => _error = 'Enter a valid 10-digit number');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).sendOtp(phone);
    setState(() { _loading = false; });
    if (result) {
      setState(() => _otpSent = true);
      _startResendTimer(); // FIX #14
    } else {
      setState(() => _error = 'Failed to send OTP. Try again.');
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;
    setState(() { _loading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).resendOtp(_phoneCtrl.text.trim());
    setState(() => _loading = false);
    if (result) {
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('OTP resent!'), backgroundColor: AppColors.green));
    } else {
      setState(() => _error = 'Failed to resend. Try again.');
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) { setState(() => _error = 'Enter the 6-digit OTP'); return; }
    setState(() { _loading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier)
        .verifyOtp(_phoneCtrl.text.trim(), otp);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result == null) { setState(() => _error = 'Invalid OTP. Try again.'); return; }
    if (result == 'new_owner') { context.go('/owner-setup'); return; }
    context.go(result == 'owner' ? '/owner' : '/staff');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 40),
          // Logo
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('ProofIt', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.white)),
          ]),
          const SizedBox(height: 48),
          Text(
            _otpSent ? 'Enter OTP' : 'Enter your phone',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.white, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            _otpSent ? 'OTP sent to +91 ${_phoneCtrl.text}' : 'We will send a verification code',
            style: const TextStyle(color: AppColors.silver, fontSize: 15),
          ),
          const SizedBox(height: 32),

          if (!_otpSent) ...[
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
                decoration: BoxDecoration(
                  color: AppColors.dark3, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text('+91', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.white, fontSize: 20, letterSpacing: 2),
                decoration: const InputDecoration(counterText: '', hintText: '98765 43210'),
                onFieldSubmitted: (_) => _sendOtp(),
              )),
            ]),
          ] else ...[
            TextFormField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              style: const TextStyle(color: AppColors.white, fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(counterText: '', hintText: '------'),
              onFieldSubmitted: (_) => _verifyOtp(),
            ),
            const SizedBox(height: 16),
            // FIX #14: Resend button with countdown
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("Didn't receive OTP? ", style: TextStyle(color: AppColors.silver, fontSize: 14)),
              GestureDetector(
                onTap: _resendCooldown > 0 ? null : _resendOtp,
                child: Text(
                  _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend OTP',
                  style: TextStyle(
                    color: _resendCooldown > 0 ? AppColors.muted : AppColors.brand,
                    fontWeight: FontWeight.w700, fontSize: 14,
                  ),
                ),
              ),
            ]),
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.red.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.red, size: 16),
                const SizedBox(width: 8),
                Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          AppButton(
            label: _otpSent ? 'Verify OTP' : 'Send OTP',
            isLoading: _loading,
            onPressed: _otpSent ? _verifyOtp : _sendOtp,
          ),
          if (_otpSent) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Change Number',
              isOutlined: true,
              onPressed: () => setState(() { _otpSent = false; _otpCtrl.clear(); _error = null; _resendTimer?.cancel(); _resendCooldown = 0; }),
            ),
          ],
          const SizedBox(height: 40),
        ]),
      )),
    );
  }
}