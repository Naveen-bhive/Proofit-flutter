import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_colors.dart';

/// Guides staff (especially Xiaomi / Huawei / Oppo / Vivo) to keep ProofIt
/// unrestricted so live location survives background / OEM battery killers.
class BatteryOptimizationService {
  static const _channel = MethodChannel('com.bhive.proofit/battery');
  static const _storage = FlutterSecureStorage();
  static const _skipUntilKey = 'battery_opt_guide_skip_until';
  static const _warningShownKey = 'battery_opt_warning_shown';

  static Future<bool> get isAndroid => Future.value(Platform.isAndroid);

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final native = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (native != null) return native;
    } catch (_) {}
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  static Future<String> manufacturer() async {
    if (!Platform.isAndroid) return '';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return (info.manufacturer).toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static Future<bool> get isAggressiveOem async {
    final m = await manufacturer();
    const known = [
      'xiaomi', 'redmi', 'poco',
      'huawei', 'honor',
      'oppo', 'realme',
      'vivo', 'iqoo',
      'oneplus', 'meizu',
    ];
    return known.any(m.contains);
  }

  static Future<OemGuide> oemGuide() async {
    final m = await manufacturer();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return const OemGuide(
        brandLabel: 'Xiaomi / Redmi / POCO',
        steps: [
          'Set battery usage for ProofIt to Unrestricted (or No restrictions).',
          'Open Autostart / Autolaunch and enable ProofIt.',
          'In Security / App battery saver, turn off saving for ProofIt.',
        ],
      );
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return const OemGuide(
        brandLabel: 'Huawei / Honor',
        steps: [
          'Set App launch for ProofIt to Manage manually â†’ enable Auto-launch, Secondary launch, and Run in background.',
          'Add ProofIt to Protected apps / Battery optimization whitelist.',
        ],
      );
    }
    if (m.contains('oppo') || m.contains('realme')) {
      return const OemGuide(
        brandLabel: 'Oppo / Realme',
        steps: [
          'Allow ProofIt to Autostart.',
          'Set Battery â†’ App power management â†’ ProofIt â†’ Allow background activity.',
        ],
      );
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return const OemGuide(
        brandLabel: 'Vivo / iQOO',
        steps: [
          'Enable Autostart for ProofIt.',
          'Set high background power consumption / unrestricted battery for ProofIt.',
        ],
      );
    }
    if (m.contains('oneplus')) {
      return const OemGuide(
        brandLabel: 'OnePlus',
        steps: [
          'Set Battery optimization for ProofIt to Donâ€™t optimize / Unrestricted.',
          'Turn off Advanced optimization / Sleep standby optimization if present.',
        ],
      );
    }
    return const OemGuide(
      brandLabel: 'this phone',
      steps: [
        'Set battery usage for ProofIt to Unrestricted.',
        'Disable any â€œkill apps when screen offâ€ / battery saver options for ProofIt.',
      ],
    );
  }

  static Future<bool> requestUnrestricted() async {
    if (!Platform.isAndroid) return true;
    try {
      final opened = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      if (opened == true) return true;
    } catch (_) {}
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  static Future<bool> openBatterySettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openBatteryOptimizationSettings') ?? false;
    } catch (_) {
      return openAppSettings();
    }
  }

  static Future<bool> openOemAutostartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openOemAutostartSettings') ?? false;
    } catch (_) {
      return openAppSettings();
    }
  }

  static Future<bool> _shouldSkipGuide() async {
    final raw = await _storage.read(key: _skipUntilKey);
    if (raw == null) return false;
    final until = DateTime.tryParse(raw);
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  static Future<void> skipGuideForToday() async {
    final until = DateTime.now().add(const Duration(hours: 20));
    await _storage.write(key: _skipUntilKey, value: until.toIso8601String());
  }

  static Future<bool> hasWarningBeenShown() async {
    if (!Platform.isAndroid) return true;
    final raw = await _storage.read(key: _warningShownKey);
    return raw == '1';
  }

  static Future<void> _markWarningShown() async {
    await _storage.write(key: _warningShownKey, value: '1');
  }

  /// Must be shown before check-in (Android). Marks warning as seen when dismissed.
  /// Returns true when the gate is satisfied (shown / not needed / already unrestricted).
  static Future<bool> ensureWarningShownBeforeCheckIn(BuildContext context) async {
    if (!Platform.isAndroid) return true;
    if (!context.mounted) return false;

    final unrestricted = await isIgnoringBatteryOptimizations();
    final aggressive = await isAggressiveOem;
    final alreadyShown = await hasWarningBeenShown();

    // Stock Android already unrestricted â€” no need to block.
    if (unrestricted && !aggressive) {
      await _markWarningShown();
      return true;
    }

    // Gate: warning must have been shown at least once.
    if (alreadyShown) return true;

    if (!context.mounted) return false;
    await _showBatteryGuideDialog(context, unrestricted: unrestricted, forceMarkShown: true);
    return hasWarningBeenShown();
  }

  /// Soft re-prompt after check-in for OEM autostart (optional follow-up).
  static Future<void> maybePromptAfterCheckIn(BuildContext context) async {
    if (!Platform.isAndroid || !context.mounted) return;
    if (await _shouldSkipGuide()) return;

    final unrestricted = await isIgnoringBatteryOptimizations();
    final aggressive = await isAggressiveOem;
    if (unrestricted && !aggressive) return;

    if (!context.mounted) return;
    await _showBatteryGuideDialog(context, unrestricted: unrestricted, forceMarkShown: true);
  }

  static Future<void> _showBatteryGuideDialog(
    BuildContext context, {
    required bool unrestricted,
    bool forceMarkShown = false,
  }) async {
    final guide = await oemGuide();
    final aggressive = await isAggressiveOem;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dark2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Keep location running in background',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unrestricted
                    ? 'On ${guide.brandLabel} phones, also allow ProofIt to autostart so live tracking is not killed.'
                    : 'Your phone may stop ProofIt when the screen is locked. Set battery to Unrestricted so your owner keeps getting your live location.',
                style: const TextStyle(color: AppColors.silver, height: 1.45, fontSize: 14),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On ${guide.brandLabel}:',
                      style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < guide.steps.length; i++) ...[
                      Text(
                        '${i + 1}. ${guide.steps[i]}',
                        style: const TextStyle(color: AppColors.silver, height: 1.4, fontSize: 13),
                      ),
                      if (i < guide.steps.length - 1) const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!unrestricted)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async { await requestUnrestricted(); },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                    child: const Text('Allow unrestricted', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              if (!unrestricted) const SizedBox(height: 8),
              if (aggressive)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async { await openOemAutostartSettings(); },
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.yellow, side: const BorderSide(color: AppColors.yellow)),
                    child: const Text('Open Autostart settings'),
                  ),
                ),
              if (aggressive) const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async { await openBatterySettings(); },
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.silver, side: const BorderSide(color: AppColors.border)),
                  child: const Text('Open battery settings'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await skipGuideForToday();
              if (forceMarkShown) await _markWarningShown();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('I understand â€” Continue', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () async {
              if (forceMarkShown) await _markWarningShown();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Done', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (forceMarkShown) await _markWarningShown();
  }
}

class OemGuide {
  final String brandLabel;
  final List<String> steps;
  const OemGuide({required this.brandLabel, required this.steps});
}
