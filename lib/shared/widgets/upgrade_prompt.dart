import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

class UpgradePrompt extends StatelessWidget {
  final String feature;
  final String requiredPlan;
  final String description;
  final VoidCallback? onDismiss;

  const UpgradePrompt({
    super.key,
    required this.feature,
    required this.requiredPlan,
    required this.description,
    this.onDismiss,
  });

  static Future<void> show(BuildContext context, {
    required String feature,
    required String requiredPlan,
    required String description,
  }) async {
    await showModalBottomSheet(
      context: context, backgroundColor: AppColors.dark2, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => UpgradePrompt(feature: feature, requiredPlan: requiredPlan, description: description));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
        Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.workspace_premium_outlined, color: AppColors.brand, size: 32)),
        const SizedBox(height: 16),
        Text('Upgrade to $requiredPlan', style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(color: AppColors.silver, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () { Navigator.pop(context); context.push('/owner/subscription'); },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text('Upgrade to $requiredPlan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        const SizedBox(height: 10),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Maybe Later', style: TextStyle(color: AppColors.muted))),
      ])));
  }
}