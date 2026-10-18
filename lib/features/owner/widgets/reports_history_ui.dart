import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';

/// Presentation pieces shared by the owner "Reports" tab and "Reports History".

/// Rounded-rectangle filter chip used by the reports filter rows.
class ReportFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final VoidCallback? onClear;
  const ReportFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.brand : AppColors.light;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandSoft : AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.brand : AppColors.border),
          boxShadow: AppColors.softShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500)),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            GestureDetector(onTap: onClear, child: Icon(Icons.close_rounded, size: 14, color: fg)),
          ],
        ]),
      ),
    );
  }
}

/// Date + status + staff filter block.
class ReportsFilterBar extends StatelessWidget {
  final String filter;
  final String status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onStatus;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;
  final List<Map<String, dynamic>> staff;
  final String? staffId;
  final void Function(String? id, String? name) onStaff;
  final int? total;

  const ReportsFilterBar({
    super.key,
    required this.filter,
    required this.status,
    required this.fromDate,
    required this.toDate,
    required this.onFilter,
    required this.onStatus,
    required this.onPickRange,
    required this.onClearRange,
    required this.staff,
    required this.staffId,
    required this.onStaff,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ranged = fromDate != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
        child: Row(children: [
          ReportFilterChip(
            label: ranged
                ? '${DateFormat('d MMM').format(fromDate!)} - ${DateFormat('d MMM').format(toDate ?? DateTime.now())}'
                : 'Date Range',
            icon: Icons.calendar_today_outlined,
            selected: ranged,
            onTap: onPickRange,
            onClear: ranged ? onClearRange : null,
          ),
          for (final f in const [('today', 'Today'), ('week', 'This Week'), ('month', 'This Month')]) ...[
            const SizedBox(width: 8),
            ReportFilterChip(label: f.$2, selected: !ranged && filter == f.$1, onTap: () => onFilter(f.$1)),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        child: Row(children: [
          for (final s in const [('submitted', 'Submitted'), ('draft', 'Drafts'), ('all', 'All')]) ...[
            ReportFilterChip(label: s.$2, selected: status == s.$1, onTap: () => onStatus(s.$1)),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Row(children: [
          StaffDropdownButton(staff: staff, selectedId: staffId, onSelected: onStaff),
          const Spacer(),
          if (total != null) Text('$total reports', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]),
      ),
    ]);
  }
}

/// "All Staff (12) ⌄" pill that opens an anchored, searchable staff list.
class StaffDropdownButton extends StatefulWidget {
  final List<Map<String, dynamic>> staff;
  final String? selectedId;
  final void Function(String? id, String? name) onSelected;
  const StaffDropdownButton({super.key, required this.staff, required this.selectedId, required this.onSelected});

  @override
  State<StaffDropdownButton> createState() => _StaffDropdownButtonState();
}

class _StaffDropdownButtonState extends State<StaffDropdownButton> {
  final _key = GlobalKey();

  String get _label {
    if (widget.selectedId == null) return 'All Staff';
    for (final s in widget.staff) {
      if (s['_id']?.toString() == widget.selectedId) return (s['name'] ?? 'Staff').toString();
    }
    return 'Staff';
  }

  Future<void> _open() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final result = await showGeneralDialog<({String? id, String? name})>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, __) => Stack(children: [
        Positioned(
          left: origin.dx,
          top: origin.dy + box.size.height + 8,
          width: (MediaQuery.sizeOf(ctx).width - origin.dx * 2).clamp(260, 360).toDouble(),
          child: _StaffMenu(staff: widget.staff, selectedId: widget.selectedId),
        ),
      ]),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), alignment: Alignment.topLeft, child: child),
      ),
    );
    if (result != null) widget.onSelected(result.id, result.name);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selectedId != null;
    return GestureDetector(
      key: _key,
      onTap: widget.staff.isEmpty ? null : _open,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.brand.withValues(alpha: active ? 0.9 : 0.55), width: 1.3),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.groups_outlined, size: 17, color: AppColors.brand),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(_label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (!active && widget.staff.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(6)),
              child: Text('${widget.staff.length}',
                  style: const TextStyle(color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.brand),
        ]),
      ),
    );
  }
}

class _StaffMenu extends StatefulWidget {
  final List<Map<String, dynamic>> staff;
  final String? selectedId;
  const _StaffMenu({required this.staff, required this.selectedId});

  @override
  State<_StaffMenu> createState() => _StaffMenuState();
}

class _StaffMenuState extends State<_StaffMenu> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = widget.staff
        .where((s) => q.isEmpty || (s['name'] ?? '').toString().toLowerCase().contains(q))
        .toList();
    return Material(
      color: AppColors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 340),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Color(0x220F172A), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.text, fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search staff members...',
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () => setState(_q.clear),
                        child: const Icon(Icons.close_rounded, size: 17),
                      ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          Flexible(
            child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
              if (q.isEmpty)
                _row(
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                    child: const Icon(Icons.groups_outlined, size: 17, color: AppColors.white),
                  ),
                  title: 'All Staff',
                  subtitle: '${widget.staff.length} members',
                  selected: widget.selectedId == null,
                  onTap: () => Navigator.pop(context, (id: null, name: null)),
                ),
              ...list.map((s) {
                final id = s['_id']?.toString();
                final name = (s['name'] ?? 'Staff').toString();
                final pending = s['invitePending'] == true || s['inviteStatus'] == 'pending';
                return _row(
                  leading: InitialAvatar(name: name, size: 30),
                  title: name,
                  subtitle: pending ? 'Invite pending' : 'Field Staff',
                  selected: widget.selectedId == id,
                  onTap: () => Navigator.pop(context, (id: id, name: name)),
                );
              }),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row({
    required Widget leading,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.brandSoft : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: selected ? AppColors.brand : AppColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
          if (selected) const Icon(Icons.check_rounded, color: AppColors.brand, size: 18),
        ]),
      ),
    );
  }
}

/// Empty state for the reports lists (clipboard illustration + Refresh).
class ReportsEmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const ReportsEmptyState({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(40, 50, 40, 24), children: [
      Center(
        child: SizedBox(
          width: 200,
          height: 140,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 180,
              height: 120,
              decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(70)),
            ),
            Container(
              width: 84,
              height: 104,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF93C5FD), width: 3),
                boxShadow: AppColors.cardShadow,
              ),
              child: const Icon(Icons.block_rounded, color: AppColors.red, size: 42),
            ),
            Positioned(
              top: 6,
              child: Container(
                width: 34,
                height: 14,
                decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(5)),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Text('No reports found', textAlign: TextAlign.center,
          style: AppTextStyles.h3.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Reports your staff submit will appear here.',
          textAlign: TextAlign.center, style: TextStyle(color: AppColors.silver, fontSize: 14.5, height: 1.5)),
      const SizedBox(height: 28),
      PrimaryButton(label: 'Refresh', icon: Icons.refresh_rounded, onPressed: onRefresh),
    ]);
  }
}

/// "Export Reports" sheet. Returns 'pdf', 'excel' or null.
Future<String?> showExportOptionsSheet(BuildContext context, {String? rangeLabel}) {
  Widget option(BuildContext ctx, String format, IconData icon, Color color, String title, String subtitle) {
    return SurfaceCard(
      radius: 16,
      borderColor: color.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.pop(ctx, format),
      child: Row(children: [
        IconTile(icon: icon, color: color, size: 46, iconSize: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppColors.silver, fontSize: 12.5, height: 1.35)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: color),
      ]),
    );
  }

  return AppSheet.show<String>(
    context,
    builder: (ctx) => AppSheet(
      title: 'Export Reports',
      subtitle: rangeLabel ?? 'Select your preferred export format',
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        option(ctx, 'pdf', Icons.picture_as_pdf_outlined, AppColors.red, 'Export as PDF',
            'Download styled document with before & after photos'),
        const SizedBox(height: 12),
        option(ctx, 'excel', Icons.table_chart_outlined, AppColors.greenDark, 'Export as Excel',
            'Raw spreadsheet data (.xlsx) for audits'),
        const SizedBox(height: 16),
        SecondaryButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
      ]),
    ),
  );
}

/// "Export Ready" sheet shown after a successful export.
Future<void> showExportReadySheet(
  BuildContext context, {
  required String path,
  required VoidCallback onOpen,
  required VoidCallback onShare,
  String shareSubtitle = 'Send via WhatsApp, Mail, or AirDrop',
}) {
  final name = path.split(Platform.pathSeparator).last;
  final isPdf = name.toLowerCase().endsWith('.pdf');
  String size = '';
  try {
    final bytes = File(path).lengthSync();
    size = bytes > 1024 * 1024
        ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).toStringAsFixed(0)} KB';
  } catch (_) {}

  Widget action(BuildContext ctx, IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return SurfaceCard(
      radius: 16,
      gradient: LinearGradient(colors: [color.withValues(alpha: 0.06), AppColors.white]),
      borderColor: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(14),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: AppColors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
          ]),
        ),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(Icons.chevron_right_rounded, color: color, size: 20),
        ),
      ]),
    );
  }

  return AppSheet.show<void>(
    context,
    builder: (ctx) => AppSheet(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
              ),
              child: Container(
                decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.check_rounded, color: AppColors.white, size: 26),
              ),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 2),
                ),
                child: const Icon(Icons.download_rounded, color: AppColors.white, size: 12),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        const Center(child: SoftBadge(label: 'File Generated', color: AppColors.greenDark, dot: true, uppercase: true, fontSize: 10.5)),
        const SizedBox(height: 10),
        Text('Export Ready', textAlign: TextAlign.center, style: AppTextStyles.h2.copyWith(fontSize: 23)),
        const SizedBox(height: 8),
        const Text(
          'Your report archive has been compiled successfully and is prepared for viewing or distribution.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.silver, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          radius: 14,
          color: AppColors.dark3,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isPdf ? AppColors.redSoft : AppColors.greenSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (isPdf ? AppColors.red : AppColors.green).withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(isPdf ? 'PDF' : 'XLS',
                    style: TextStyle(
                        color: isPdf ? AppColors.red : AppColors.greenDark, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text('${size.isEmpty ? '' : '$size • '}Generated just now',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text('Complete', style: TextStyle(color: AppColors.light, fontSize: 11.5)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        action(ctx, Icons.open_in_new_rounded, AppColors.brand, 'Open File', 'Preview report document immediately', onOpen),
        const SizedBox(height: 12),
        action(ctx, Icons.share_outlined, AppColors.greenDark, 'Share', shareSubtitle, onShare),
        const SizedBox(height: 14),
        SecondaryButton(label: 'Dismiss', fill: AppColors.dark4, onPressed: () => Navigator.pop(ctx)),
      ]),
    ),
  );
}
