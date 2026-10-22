import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/ui_kit.dart';

/// Shown when a staff member opens an owner screen they don't have access to
/// (deep link, notification tap, or access revoked while it was open).
class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'No access',
            onBack: () => context.canPop() ? context.pop() : context.go('/staff'),
          ),
          Expanded(
            child: SoftEmptyState(
              icon: Icons.lock_outline_rounded,
              title: "You don't have access to this",
              subtitle: 'Ask your owner to give you permission for this feature.',
              action: SizedBox(
                width: 200,
                child: PrimaryButton(
                  label: 'Go to Home',
                  height: 46,
                  onPressed: () => context.go('/staff'),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
