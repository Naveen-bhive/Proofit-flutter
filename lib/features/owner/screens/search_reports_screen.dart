import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../shared/widgets/empty_state.dart';
import '../controllers/owner_controller.dart';

class SearchReportsScreen extends ConsumerStatefulWidget {
  const SearchReportsScreen({super.key});
  @override
  ConsumerState<SearchReportsScreen> createState() => _SearchReportsScreenState();
}

class _SearchReportsScreenState extends ConsumerState<SearchReportsScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;       // FIX #21 — debounce timer
  bool _isSearching = false;

  @override
  void dispose() { _ctrl.dispose(); _debounce?.cancel(); super.dispose(); }

  // FIX #21 — Debounce 500ms — don't call API on every keystroke
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) return;
    setState(() => _isSearching = true);
    await ref.read(ownerControllerProvider.notifier).searchReports(query.trim());
    if (mounted) setState(() => _isSearching = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search by job title, staff name...',
            hintStyle: const TextStyle(color: AppColors.muted),
            border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, color: AppColors.muted),
                    onPressed: () { _ctrl.clear(); setState(() {}); })
                : null,
          ),
          onChanged: (v) { setState(() {}); _onSearchChanged(v); }, // FIX #21
          onSubmitted: _search,
        ),
      ),
      body: _ctrl.text.isEmpty
          ? _emptyState()
          : _isSearching
              ? const ReportListShimmer()
              : state.searchResults.isEmpty
                  ? const EmptyState(type: EmptyType.search)
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.searchResults.length,
                      itemBuilder: (_, i) => ReportCard(
                        report: state.searchResults[i], showStaffName: true,
                        onTap: () => context.push('/owner/report/${state.searchResults[i].id}'),
                      ),
                    ),
    );
  }

  Widget _emptyState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.search, color: AppColors.muted, size: 64),
    const SizedBox(height: 16),
    const Text('Search reports', style: TextStyle(color: AppColors.silver, fontSize: 16)),
    const SizedBox(height: 8),
    const Text('Type job title, staff name or location', style: TextStyle(color: AppColors.muted, fontSize: 13)),
    const SizedBox(height: 24),
    Wrap(spacing: 8, children: [
      for (final hint in ['AC Service', 'Electrical', 'Plumbing', 'Painting'])
        GestureDetector(
          onTap: () { _ctrl.text = hint; _search(hint); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(100), border: Border.all(color: AppColors.border)),
            child: Text(hint, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
          ),
        ),
    ]),
  ]));
}