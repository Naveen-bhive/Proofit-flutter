import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/report_card.dart';
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
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Report History')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            for (final f in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _setFilter(f.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _filter == f.$1 ? AppColors.brand : AppColors.dark3,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: _filter == f.$1 ? AppColors.brand : AppColors.border),
                    ),
                    child: Text(f.$2,
                      style: TextStyle(
                        color: _filter == f.$1 ? Colors.white : AppColors.silver,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                  ),
                ),
              ),
          ]),
        ),

        Expanded(child: RefreshIndicator(
          color: AppColors.brand,
          onRefresh: () async => reload(),
          child: state.historyLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
              : state.historyReports.isEmpty
                  ? ListView(children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                      Center(child: Text(
                        _filter == 'drafts' ? 'No draft reports saved' : 'No reports in this period',
                        style: const TextStyle(color: AppColors.silver))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: state.historyReports.length,
                      itemBuilder: (_, i) {
                        final report = state.historyReports[i];
                        return ReportCard(
                          report: report,
                          onTap: () {
                            if (report.status == 'draft') {
                              context.push('/staff/draft/${report.id}');
                            } else {
                              context.push('/staff/report/${report.id}');
                            }
                          },
                        );
                      },
                    ),
        )),
      ]),
    );
  }
}
