import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../controllers/staff_controller.dart';

class StaffHistoryScreen extends ConsumerStatefulWidget {
  final String? initialFilter;
  final bool autoLoad;
  const StaffHistoryScreen({super.key, this.initialFilter, this.autoLoad = true});

  @override
  ConsumerState<StaffHistoryScreen> createState() => StaffHistoryScreenState();
}

class StaffHistoryScreenState extends ConsumerState<StaffHistoryScreen> {
  late String _filter;

  static const _filters = [
    ('today', 'Today'),
    ('week', 'Week'),
    ('month', 'Month'),
    ('all', 'All'),
    ('drafts', 'Drafts'),
  ];

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? 'week';
    if (widget.autoLoad) {
      Future.microtask(() => reload());
    }
  }

  void reload() => ref.read(staffControllerProvider.notifier).loadHistory(_filter);

  void _setFilter(String f) {
    setState(() => _filter = f);
    ref.read(staffControllerProvider.notifier).loadHistory(f);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'Report History',
            subtitle: 'Verified field records & telemetry',
            showBack: canPop,
            titleSize: 22,
            padding: EdgeInsets.fromLTRB(canPop ? 16 : 20, 14, 16, 12),
          ),
          PillChipBar(
            chips: [
              for (final f in _filters)
                PillChip(
                  label: f.$2,
                  selected: _filter == f.$1,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  onTap: () => _setFilter(f.$1),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brand,
              onRefresh: () async => reload(),
              child: state.historyLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                  : state.historyReports.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 90),
                          SoftEmptyState(
                            icon: _filter == 'drafts' ? Icons.drafts_outlined : Icons.history_rounded,
                            title: _filter == 'drafts' ? 'No draft reports saved' : 'No reports in this period',
                            subtitle: 'Reports you submit will appear here.',
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [
                            for (final report in state.historyReports)
                              ReportCard(
                                report: report,
                                actionLabel: report.status == 'draft' ? 'Continue' : 'View Report',
                                onTap: () {
                                  if (report.status == 'draft') {
                                    context.push('/staff/draft/${report.id}');
                                  } else {
                                    context.push('/staff/report/${report.id}');
                                  }
                                },
                              ),
                            const SizedBox(height: 4),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(100)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.check_circle_rounded, size: 15, color: AppColors.greenDark),
                                  SizedBox(width: 6),
                                  Text('Time & GPS stamped proof',
                                      style: TextStyle(color: AppColors.light, fontSize: 12, fontWeight: FontWeight.w500)),
                                ]),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ]),
      ),
    );
  }
}
