import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../shared/services/auth_storage.dart';
import '../controllers/owner_controller.dart';

class OwnerHistoryScreen extends ConsumerStatefulWidget {
  final String? initialStatus;
  const OwnerHistoryScreen({super.key, this.initialStatus});
  @override ConsumerState<OwnerHistoryScreen> createState() => _OwnerHistoryScreenState();
}

class _OwnerHistoryScreenState extends ConsumerState<OwnerHistoryScreen> {
  String _filter      = 'today';
  late String _status;
  String? _staffId;
  String? _staffName;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _exporting     = false;
  bool _loading       = true;
  bool _loadingMore   = false;
  int  _page          = 1;
  bool _hasMore       = true;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus ?? 'submitted';
    _scroll.addListener(_onScroll);
    Future.microtask(_loadFirst);
    ref.read(ownerControllerProvider.notifier).loadStaff();
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 && _hasMore && !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() { _page = 1; _hasMore = true; _loading = true; });
    await ref.read(ownerControllerProvider.notifier).loadAllReports(
      filter:   _fromDate == null ? _filter : null,
      staffId:  _staffId,
      from:     _fromDate != null ? DateFormat('yyyy-MM-dd').format(_fromDate!) : null,
      to:       _toDate   != null ? DateFormat('yyyy-MM-dd').format(_toDate!)   : null,
      page:     1,
      status:   _status,
    );
    if (!mounted) return;
    final state = ref.read(ownerControllerProvider);
    setState(() { _page = 1; _hasMore = state.reportPagination?['hasMore'] == true; _loading = false; });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() { _loadingMore = true; _page++; });
    await ref.read(ownerControllerProvider.notifier).loadMoreReports(
      filter:  _fromDate == null ? _filter : null,
      staffId: _staffId,
      from:    _fromDate != null ? DateFormat('yyyy-MM-dd').format(_fromDate!) : null,
      to:      _toDate   != null ? DateFormat('yyyy-MM-dd').format(_toDate!)   : null,
      page:    _page,
      status:  _status,
    );
    final state = ref.read(ownerControllerProvider);
    setState(() { _loadingMore = false; _hasMore = state.reportPagination?['hasMore'] == true; });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024), lastDate: DateTime.now(),
      initialDateRange: _fromDate != null ? DateTimeRange(start: _fromDate!, end: _toDate ?? DateTime.now()) : null,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.brand)), child: child!),
    );
    if (picked != null) {
      setState(() { _fromDate = picked.start; _toDate = picked.end; _filter = ''; });
      _loadFirst();
    }
  }

  void _clearDateRange() { setState(() { _fromDate = null; _toDate = null; _filter = 'today'; }); _loadFirst(); }

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;
      final dio  = Dio();
      final dir  = await getTemporaryDirectory();
      final org  = ref.read(ownerControllerProvider).orgName.replaceAll(' ', '-');
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final ext  = format == 'excel' ? 'xlsx' : 'pdf';
      final path = '${dir.path}/proofit-$org-$date.$ext';

      final body = <String, dynamic>{'format': format};
      if (_fromDate != null) { body['from'] = DateFormat('yyyy-MM-dd').format(_fromDate!); body['to'] = DateFormat('yyyy-MM-dd').format(_toDate ?? DateTime.now()); }
      else if (_filter.isNotEmpty) {
        body['filter'] = _filter;
      }
      if (_staffId != null) body['staffId'] = _staffId;

      final res = await dio.post('${AppConstants.baseUrl}/reports/export',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $token'}, responseType: ResponseType.bytes));
      await File(path).writeAsBytes(res.data);
      if (!mounted) return;
      _showFileOptions(path);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not export reports. Please try again.');
    } finally { if (mounted) setState(() => _exporting = false); }
  }

  void _showFileOptions(String path) => showModalBottomSheet(
    context: context, backgroundColor: AppColors.dark2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
      const Text('Export Ready', style: TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      _optRow(Icons.open_in_new_rounded, AppColors.brand, 'Open File',  () { Navigator.pop(context); OpenFile.open(path); }),
      const SizedBox(height: 10),
      _optRow(Icons.share_outlined, AppColors.blue, 'Share', () async {
        Navigator.pop(context);
        await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      }),
      const SizedBox(height: 20),
    ])));

  Widget _optRow(IconData icon, Color c, String label, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.2))),
      child: Row(children: [Icon(icon, color: c, size: 22), const SizedBox(width: 14), Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 15)), const Spacer(), Icon(Icons.chevron_right, color: c.withValues(alpha: 0.5), size: 18)])));

  void _showExportOptions() => showModalBottomSheet(
    context: context, backgroundColor: AppColors.dark2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
      const Text('Export Reports', style: TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      if (_fromDate != null) Padding(padding: const EdgeInsets.only(top: 6),
        child: Text('${DateFormat("d MMM").format(_fromDate!)} â€“ ${DateFormat("d MMM").format(_toDate ?? DateTime.now())}',
          style: const TextStyle(color: AppColors.silver, fontSize: 13))),
      const SizedBox(height: 20),
      _optRow(Icons.picture_as_pdf_outlined, AppColors.red, 'Export as PDF',   () { Navigator.pop(context); _export('pdf'); }),
      const SizedBox(height: 10),
      _optRow(Icons.table_chart_outlined,    AppColors.green, 'Export as Excel', () { Navigator.pop(context); _export('excel'); }),
      const SizedBox(height: 20),
    ])));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('Reports History'),
        actions: [
          if (_exporting)
            const Padding(padding: EdgeInsets.only(right: 16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))))
          else
            IconButton(icon: const Icon(Icons.download_outlined, color: AppColors.brand), onPressed: _showExportOptions),
          IconButton(icon: const Icon(Icons.search_outlined), onPressed: () => context.push('/owner/search')),
        ],
      ),
      body: Column(children: [
        // Filter row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            // Date range filter (FIX 6)
            GestureDetector(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _fromDate != null ? AppColors.brand.withValues(alpha: 0.2) : AppColors.dark3,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _fromDate != null ? AppColors.brand : AppColors.border)),
                child: Row(children: [
                  Icon(Icons.date_range_outlined, color: _fromDate != null ? AppColors.brand : AppColors.silver, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    _fromDate != null ? '${DateFormat("d MMM").format(_fromDate!)}â€“${DateFormat("d MMM").format(_toDate ?? DateTime.now())}' : 'Date Range',
                    style: TextStyle(color: _fromDate != null ? AppColors.brand : AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600)),
                  if (_fromDate != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(onTap: _clearDateRange, child: const Icon(Icons.close, color: AppColors.brand, size: 14)),
                  ],
                ]),
              ),
            ),
            // Quick filters
            for (final f in [('today','Today'),('week','This Week'),('month','This Month')])
              GestureDetector(
                onTap: () { setState(() { _filter = f.$1; _fromDate = null; _toDate = null; }); _loadFirst(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _filter == f.$1 && _fromDate == null ? AppColors.brand.withValues(alpha: 0.2) : AppColors.dark3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _filter == f.$1 && _fromDate == null ? AppColors.brand : AppColors.border)),
                  child: Text(f.$2, style: TextStyle(color: _filter == f.$1 && _fromDate == null ? AppColors.brand : AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600))),
              ),
          ]),
        ),

        // Status filter
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            for (final s in [('submitted','Submitted'),('draft','Drafts'),('all','All')])
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: GestureDetector(
                onTap: () { setState(() => _status = s.$1); _loadFirst(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _status == s.$1 ? AppColors.brand.withValues(alpha: 0.2) : AppColors.dark3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _status == s.$1 ? AppColors.brand : AppColors.border)),
                  child: Text(s.$2, textAlign: TextAlign.center,
                    style: TextStyle(color: _status == s.$1 ? AppColors.brand : AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ))),
          ])),

        // Staff filter row (FIX 4)
        if (_staffId != null || state.staffList.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              GestureDetector(
                onTap: () { setState(() { _staffId = null; _staffName = null; }); _loadFirst(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(right: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: _staffId == null ? AppColors.brand.withValues(alpha: 0.15) : AppColors.dark3,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: _staffId == null ? AppColors.brand : AppColors.border)),
                  child: Text('All Staff', style: TextStyle(color: _staffId == null ? AppColors.brand : AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600))),
              ),
              ...state.staffList.map((s) {
                final sid  = s['_id']?.toString();
                final sname = s['name'] ?? '';
                final sel  = _staffId == sid;
                return GestureDetector(
                  onTap: () { setState(() { _staffId = sid; _staffName = sname; }); _loadFirst(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    margin: const EdgeInsets.only(right: 8, bottom: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.brand.withValues(alpha: 0.15) : AppColors.dark3,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: sel ? AppColors.brand : AppColors.border)),
                    child: Text(sname, style: TextStyle(color: sel ? AppColors.brand : AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600))),
                );
              }),
            ]),
          ),

        // Count row
        if (state.reportPagination != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('${state.reportPagination!['total'] ?? 0} reports', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (_staffName != null) ...[
                const Text(' â€¢ ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(_staffName!, style: const TextStyle(color: AppColors.brand, fontSize: 12)),
              ],
            ])),

        // Reports list with pagination
        Expanded(child: _loading && state.allReports.isEmpty
          ? const ReportListShimmer()
          : state.allReports.isEmpty
            ? EmptyState(type: EmptyType.history, actionLabel: 'Refresh', onAction: _loadFirst)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: state.allReports.length + (_loadingMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == state.allReports.length) {
                    return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2)));
                  }
                  return ReportCard(
                    report: state.allReports[i], showStaffName: true,
                    onTap: () => context.push('/owner/report/${state.allReports[i].id}'));
                })),
      ]),
    );
  }
}
