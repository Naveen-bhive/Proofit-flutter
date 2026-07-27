import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../network/api_service.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/staff/controllers/staff_controller.dart';
import '../../shared/services/socket_service.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/screens/sign_in_screen.dart';
import '../../features/auth/screens/sign_up_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/owner/screens/staff_attendance_screen.dart';
import '../../features/auth/screens/invite_screen.dart';
import '../../features/auth/screens/owner_setup_screen.dart';
import '../../features/staff/screens/staff_shell.dart';
import '../../features/staff/screens/submit_report_screen.dart';
import '../../features/staff/screens/multi_photo_report_screen.dart';
import '../../features/staff/screens/staff_history_screen.dart';
import '../../features/staff/screens/check_in_screen.dart';
import '../../features/staff/screens/check_out_screen.dart';
import '../../features/staff/screens/checkin_history_screen.dart';
import '../../features/staff/screens/staff_report_detail_screen.dart';
import '../../features/staff/screens/photo_viewer_screen.dart';
import '../../features/staff/screens/draft_detail_screen.dart';
import '../../features/staff/screens/staff_notifications_screen.dart';
import '../../features/owner/screens/owner_shell.dart';
import '../../features/owner/screens/owner_dashboard_screen.dart';
import '../../features/owner/screens/report_detail_screen.dart';
import '../../features/owner/screens/owner_photo_viewer_screen.dart';
import '../../features/owner/screens/staff_management_screen.dart';
import '../../features/owner/screens/staff_profile_screen.dart' as owner_staff;
import '../../features/owner/screens/owner_history_screen.dart';
import '../../features/owner/screens/live_map_screen.dart';
import '../../features/owner/screens/flagged_reports_screen.dart';
import '../../features/owner/screens/search_reports_screen.dart';
import '../../features/owner/screens/owner_notifications_screen.dart';
import '../../features/owner/screens/owner_settings_screen.dart';
import '../../features/owner/screens/subscription_screen.dart';
import '../../features/owner/screens/payment_history_screen.dart';
import '../../features/owner/screens/jobs_screen.dart';
import '../../features/owner/screens/customers_screen.dart';
import '../../features/owner/screens/working_hours_screen.dart';
import '../../features/staff/screens/staff_jobs_screen.dart';
import '../../features/staff/screens/staff_profile_screen.dart';
import '../../features/owner/screens/pdf_export_screen.dart';
import '../../shared/services/deep_link_utils.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final token = DeepLinkUtils.inviteTokenFromUri(state.uri);
      if (token != null && state.uri.path != '/invite/$token') {
        return '/invite/$token';
      }
      return null;
    },
    errorBuilder: (_, __) => const Scaffold(
      body: Center(child: Text('Page not found', style: TextStyle(color: Colors.white)))),
    routes: [
      GoRoute(path: '/',       builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/signin', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, s) => ResetPasswordScreen(
        initialEmail: s.uri.queryParameters['email'] != null
            ? Uri.decodeComponent(s.uri.queryParameters['email']!)
            : null,
      )),
      GoRoute(path: '/change-password', builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(path: '/otp',    redirect: (_, __) => '/signin'),
      GoRoute(path: '/invite/:token', builder: (_, s) => InviteScreen(token: s.pathParameters['token'] ?? '')),
      GoRoute(path: '/owner-setup',   builder: (_, __) => const OwnerSetupScreen()),

      // Staff shell with bottom nav
      GoRoute(path: '/staff', builder: (_, __) => const StaffShell()),
      GoRoute(path: '/staff/submit', builder: (_, s) => SubmitReportScreen(
        reportId: s.uri.queryParameters['reportId'],
        jobId:    s.uri.queryParameters['jobId'],
        jobTitle: s.uri.queryParameters['jobTitle'] != null
            ? Uri.decodeComponent(s.uri.queryParameters['jobTitle']!) : null)),
      GoRoute(path: '/staff/multi-photo',  builder: (_, __) => const MultiPhotoReportScreen()),
      GoRoute(path: '/staff/history', builder: (_, s) => StaffHistoryScreen(
        initialFilter: s.uri.queryParameters['filter'])),
      GoRoute(path: '/staff/checkin',      builder: (_, __) => const CheckInScreen()),
      GoRoute(path: '/staff/checkout',     builder: (_, __) => const CheckOutScreen()),
      GoRoute(path: '/staff/checkin-history', builder: (_, __) => const CheckinHistoryScreen()),
      GoRoute(path: '/staff/report/:id',   builder: (_, s) => StaffReportDetailScreen(reportId: s.pathParameters['id'] ?? '')),
      GoRoute(path: '/staff/draft/:id',    builder: (_, s) => DraftDetailScreen(reportId: s.pathParameters['id'] ?? '')),
      GoRoute(path: '/staff/photo-viewer', builder: (_, s) => PhotoViewerScreen(
        beforeUrl: s.uri.queryParameters['before'] ?? '',
        afterUrl:  s.uri.queryParameters['after'])),
      GoRoute(path: '/staff/notifications', builder: (_, __) => const StaffNotificationsScreen()),
      GoRoute(path: '/staff/jobs',          builder: (_, __) => const StaffJobsScreen()),
      GoRoute(path: '/staff/profile',       builder: (_, __) => const StaffProfileScreen()),

      // Owner shell with bottom nav
      GoRoute(path: '/owner', builder: (_, __) => const OwnerShell()),
      GoRoute(path: '/owner/report/:id',    builder: (_, s) => ReportDetailScreen(reportId: s.pathParameters['id'] ?? '')),
      GoRoute(path: '/owner/photo-viewer',  builder: (_, s) {
        final before = s.uri.queryParameters['before'];
        final after  = s.uri.queryParameters['after'];
        final fileId = s.uri.queryParameters['fileId'];
        final label  = s.uri.queryParameters['label'];
        return OwnerPhotoViewerScreen(
          fileId: fileId ?? before ?? after ?? '',
          label: label ?? (before != null ? 'Before' : 'After'),
          reportId: s.uri.queryParameters['reportId'],
          photoSlot: s.uri.queryParameters['slot'],
        );
      }),
      GoRoute(path: '/owner/staff',         builder: (_, __) => const StaffManagementScreen()),
      GoRoute(path: '/owner/staff/:id',     builder: (_, s) => owner_staff.StaffProfileScreen(staffId: s.pathParameters['id'] ?? '')),
      GoRoute(path: '/owner/history', builder: (_, s) => OwnerHistoryScreen(
        initialStatus: s.uri.queryParameters['status'])),
      GoRoute(path: '/owner/map',           builder: (_, __) => const LiveMapScreen()),
      GoRoute(path: '/owner/flagged',       builder: (_, __) => const FlaggedReportsScreen()),
      GoRoute(path: '/owner/search',        builder: (_, __) => const SearchReportsScreen()),
      GoRoute(path: '/owner/notifications', builder: (_, __) => const OwnerNotificationsScreen()),
      GoRoute(path: '/owner/settings',      builder: (_, __) => const OwnerSettingsScreen()),
      GoRoute(path: '/owner/subscription',  builder: (_, __) => const SubscriptionScreen()),
      GoRoute(path: '/owner/payment-history', builder: (_, __) => const PaymentHistoryScreen()),
      GoRoute(path: '/owner/customers', builder: (_, __) => const CustomersScreen()),
      GoRoute(path: '/owner/jobs',          builder: (_, __) => const JobsScreen()),
      GoRoute(path: '/owner/working-hours', builder: (_, __) => const WorkingHoursScreen()),
      GoRoute(path: '/owner/staff-attendance', builder: (_, s) => StaffAttendanceScreen(
        staffId: s.pathParameters['staffId'],
        staffName: s.uri.queryParameters['name'] != null
            ? Uri.decodeComponent(s.uri.queryParameters['name']!) : null)),
      GoRoute(path: '/owner/staff-attendance/:staffId', builder: (_, s) => StaffAttendanceScreen(
        staffId: s.pathParameters['staffId'],
        staffName: s.uri.queryParameters['name'] != null
            ? Uri.decodeComponent(s.uri.queryParameters['name']!) : null)),
      GoRoute(path: '/owner/export-pdf/:id',builder: (_, s) => PdfExportScreen(reportId: s.pathParameters['id'] ?? '')),
    ],
  );

  onUnauthorized = () {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      SocketService.disconnect();
      await ref.read(authControllerProvider.notifier).logout();
      ref.invalidate(staffControllerProvider);
      router.go('/signin');
    });
  };

  return router;
});