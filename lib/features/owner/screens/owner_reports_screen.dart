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
import '../../../core/utils/export_file_utils.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../widgets/reports_history_ui.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../shared/services/auth_storage.dart';
import '../controllers/owner_controller.dart';

class OwnerReportsScreen extends ConsumerStatefulWidget {
  const OwnerReportsScreen({super.key});
  @override ConsumerState<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends ConsumerState<OwnerReportsScreen> {
  String    _filter   = 'today';
  String    _status   = 'submitted';
  String?   _staffId;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool      _exporting  = false;
  bool      _loading    = true;
  bool      _loadingMore = false;
  int       _page       = 1;
  bool      _hasMore    = true;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
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
      filter:  _fromDate == null ? _filter : null,
      staffId: _staffId,
      from:    _fromDate != null ? DateFormat('yyyy-MM-dd').format(_fromDate!) : null,
      to:      _toDate   != null ? DateFormat('yyyy-MM-dd').format(_toDate!)   : null,
      page:    1,
      status:  _status,
    );
    if (!mounted) return;
    final pagination = ref.read(ownerControllerProvider).reportPagination;
    setState(() { _page = 1; _hasMore = pagination?['hasMore'] == true; _loading = false; });
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
    final pagination = ref.read(ownerControllerProvider).reportPagination;
    setState(() { _loadingMore = false; _hasMore = pagination?['hasMore'] == true; });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024), lastDate: DateTime.now(),
      initialDateRange: _fromDate != null ? DateTimeRange(start: _fromDate!, end: _toDate ?? DateTime.now()) : null,
    );
    if (picked != null) {
      setState(() { _fromDate = picked.start; _toDate = picked.end; _filter = ''; });
      _loadFirst();
    }
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;
      final dio  = Dio();
      final dir  = await getTemporaryDirectory();
      final org  = exportFileNamePart(ref.read(ownerControllerProvider).orgName);
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
      _showFileSheet(path);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not export reports. Please try again.');
    } finally { if (mounted) setState(() => _exporting = false); }
  }

  void _showFileSheet(String path) => showExportReadySheet(
    context,
    path: path,
    onOpen: () => OpenFile.open(path),
    onShare: () => SharePlus.instance.share(ShareParams(files: [XFile(path)], subject: 'Work Completion Report')),
  );

  Future<void> _showExportOptions() async {
    final format = await showExportOptionsSheet(
      context,
      rangeLabel: _fromDate == null
          ? null
          : '${DateFormat("d MMM").format(_fromDate!)} - ${DateFormat("d MMM").format(_toDate ?? DateTime.now())}',
    );
    if (format != null) _export(format);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'Reports History',
            showBack: Navigator.of(context).canPop(),
            titleSize: 21,
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            actions: [
              if (_exporting)
                const SizedBox(width: 38, height: 38, child: Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)))
              else
                IconButton(icon: const Icon(Icons.file_download_outlined, color: AppColors.text), onPressed: _showExportOptions),
              IconButton(icon: const Icon(Icons.search_rounded, color: AppColors.text), onPressed: () => context.push('/owner/search')),
            ],
          ),
          ReportsFilterBar(
            filter: _filter,
            status: _status,
            fromDate: _fromDate,
            toDate: _toDate,
            onFilter: (f) { setState(() { _filter = f; _fromDate = null; _toDate = null; }); _loadFirst(); },
            onStatus: (s) { setState(() => _status = s); _loadFirst(); },
            onPickRange: _pickDateRange,
            onClearRange: () { setState(() { _fromDate = null; _toDate = null; _filter = 'today'; }); _loadFirst(); },
            staff: state.staffList,
            staffId: _staffId,
            onStaff: (id, _) { setState(() { _staffId = id; }); _loadFirst(); },
            total: state.reportPagination == null ? null : (state.reportPagination!['total'] as num?)?.toInt() ?? 0,
          ),
          const SizedBox(height: 8),
          Expanded(child: _loading && state.allReports.isEmpty
            ? const ReportListShimmer()
            : state.allReports.isEmpty
              ? ReportsEmptyState(onRefresh: _loadFirst)
              : RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: _loadFirst,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: state.allReports.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == state.allReports.length) {
                        return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2)));
                      }
                      return ReportCard(
                        report: state.allReports[i], showStaffName: true, actionLabel: 'View',
                        onTap: () => context.push('/owner/report/${state.allReports[i].id}'));
                    }),
                )),
        ]),
      ),
    );
  }
}
