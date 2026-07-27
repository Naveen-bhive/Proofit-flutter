import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/empty_state.dart';
import '../controllers/owner_controller.dart';

class StaffProfileScreen extends ConsumerStatefulWidget {
  final String staffId;
  const StaffProfileScreen({super.key, required this.staffId});
  @override
  ConsumerState<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends ConsumerState<StaffProfileScreen> {
  @override
  void initState() {
    super.initState();
    // loadStaffProfile — fetches profile + reports
    Future.microtask(() => ref.read(ownerControllerProvider.notifier).loadStaffProfile(widget.staffId));
  }

  void _showSetTargetDialog(BuildContext context, int current) {
    final ctrl = TextEditingController(text: '$current');
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.dark2,
      title: const Text('Set Daily Target', style: TextStyle(color: AppColors.white)),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number,
        style: const TextStyle(color: AppColors.white),
        decoration: const InputDecoration(labelText: 'Jobs per day')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.silver))),
        TextButton(onPressed: () {
          final val = int.tryParse(ctrl.text.trim());
          if (val != null) {
            // setStaffTarget — updates target and notifies staff
            ref.read(ownerControllerProvider.notifier).setStaffTarget(widget.staffId, val);
          }
          Navigator.pop(context);
        }, child: const Text('Save', style: TextStyle(color: AppColors.brand))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state   = ref.watch(ownerControllerProvider);
    final profile = state.selectedStaffProfile;
    // staffReports — reports for this staff member
    final staffReports = state.staffReports;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Text(profile?['name'] ?? 'Staff Profile'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red),
            onPressed: () async {
              await ref.read(ownerControllerProvider.notifier).removeStaff(widget.staffId);
              if (context.mounted) context.pop();
            }),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
              const SizedBox(height: 10),
              CircleAvatar(radius: 40, backgroundColor: AppColors.brand.withOpacity(0.2),
                child: Text((profile['name'] as String? ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: AppColors.brand, fontSize: 30, fontWeight: FontWeight.w800))),
              const SizedBox(height: 14),
              Text(profile['name'] ?? '', style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              Text(profile['phone'] ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 14)),
              const SizedBox(height: 8),
              if ((profile['streak'] ?? 0) > 0)
                Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.12), borderRadius: BorderRadius.circular(100)),
                  child: Text('🔥 ${profile['streak']}-day streak', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700))),
              const SizedBox(height: 28),

              Row(children: [
                _stat('Today',  '${profile['todayCount']  ?? 0}', AppColors.brand),
                const SizedBox(width: 10),
                _stat('Week',   '${profile['weekCount']   ?? 0}', AppColors.blue),
                const SizedBox(width: 10),
                _stat('Month',  '${profile['monthCount']  ?? 0}', AppColors.green),
                const SizedBox(width: 10),
                _stat('Total',  '${profile['totalCount']  ?? 0}', AppColors.yellow),
              ]),
              const SizedBox(height: 20),

              Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  const Icon(Icons.flag_outlined, color: AppColors.brand, size: 22),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Daily Target', style: TextStyle(color: AppColors.silver, fontSize: 12)),
                    Text('${profile['dailyTarget'] ?? 0} jobs/day', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  ]),
                  const Spacer(),
                  TextButton(onPressed: () => _showSetTargetDialog(context, profile['dailyTarget'] ?? 0),
                    child: const Text('Edit', style: TextStyle(color: AppColors.brand))),
                ])),
              const SizedBox(height: 24),

              const Align(alignment: Alignment.centerLeft,
                child: Text('Recent Reports', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16))),
              const SizedBox(height: 12),
              if (staffReports.isEmpty)
                const EmptyState(type: EmptyType.reports)
              else
                ...staffReports.map((r) => ReportCard(report: r,
                  onTap: () => context.push('/owner/report/${r.id}'))),
              const SizedBox(height: 40),
            ])),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 11)),
    ])));
}