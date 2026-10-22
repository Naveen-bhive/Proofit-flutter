import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/app_feature.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/owner_controller.dart';

class OwnerProfileScreen extends ConsumerStatefulWidget {
  const OwnerProfileScreen({super.key});

  @override
  ConsumerState<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends ConsumerState<OwnerProfileScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'ProofIt v${info.version} (Build ${info.buildNumber})');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final unread = state.ownerNotifications.where((n) => n['isRead'] != true).length;
    final renews = state.subscriptionExpiresAt == null
        ? null
        : 'Renews ${DateFormat('MMM d, yyyy').format(state.subscriptionExpiresAt!.toLocal())}';

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
          PageHeader(
            title: 'Profile',
            showBack: false,
            titleSize: 22,
            padding: const EdgeInsets.fromLTRB(4, 8, 0, 16),
            actions: [
              HeaderIconButton(
                icon: Icons.notifications_none_rounded,
                badge: unread,
                onTap: () => context.push('/owner/notifications'),
              ),
            ],
          ),

          // Organisation card → profile details
          SurfaceCard(
            radius: 20,
            padding: const EdgeInsets.all(16),
            onTap: () => context.push('/owner/profile'),
            child: Row(children: [
              state.ownerPhotoUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(state.ownerPhotoUrl!, width: 56, height: 56, fit: BoxFit.cover),
                    )
                  : InitialAvatar(
                      name: state.orgName.isEmpty ? 'O' : state.orgName.substring(0, 1),
                      size: 56,
                      square: true,
                      color: AppColors.indigo,
                      online: true,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(state.orgName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h3.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(children: [
                    SoftBadge(label: state.plan, color: AppColors.brand, uppercase: true, fontSize: 10),
                    if ((state.ownerEmail ?? '').isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(state.ownerEmail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                      ),
                    ],
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ),

          if (state.isEnabled(AppFeature.customers)) ...[
          const SectionLabel('Customers & Jobs'),
          MenuGroup(children: [
            MenuRow(
              icon: Icons.groups_outlined,
              color: AppColors.brand,
              label: 'Customers',
              trailing: state.customers.isEmpty
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(100)),
                      child: Text('${state.customers.length} active',
                          style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
              onTap: () => context.push('/owner/customers'),
            ),
          ]),
          ],

          const SectionLabel('Reports & Attendance'),
          MenuGroup(children: [
            if (state.isEnabled(AppFeature.workingHours))
              MenuRow(icon: Icons.schedule_rounded, color: AppColors.brand, label: 'Working Hours',
                  onTap: () => context.push('/owner/working-hours')),
            if (state.isEnabled(AppFeature.attendance))
              MenuRow(icon: Icons.event_available_outlined, color: AppColors.greenDark, label: 'Staff Attendance',
                  onTap: () => context.push('/owner/staff-attendance')),
            if (state.isEnabled(AppFeature.leaves))
              MenuRow(icon: Icons.event_busy_outlined, color: AppColors.red, label: 'Leave Management',
                  onTap: () => context.push('/owner/leaves')),
            if (state.isEnabled(AppFeature.holidays))
              MenuRow(icon: Icons.celebration_outlined, color: AppColors.purple, label: 'Holidays',
                  onTap: () => context.push('/owner/holidays')),
            MenuRow(icon: Icons.manage_accounts_outlined, color: AppColors.yellow, label: 'Staff Management',
                onTap: () => context.push('/owner/staff')),
          ]),

          const SectionLabel('Subscription'),
          MenuGroup(children: [
            MenuRow(icon: Icons.verified_outlined, color: AppColors.brand, label: 'Manage Plan', subtitle: renews,
                onTap: () => context.push('/owner/subscription')),
            MenuRow(icon: Icons.receipt_long_outlined, color: AppColors.silver, label: 'Payment History',
                onTap: () => context.push('/owner/payment-history')),
          ]),

          const SectionLabel('Account'),
          MenuGroup(
            borderColor: AppColors.red.withValues(alpha: 0.18),
            children: [
              MenuRow(
                icon: Icons.logout_rounded,
                color: AppColors.red,
                label: 'Logout',
                labelColor: AppColors.red,
                onTap: () => _logout(context, state),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Center(child: Text(_version, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
        ]),
      ),
    );
  }

  Future<void> _logout(BuildContext context, OwnerState state) async {
    final ok = await showConfirmSheet(
      context,
      icon: Icons.logout_rounded,
      title: 'Are you sure you want to log out?',
      message:
          'Please confirm that you want to log out of your ProofIt account. You will need to sign in again with your credentials to access your organization workspace.',
      confirmLabel: 'Yes',
      detail: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Row(children: [
          InitialAvatar(
              name: state.orgName.isEmpty ? 'O' : state.orgName.substring(0, 1),
              size: 34,
              square: true,
              color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.orgName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13.5)),
              if ((state.ownerEmail ?? '').isNotEmpty)
                Text(state.ownerEmail!, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ]),
          ),
          SoftBadge(label: state.plan, color: AppColors.brand, uppercase: true, fontSize: 10),
        ]),
      ),
    );
    if (!ok) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) context.go('/signin');
  }
}
