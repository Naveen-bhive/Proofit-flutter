import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Search field + scrollable list for picking one item (customer, staff, etc.).
/// Results appear only after the user types a search query.
class SearchableSelectionField extends StatefulWidget {
  final String sectionLabel;
  final String searchHint;
  final String emptyMessage;
  final String typeToSearchMessage;
  final List<Map<String, dynamic>> items;
  final String? selectedId;
  final String Function(Map<String, dynamic>) itemId;
  final String Function(Map<String, dynamic>) itemTitle;
  final String Function(Map<String, dynamic>) itemSubtitle;
  final bool Function(Map<String, dynamic>)? itemEnabled;
  final ValueChanged<String?> onSelected;

  const SearchableSelectionField({
    super.key,
    required this.sectionLabel,
    required this.searchHint,
    required this.emptyMessage,
    this.typeToSearchMessage = 'Type to search',
    required this.items,
    required this.selectedId,
    required this.itemId,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.onSelected,
    this.itemEnabled,
  });

  @override
  State<SearchableSelectionField> createState() => _SearchableSelectionFieldState();
}

class _SearchableSelectionFieldState extends State<SearchableSelectionField> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selectedItem {
    if (widget.selectedId == null) return null;
    for (final item in widget.items) {
      if (widget.itemId(item) == widget.selectedId) return item;
    }
    return null;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    return widget.items.where((item) {
      final title = widget.itemTitle(item).toLowerCase();
      final subtitle = widget.itemSubtitle(item).toLowerCase();
      return title.contains(q) || subtitle.contains(q);
    }).toList();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {});
  }

  void _selectItem(Map<String, dynamic> item) {
    widget.onSelected(widget.itemId(item));
    _clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim();
    final filtered = _filtered;
    final selected = _selectedItem;
    final showResults = query.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.sectionLabel,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: widget.searchHint,
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: AppColors.muted),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.muted),
                    onPressed: _clearSearch,
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (selected != null && !showResults) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.brand, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.itemTitle(selected),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.itemSubtitle(selected).isNotEmpty)
                        Text(
                          widget.itemSubtitle(selected),
                          style: const TextStyle(color: AppColors.silver, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.muted, size: 18),
                  onPressed: () => widget.onSelected(null),
                  tooltip: 'Clear selection',
                ),
              ],
            ),
          ),
        ],
        if (showResults) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Material(
              color: AppColors.dark3,
              child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.emptyMessage,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      final id = widget.itemId(item);
                      final enabled = widget.itemEnabled?.call(item) ?? true;
                      final isSelected = widget.selectedId == id;

                      return ListTile(
                        dense: true,
                        enabled: enabled,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: (isSelected ? AppColors.brand : AppColors.muted)
                              .withValues(alpha: 0.15),
                          child: Text(
                            widget.itemTitle(item).isNotEmpty
                                ? widget.itemTitle(item)[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: isSelected ? AppColors.brand : AppColors.silver,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        title: Text(
                          widget.itemTitle(item),
                          style: TextStyle(
                            color: enabled
                                ? (isSelected ? AppColors.brand : AppColors.white)
                                : AppColors.muted,
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: widget.itemSubtitle(item).isNotEmpty
                            ? Text(
                                widget.itemSubtitle(item),
                                style: TextStyle(
                                  color: enabled ? AppColors.silver : AppColors.muted,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: AppColors.brand, size: 20)
                            : null,
                        onTap: enabled ? () => _selectItem(item) : null,
                      );
                    },
                  ),
            ),
          ),
        ] else if (selected == null) ...[
          const SizedBox(height: 6),
          Text(
            widget.typeToSearchMessage,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
