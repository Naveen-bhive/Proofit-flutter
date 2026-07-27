import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';

class OfflineScreen extends ConsumerStatefulWidget {
  final Widget child;
  const OfflineScreen({super.key, required this.child});
  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() => _isOffline = result == ConnectivityResult.none);
    });
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _isOffline = result == ConnectivityResult.none);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline) return widget.child;

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.muted, size: 80),
          const SizedBox(height: 24),
          const Text('No Internet', style: TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
            'You\'re offline. Drafts you save will sync automatically when you reconnect.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.silver, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 40),
          // Offline capabilities
          _offlineCapability('📷 Capture photos', true),
          _offlineCapability('💾 Save as draft', true),
          _offlineCapability('📤 Submit report', false),
          _offlineCapability('🗺  Live map', false),
          const SizedBox(height: 40),
          AppButton(
            label: 'Try Again',
            icon: Icons.refresh_rounded,
            onPressed: _checkConnectivity,
          ),
        ]),
      )),
    );
  }

  Widget _offlineCapability(String label, bool available) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(available ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: available ? AppColors.green : AppColors.muted, size: 20),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(
          color: available ? AppColors.light : AppColors.muted,
          fontSize: 14,
        )),
        const Spacer(),
        Text(available ? 'Available' : 'Requires internet',
            style: TextStyle(color: available ? AppColors.green : AppColors.muted, fontSize: 12)),
      ]),
    );
  }
}