import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class PlanGate extends StatelessWidget {
  final bool hasAccess;
  final String requiredPlan;
  final Widget child;

  const PlanGate({
    super.key,
    required this.hasAccess,
    required this.requiredPlan,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (hasAccess) return child;
    return Stack(children: [
      Opacity(opacity: 0.3, child: IgnorePointer(child: child)),
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.dark3.withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock_outline, color: AppColors.brand, size: 28),
            const SizedBox(height: 8),
            Text('Requires $requiredPlan Plan',
              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Upgrade to unlock', style: TextStyle(color: AppColors.silver, fontSize: 12)),
          ]),
        ),
      ),
    ]);
  }
}