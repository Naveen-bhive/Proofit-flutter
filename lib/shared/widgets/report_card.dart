import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../models/report_model.dart';

class ReportCard extends StatelessWidget {
  final ReportModel report;
  final VoidCallback? onTap;
  final bool showStaffName;

  const ReportCard({super.key, required this.report, this.onTap, this.showStaffName = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: report.isFlagged ? AppColors.red.withValues(alpha: 0.5) : AppColors.border,
          ),
        ),
        child: Row(children: [
          // Before photo thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: report.beforeMedia?.url != null
                ? Image.network(report.beforeMedia!.url!, width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder())
                : _placeholder(),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showStaffName)
              Text(report.staffName, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
            Text(report.jobTitle,
              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 15),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: AppColors.muted),
              const SizedBox(width: 3),
              Expanded(child: Text(
                report.location?.address ?? 'Location not available',
                style: const TextStyle(color: AppColors.silver, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
            ]),
          ])),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _statusChip(),
            const SizedBox(height: 6),
            if (report.submittedAt != null)
              Text(formatApiTime(report.submittedAt),
                style: const TextStyle(color: AppColors.muted, fontSize: 11))
            else if (report.createdAt != null)
              Text(formatApiDate(report.createdAt, pattern: 'd MMM'),
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 56, height: 56, color: AppColors.dark4,
    child: const Icon(Icons.image_outlined, color: AppColors.muted, size: 24),
  );

  Widget _statusChip() {
    final (color, label) = report.isFlagged
        ? (AppColors.red, 'âš  Flagged')
        : report.isSubmitted
            ? (AppColors.green, 'Sent')
            : (AppColors.yellow, 'Draft');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}