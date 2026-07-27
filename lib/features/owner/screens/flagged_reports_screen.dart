import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/owner_controller.dart';

class FlaggedReportsScreen extends ConsumerStatefulWidget {
  const FlaggedReportsScreen({super.key});
  @override
  ConsumerState<FlaggedReportsScreen> createState() => _FlaggedReportsScreenState();
}

class _FlaggedReportsScreenState extends ConsumerState<FlaggedReportsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ownerControllerProvider.notifier).loadFlaggedReports());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: Row(children: [
          const Text('Flagged Reports'),
          if (state.flaggedReports.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(100)),
              child: Text('${state.flaggedReports.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : state.flaggedReports.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified_user_outlined, color: AppColors.green, size: 56),
                  SizedBox(height: 12),
                  Text('No flagged reports', style: TextStyle(color: AppColors.green, fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('All reports have verified locations', style: TextStyle(color: AppColors.silver, fontSize: 13)),
                ]))
              : Column(children: [
                  // Warning header
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.red.withOpacity(0.3))),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        '${state.flaggedReports.length} report(s) have suspicious location data. Review them below.',
                        style: const TextStyle(color: AppColors.red, fontSize: 13),
                      )),
                    ]),
                  ),
                  Expanded(child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.flaggedReports.length,
                    itemBuilder: (_, i) {
                      final r = state.flaggedReports[i];
                      return GestureDetector(
                        onTap: () => context.push('/owner/report/${r.id}'),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.dark2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.red.withOpacity(0.4)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(r.jobTitle, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600))),
                              Text(r.submittedAt != null ? DateFormat('d MMM, h:mm a').format(r.submittedAt!) : '',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ]),
                            const SizedBox(height: 6),
                            Text(r.staffName, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                            if (r.location?.flagReason != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: AppColors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text(r.location!.flagReason!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
                              ),
                            ],
                          ]),
                        ),
                      );
                    },
                  )),
                ]),
    );
  }
}