import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';

/// Shared models and widgets for the staff leave request and owner leave
/// management screens.

const leaveDurations = <String, String>{
  'full_day': 'Full Day',
  'multiple': 'Multiple',
  'first_half': 'First Half',
  'second_half': 'Second Half',
};

const leaveStatuses = <String, String>{
  'approved': 'Approved',
  'pending': 'Pending',
  'rejected': 'Rejected',
  'cancelled': 'Cancelled',
};

Color leaveStatusColor(String status) => switch (status) {
      'approved' => AppColors.green,
      'pending' => AppColors.yellow,
      'rejected' => AppColors.red,
      _ => AppColors.silver,
    };

Color parseHexColor(String? hex, {Color fallback = AppColors.brand}) {
  final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

class LeaveType {
  final String id;
  final String name;
  final String description;
  final Color color;
  const LeaveType(this.id, this.name, this.description, this.color);

  factory LeaveType.fromJson(Map<String, dynamic> j) => LeaveType(
        j['_id'].toString(),
        (j['name'] ?? '').toString(),
        (j['description'] ?? '').toString(),
        parseHexColor(j['color']?.toString()),
      );
}

class LeaveMember {
  final String id;
  final String name;
  final String phone;
  final String? photoUrl;
  const LeaveMember(this.id, this.name, this.phone, this.photoUrl);

  factory LeaveMember.fromJson(Map<String, dynamic> j) => LeaveMember(
        j['_id'].toString(),
        (j['name'] ?? 'Staff').toString(),
        (j['phone'] ?? j['email'] ?? '').toString(),
        j['photoUrl']?.toString(),
      );
}

class LeaveRecord {
  final String id;
  final LeaveMember? staff;
  final String leaveTypeId;
  final String leaveTypeName;
  final String duration;
  final DateTime start;
  final DateTime end;
  final num days;
  final String reason;
  final String? attachmentUrl;
  final String status;
  final String? reviewedBy;
  final DateTime? createdAt;

  const LeaveRecord({
    required this.id,
    required this.staff,
    required this.leaveTypeId,
    required this.leaveTypeName,
    required this.duration,
    required this.start,
    required this.end,
    required this.days,
    required this.reason,
    required this.attachmentUrl,
    required this.status,
    required this.reviewedBy,
    required this.createdAt,
  });

  bool get isHalfDay => duration == 'first_half' || duration == 'second_half';

  factory LeaveRecord.fromJson(Map<String, dynamic> j) {
    final staff = j['staffId'];
    final reviewer = j['reviewedBy'];
    final start = DateTime.parse(j['startDate'].toString());
    return LeaveRecord(
      id: j['_id'].toString(),
      staff: staff is Map ? LeaveMember.fromJson(Map<String, dynamic>.from(staff)) : null,
      leaveTypeId: j['leaveTypeId'].toString(),
      leaveTypeName: (j['leaveTypeName'] ?? '').toString(),
      duration: (j['duration'] ?? 'full_day').toString(),
      start: start,
      end: DateTime.tryParse(j['endDate']?.toString() ?? '') ?? start,
      days: (j['days'] as num?) ?? 1,
      reason: (j['reason'] ?? '').toString(),
      attachmentUrl: j['attachmentUrl']?.toString(),
      status: (j['status'] ?? 'pending').toString(),
      reviewedBy: reviewer is Map ? reviewer['name']?.toString() : null,
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }

  String get dateLabel {
    if (DateUtils.isSameDay(start, end)) return DateFormat('dd-MM-yyyy').format(start);
    return '${DateFormat('dd-MM-yyyy').format(start)} → ${DateFormat('dd-MM-yyyy').format(end)}';
  }

  String get daysLabel {
    final d = days == days.roundToDouble() ? days.toInt().toString() : days.toString();
    return '$d ${days == 1 ? 'Day' : 'Days'}';
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────

class LeaveAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  const LeaveAvatar({super.key, required this.name, this.photoUrl, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1 ? parts.first[0] : '${parts.first[0]}${parts.last[0]}').toUpperCase();
    final url = photoUrl;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.brand.withValues(alpha: 0.18),
      foregroundImage: url != null && url.startsWith('http') ? CachedNetworkImageProvider(url) : null,
      child: Text(initials,
          style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

class LeaveStatusBadge extends StatelessWidget {
  final String status;
  const LeaveStatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = leaveStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(leaveStatuses[status] ?? status,
            style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Bottom-sheet option list used by the leave dropdowns.
Future<T?> showLeavePicker<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T? current,
  required String Function(T) label,
  String? Function(T)? subtitle,
  Widget Function(T)? leading,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.dark2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(title, style: const TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              for (final v in values)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, v),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: v == current ? AppColors.brand.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: v == current ? AppColors.brand.withValues(alpha: 0.5) : Colors.transparent),
                    ),
                    child: Row(children: [
                      if (leading != null) ...[leading(v), const SizedBox(width: 12)],
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label(v),
                              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          if ((subtitle?.call(v) ?? '').isNotEmpty)
                            Text(subtitle!(v)!, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                        ]),
                      ),
                      if (v == current) const Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 20),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ]),
    ),
  );
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 14),
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
      );
}

/// Tappable field that looks like a dropdown (dark input with chevron).
class LeaveSelectBox extends StatelessWidget {
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final Widget? leading;
  final IconData trailingIcon;
  final BorderRadius? borderRadius;
  const LeaveSelectBox({
    super.key,
    required this.value,
    this.placeholder = '--',
    this.onTap,
    this.leading,
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(12);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: radius,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Text(
              value ?? placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value == null ? AppColors.muted : AppColors.white,
                fontSize: 15,
                fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
          Icon(trailingIcon, color: AppColors.silver, size: 22),
        ]),
      ),
    );
  }
}
