import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/owner_controller.dart';

class OwnerProfileScreen extends ConsumerWidget {
  const OwnerProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ownerControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(children: [
        // Company + owner info
        Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            CircleAvatar(radius: 30, backgroundColor: AppColors.brand.withOpacity(0.15),
              backgroundImage: state.ownerPhotoUrl != null ? NetworkImage(state.ownerPhotoUrl!) : null,
              child: state.ownerPhotoUrl == null ? Text(state.orgName.isNotEmpty ? state.orgName[0] : '?',
                style: const TextStyle(color: AppColors.brand, fontSize: 22, fontWeight: FontWeight.w800)) : null),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.orgName, style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              Text(state.ownerEmail ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                child: Text(state.plan.toUpperCase(), style: const TextStyle(color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.w700))),
            ])),
          ])),

        _section('CUSTOMERS & JOBS', [
          _tile(Icons.people_outline, AppColors.brand, 'Customers', () => context.push('/owner/customers')),
        ]),
        _section('REPORTS & ATTENDANCE', [
          _tile(Icons.access_time_outlined,     AppColors.blue,   'Working Hours',     () => context.push('/owner/working-hours')),
          _tile(Icons.calendar_today_outlined,  AppColors.green,  'Staff Attendance',  () => context.push('/owner/staff-attendance')),
          _tile(Icons.people_outline,           AppColors.yellow, 'Staff Management',  () => context.push('/owner/staff')),
        ]),

        _section('SUBSCRIPTION', [
          _tile(Icons.workspace_premium_outlined, AppColors.brand, 'Manage Plan',       () => context.push('/owner/subscription')),
          _tile(Icons.receipt_long_outlined,      AppColors.silver,'Payment History',   () => context.push('/owner/payment-history')),
        ]),

        _section('SETTINGS', [
          _tile(Icons.business_outlined,  AppColors.silver, 'Company Name',        () => _editCompanyName(context, ref, state.orgName)),
        ]),

        _section('ACCOUNT', [
          _tile(Icons.logout_rounded, AppColors.red, 'Logout', () => _logout(context, ref), color_: AppColors.red),
        ]),

        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _section(String title, List<Widget> tiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2))),
    Container(margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Material(
        color: AppColors.dark2,
        child: Column(children: tiles),
      )),
  ]);

  Widget _tile(IconData icon, Color color, String label, VoidCallback onTap, {Color? color_}) =>
    ListTile(
      leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20)),
      title: Text(label, style: TextStyle(color: color_ ?? AppColors.white, fontSize: 14)),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.muted.withOpacity(0.5), size: 20),
      onTap: onTap,
      dense: true,
    );

  void _editCompanyName(BuildContext context, WidgetRef ref, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.dark2,
      title: const Text('Company Name', style: TextStyle(color: AppColors.white)),
      content: TextField(controller: ctrl, style: const TextStyle(color: AppColors.white),
        decoration: const InputDecoration(labelText: 'Company name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.silver))),
        TextButton(onPressed: () {
          ref.read(ownerControllerProvider.notifier).updateCompanyName(ctrl.text.trim());
          Navigator.pop(context);
        }, child: const Text('Save', style: TextStyle(color: AppColors.brand))),
      ]));
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) context.go('/signin');
  }
}