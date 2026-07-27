import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/staff_controller.dart';

/// Shared attendance rules for check-out and logout.
class AttendanceGates {
  /// Open assigned jobs that still need a submitted report.
  static Future<Map<String, dynamic>?> firstOpenJob(WidgetRef ref) async {
    final jobs = await ref
        .read(staffControllerProvider.notifier)
        .loadMyJobs(status: 'pending,in_progress');
    if (jobs.isEmpty) return null;
    return jobs.first;
  }

  static String _jobId(Map<String, dynamic> job) =>
      job['_id']?.toString() ?? job['id']?.toString() ?? '';

  static String _jobTitle(Map<String, dynamic> job) =>
      job['title']?.toString() ?? 'Assigned job';

  static void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppColors.brand,
        duration: const Duration(seconds: 3),
      ));
  }

  static Future<void> goSubmitOpenJob(
    BuildContext context,
    Map<String, dynamic> job, {
    String message = 'Complete the job first by submitting a report.',
  }) async {
    final id = _jobId(job);
    final title = Uri.encodeComponent(_jobTitle(job));
    _snack(context, message);
    if (!context.mounted) return;
    if (id.isEmpty) {
      context.push('/staff/jobs');
      return;
    }
    context.push('/staff/submit?jobId=$id&jobTitle=$title');
  }

  /// Called before opening the checkout screen.
  /// Returns `true` if checkout may proceed.
  static Future<bool> allowCheckOut(BuildContext context, WidgetRef ref) async {
    final openJob = await firstOpenJob(ref);
    if (!context.mounted) return false;
    if (openJob != null) {
      await goSubmitOpenJob(context, openJob);
      return false;
    }
    return true;
  }

  /// Called when staff taps Logout.
  /// Returns `true` if logout may proceed.
  static Future<bool> allowLogout(BuildContext context, WidgetRef ref) async {
    await ref.read(staffControllerProvider.notifier).loadCheckInStatus();
    if (!context.mounted) return false;

    final checkedIn = ref.read(staffControllerProvider).isCheckedIn;
    if (!checkedIn) return true;

    final openJob = await firstOpenJob(ref);
    if (!context.mounted) return false;

    if (openJob != null) {
      await goSubmitOpenJob(
        context,
        openJob,
        message: 'Complete the job first before logging out.',
      );
      return false;
    }

    _snack(context, 'Logout is restricted while checked in. Please check out first.');
    if (!context.mounted) return false;
    context.push('/staff/checkout');
    return false;
  }
}
