import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../shared/services/app_update_service.dart';
import '../../shared/widgets/app_button.dart';

/// Mandatory, non-dismissable update screen. Shown instead of the splash's
/// normal navigation when the installed build is below the admin-configured
/// minimum version — the user cannot get past this without updating.
class ForceUpdateScreen extends StatefulWidget {
  final AppUpdateConfig config;
  const ForceUpdateScreen({super.key, required this.config});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen>
    with SingleTickerProviderStateMixin {
  bool _opening = false;
  String? _currentVersion;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    AppUpdateService.currentVersion().then((v) {
      if (mounted) setState(() => _currentVersion = v);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _openStore() async {
    final url = widget.config.storeUrl;
    if (url.isEmpty) return;
    setState(() => _opening = true);
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // mandatory — no back button out of this screen
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
            child: Column(
              children: [
                Image.asset('assets/images/logo.png', height: 28),
                const Spacer(),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final glow = 0.10 + _pulseController.value * 0.10;
                    return Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.brand.withValues(alpha: glow),
                            AppColors.brand.withValues(alpha: 0),
                          ],
                        ),
                      ),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 84,
                    height: 84,
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.brand, AppColors.navy],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.system_update_alt_rounded,
                        color: AppColors.white, size: 38),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Update Required',
                  style: TextStyle(
                      color: AppColors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.config.updateMessage,
                  style: const TextStyle(
                      color: AppColors.silver, fontSize: 14.5, height: 1.55),
                  textAlign: TextAlign.center,
                ),
                if (_currentVersion != null &&
                    _currentVersion != widget.config.latestVersion) ...[
                  const SizedBox(height: 20),
                  _VersionBadge(
                    current: _currentVersion!,
                    latest: widget.config.latestVersion,
                  ),
                ],
                const Spacer(flex: 2),
                AppButton(
                  label: 'Update Now',
                  icon: Icons.download_rounded,
                  isLoading: _opening,
                  onPressed: widget.config.storeUrl.isEmpty ? null : _openStore,
                ),
                const SizedBox(height: 14),
                const Text(
                  'You\'ll be taken to the App Store to update ProofIt.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  final String current;
  final String latest;
  const _VersionBadge({required this.current, required this.latest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('v$current',
              style: const TextStyle(
                  color: AppColors.silver,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded,
                color: AppColors.muted, size: 14),
          ),
          Text('v$latest',
              style: const TextStyle(
                  color: AppColors.brand,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
