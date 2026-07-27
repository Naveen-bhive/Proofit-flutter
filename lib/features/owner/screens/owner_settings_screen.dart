import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/owner_controller.dart';

class OwnerSettingsScreen extends ConsumerStatefulWidget {
  const OwnerSettingsScreen({super.key});
  @override
  ConsumerState<OwnerSettingsScreen> createState() => _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends ConsumerState<OwnerSettingsScreen> {
  final _companyCtrl = TextEditingController();
  bool _editingName = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(ownerControllerProvider);
    _companyCtrl.text = state.orgName;
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Log Out?', style: TextStyle(color: AppColors.white)),
        content: const Text('You will need to sign in again.', style: TextStyle(color: AppColors.silver)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.silver))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log Out', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/signin');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Profile card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.brand.withOpacity(0.2),
              child: Text(state.orgName.isNotEmpty ? state.orgName[0].toUpperCase() : 'O',
                  style: const TextStyle(color: AppColors.brand, fontSize: 22, fontWeight: FontWeight.w800))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.orgName, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Text(state.plan.toUpperCase(), style: const TextStyle(color: AppColors.brand, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ])),
          ]),
        ),
        const SizedBox(height: 28),

        _sectionTitle('ACCOUNT'),
        _settingRow(Icons.business_outlined, 'Company Name', state.orgName, onTap: () {
          setState(() => _editingName = !_editingName);
        }),
        if (_editingName) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _companyCtrl,
              style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(labelText: 'Company Name'),
            )),
            const SizedBox(width: 10),
            TextButton(
              onPressed: () async {
                await ref.read(ownerControllerProvider.notifier).updateCompanyName(_companyCtrl.text.trim());
                setState(() => _editingName = false);
              },
              child: const Text('Save', style: TextStyle(color: AppColors.brand)),
            ),
          ]),
        ],
        _settingRow(Icons.workspace_premium_outlined, 'Current Plan',
            '${state.plan[0].toUpperCase()}${state.plan.substring(1)}',
            onTap: () => context.push('/owner/subscription')),
        _settingRow(Icons.lock_outline, 'Change Password', '',
            onTap: () => context.push('/change-password')),
        const SizedBox(height: 24),

        _sectionTitle('NOTIFICATIONS'),
        _settingToggle('End-of-day draft reminders', true, (v) {}),
        _settingToggle('New report alerts', true, (v) {}),
        _settingToggle('Flagged location alerts', true, (v) {}),
        const SizedBox(height: 24),

        _sectionTitle('SUPPORT'),
        _settingRow(Icons.help_outline, 'Help & FAQ', '', onTap: () {}),
        _settingRow(Icons.privacy_tip_outlined, 'Privacy Policy', '', onTap: () {}),
        _settingRow(Icons.info_outline, 'App Version', '1.0.0', onTap: null),
        const SizedBox(height: 32),

        AppButton(label: 'Log Out', isOutlined: true, color: AppColors.red, icon: Icons.logout_rounded, onPressed: _logout),
        const SizedBox(height: 40),
      ])),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
  );

  Widget _settingRow(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: AppColors.silver, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.light, fontSize: 15))),
          if (value.isNotEmpty) Text(value, style: const TextStyle(color: AppColors.silver, fontSize: 14)),
          if (onTap != null) const SizedBox(width: 6),
          if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
        ]),
      ),
    );
  }

  Widget _settingToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(label, style: const TextStyle(color: AppColors.light, fontSize: 14)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.brand,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}