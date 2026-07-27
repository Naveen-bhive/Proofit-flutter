import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../shared/models/report_model.dart';
import '../../../shared/models/customer_model.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/models/org_model.dart';

class OwnerState {
  final bool isLoading;
  final String orgName;
  final String plan;
  final int totalReportsToday;
  final int activeStaffCount;
  final int totalStaff;
  final int pendingDraftCount;
  final List<Map<String, dynamic>> staffStatuses;
  final List<ReportModel> recentReports;
  final List<ReportModel> allReports;
  final List<ReportModel> flaggedReports;
  final List<ReportModel> searchResults;
  final List<Map<String, dynamic>> staffList;
  final List<Map<String, dynamic>> staffLocations;
  final List<Map<String, dynamic>> ownerNotifications;
  final List<Map<String, dynamic>> paymentHistory;
  final ReportModel? selectedReport;
  final Map<String, dynamic>? selectedStaffProfile;
  final List<ReportModel> staffReports;
  final List<CustomerModel> customers;
  final bool canAddCustomer;
  final int customerLimit;
  final Map<String, dynamic>? reportPagination;
  final DateTime? subscriptionExpiresAt;
  final int? subscriptionDaysRemaining;
  final List<Map<String, dynamic>> availablePlans;
  final String? ownerEmail;
  final String? ownerPhotoUrl;

  const OwnerState({
    this.isLoading = false,
    this.orgName = '',
    this.plan = 'free',
    this.totalReportsToday = 0,
    this.activeStaffCount = 0,
    this.totalStaff = 0,
    this.pendingDraftCount = 0,
    this.staffStatuses = const [],
    this.recentReports = const [],
    this.allReports = const [],
    this.flaggedReports = const [],
    this.searchResults = const [],
    this.staffList = const [],
    this.staffLocations = const [],
    this.ownerNotifications = const [],
    this.paymentHistory = const [],
    this.selectedReport,
    this.selectedStaffProfile,
    this.staffReports = const [],
    this.customers = const [],
    this.canAddCustomer = true,
    this.customerLimit = 3,
    this.reportPagination,
    this.subscriptionExpiresAt,
    this.subscriptionDaysRemaining,
    this.availablePlans = const [],
    this.ownerEmail,
    this.ownerPhotoUrl,
  });

  OwnerState copyWith({
    bool? isLoading, String? orgName, String? plan,
    int? totalReportsToday, int? activeStaffCount, int? totalStaff, int? pendingDraftCount,
    List<Map<String, dynamic>>? staffStatuses,
    List<ReportModel>? recentReports, List<ReportModel>? allReports,
    List<ReportModel>? flaggedReports, List<ReportModel>? searchResults,
    List<Map<String, dynamic>>? staffList, List<Map<String, dynamic>>? staffLocations,
    List<Map<String, dynamic>>? ownerNotifications, List<Map<String, dynamic>>? paymentHistory,
    ReportModel? selectedReport, Map<String, dynamic>? selectedStaffProfile,
    List<ReportModel>? staffReports,
    List<CustomerModel>? customers,
    bool? canAddCustomer,
    int? customerLimit,
    Map<String, dynamic>? reportPagination,
    DateTime? subscriptionExpiresAt, int? subscriptionDaysRemaining,
    List<Map<String, dynamic>>? availablePlans,
    String? ownerEmail,
    String? ownerPhotoUrl,
  }) => OwnerState(
    isLoading: isLoading ?? this.isLoading,
    orgName: orgName ?? this.orgName,
    plan: plan ?? this.plan,
    totalReportsToday: totalReportsToday ?? this.totalReportsToday,
    activeStaffCount: activeStaffCount ?? this.activeStaffCount,
    totalStaff: totalStaff ?? this.totalStaff,
    pendingDraftCount: pendingDraftCount ?? this.pendingDraftCount,
    staffStatuses: staffStatuses ?? this.staffStatuses,
    recentReports: recentReports ?? this.recentReports,
    allReports: allReports ?? this.allReports,
    flaggedReports: flaggedReports ?? this.flaggedReports,
    searchResults: searchResults ?? this.searchResults,
    staffList: staffList ?? this.staffList,
    staffLocations: staffLocations ?? this.staffLocations,
    ownerNotifications: ownerNotifications ?? this.ownerNotifications,
    paymentHistory: paymentHistory ?? this.paymentHistory,
    selectedReport: selectedReport ?? this.selectedReport,
    selectedStaffProfile: selectedStaffProfile ?? this.selectedStaffProfile,
    staffReports:    staffReports    ?? this.staffReports,
    customers:       customers       ?? this.customers,
    canAddCustomer:  canAddCustomer  ?? this.canAddCustomer,
    customerLimit:   customerLimit   ?? this.customerLimit,
    reportPagination: reportPagination ?? this.reportPagination,
    subscriptionExpiresAt: subscriptionExpiresAt ?? this.subscriptionExpiresAt,
    subscriptionDaysRemaining: subscriptionDaysRemaining ?? this.subscriptionDaysRemaining,
    availablePlans: availablePlans ?? this.availablePlans,
    ownerEmail: ownerEmail ?? this.ownerEmail,
    ownerPhotoUrl: ownerPhotoUrl ?? this.ownerPhotoUrl,
  );
}

final ownerControllerProvider = StateNotifierProvider<OwnerController, OwnerState>(
  (ref) => OwnerController(ref.read(apiServiceProvider)),
);

class OwnerController extends StateNotifier<OwnerState> {
  final ApiService _api;
  OwnerController(this._api) : super(const OwnerState()) { _initOrg(); }

  Future<void> _initOrg() async {
    final org  = await AuthStorage.getOrg();
    final user = await AuthStorage.getUser();
    if (org != null) {
      state = state.copyWith(
        orgName: org.name,
        plan: org.plan,
        ownerEmail: user?.email,
        ownerPhotoUrl: user?.photoUrl,
      );
    }
    loadAvailablePlans();
  }

  // ── Subscription ─────────────────────────────────────────────

  Future<({Map<String, dynamic>? data, String? error})> createOrder(String plan) async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await AuthStorage.getUser();
      final res  = await _api.post('/subscription/create-order', data: {'plan': plan});
      state = state.copyWith(isLoading: false);
      if (res.data['success'] == true) {
        final payload = Map<String, dynamic>.from(res.data['data'] as Map);
        payload['ownerPhone'] = user?.phone ?? '';
        return (data: payload, error: null);
      }
      return (data: null, error: res.data['message'] as String? ?? 'Could not start payment');
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false);
      return (data: null, error: friendlyErrorMessage(e, fallback: 'Could not start payment'));
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return (data: null, error: friendlyErrorMessage(e, fallback: 'Could not start payment'));
    }
  }

  Future<bool> verifyPayment({
    required String orderId, required String paymentId,
    required String signature, required String plan,
  }) async {
    try {
      final res = await _api.post('/subscription/verify-payment', data: {
        'razorpay_order_id':   orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature':  signature,
        'plan':                plan,
      });
      if (res.data['success'] == true) {
        state = state.copyWith(plan: plan);
        return true;
      }
      return false;
    } catch (_) { return false; }
  }

  Future<void> loadSubscriptionStatus() async {
    try {
      final res = await _api.get('/subscription/status');
      if (res.data['success'] == true) {
        final d = res.data['data'];
        state = state.copyWith(
          plan: d['plan'] ?? 'free',
          subscriptionExpiresAt: d['expiresAt'] != null ? DateTime.parse(d['expiresAt']) : null,
          subscriptionDaysRemaining: d['daysRemaining'],
        );
      }
    } catch (_) {}
  }

  // Fetches live plans from the backend (managed via the admin panel).
  // Replaces the old hardcoded plan list — any plan created/edited in
  // admin shows up here without an app update.
  Future<void> loadAvailablePlans() async {
    try {
      final res = await _api.get('/plans/active');
      if (res.data['success'] == true) {
        state = state.copyWith(
          availablePlans: List<Map<String, dynamic>>.from(res.data['data'] ?? []),
        );
      }
    } catch (_) {}
  }

  // Looks up a feature flag for the org's current plan from the live
  // plans list, instead of hardcoding plan-name comparisons (e.g.
  // `plan == 'pro'`) which silently break for any new plan slug.
  bool hasFeature(String flagKey) {
    if (state.plan == 'free') return false; // free tier has no premium features
    final currentPlan = state.availablePlans.firstWhere(
      (p) => p['slug'] == state.plan,
      orElse: () => const {},
    );
    final flags = currentPlan['flags'] as Map<String, dynamic>?;
    return flags?[flagKey] == true;
  }

  Future<void> loadPaymentHistory() async {
    try {
      final res = await _api.get('/subscription/history');
      if (res.data['success'] == true) {
        state = state.copyWith(paymentHistory: List<Map<String, dynamic>>.from(res.data['data'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> scheduleDowngrade(String plan) async {
    try {
      final res = await _api.post('/subscription/downgrade', data: {'plan': plan});
      if (res.data['success'] == true) {
        // Show scheduled — don't change current plan yet
      }
    } catch (_) {}
  }

  // ── Dashboard ─────────────────────────────────────────────────

  Future<bool> loadDashboard() async {
    try {
      final res = await _api.get('/owner/dashboard');
      if (res.data['success'] == true) {
        final d = res.data['data'] as Map<String, dynamic>? ?? {};
        final recent = <ReportModel>[];
        for (final raw in (d['recentReports'] as List? ?? [])) {
          if (raw is! Map) continue;
          try {
            recent.add(ReportModel.fromJson(Map<String, dynamic>.from(raw)));
          } catch (_) {}
        }
        final staffStatuses = <Map<String, dynamic>>[];
        for (final raw in (d['staffStatuses'] as List? ?? [])) {
          if (raw is Map) {
            staffStatuses.add(Map<String, dynamic>.from(raw));
          }
        }
        state = state.copyWith(
          totalReportsToday: _asInt(d['totalReportsToday']),
          activeStaffCount:  _asInt(d['activeStaffCount']),
          totalStaff:        _asInt(d['totalStaff']),
          pendingDraftCount: _asInt(d['pendingDraftCount']),
          staffStatuses:     staffStatuses,
          recentReports:     recent,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> loadStaff() async {
    try {
      final res = await _api.get('/staff');
      if (res.data['success'] == true) {
        state = state.copyWith(staffList: List<Map<String, dynamic>>.from(res.data['data'] ?? []));
      }
    } catch (_) {}
  }

  Future<({bool ok, String message})> addStaff({
    required String name,
    required String phone,
    required String email,
  }) async {
    try {
      final res = await _api.post('/staff', data: {
        'name': name,
        'phone': phone,
        'email': email,
      });
      await loadStaff();
      final msg = res.data['message']?.toString();
      if (res.data['success'] != true) {
        return (ok: false, message: msg ?? 'Could not add staff');
      }
      final data = res.data['data'] as Map<String, dynamic>?;
      final emailSent = data?['emailSent'] == true;
      final emailError = data?['emailError']?.toString();
      if (!emailSent) {
        return (
          ok: false,
          message: emailError != null && emailError.isNotEmpty
              ? friendlyErrorMessage(emailError, fallback: 'Invitation email could not be sent. Please try again.')
              : (msg ?? 'Invitation email could not be sent. Please try again.'),
        );
      }
      return (ok: true, message: msg ?? 'Invitation sent by email');
    } catch (e) {
      return (ok: false, message: friendlyErrorMessage(e, fallback: 'Could not add staff'));
    }
  }

  Future<void> removeStaff(String staffId) async {
    try { await _api.delete('/staff/$staffId'); await loadStaff(); } catch (_) {}
  }

  Future<void> setStaffTarget(String staffId, int target) async {
    try { await _api.put('/staff/$staffId/target', data: {'target': target}); await loadStaffProfile(staffId); } catch (_) {}
  }

  Future<void> loadStaffProfile(String staffId) async {
    try {
      final res = await _api.get('/staff/$staffId/profile');
      if (res.data['success'] == true) {
        final rRes = await _api.get('/reports', params: {'staffId': staffId, 'filter': 'month'});
        state = state.copyWith(
          selectedStaffProfile: res.data['data'],
          staffReports: rRes.data['success'] == true
              ? ((rRes.data['data'] is List ? rRes.data['data'] : rRes.data['data']['reports']) as List)
                  .map((r) => ReportModel.fromJson(r)).toList()
              : [],
        );
      }
    } catch (_) {}
  }

  Future<void> loadReportDetail(String reportId) async {
    try {
      final res = await _api.get('/reports/$reportId');
      if (res.data['success'] == true) state = state.copyWith(selectedReport: ReportModel.fromJson(res.data['data']));
    } catch (_) {}
  }

  Future<void> loadFlaggedReports() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _api.get('/reports', params: {'flagged': 'true'});
      if (res.data['success'] == true) {
        final list = (res.data['data']['reports'] as List? ?? []);
        state = state.copyWith(isLoading: false, flaggedReports: list.map((r) => ReportModel.fromJson(r)).toList());
      }
    } catch (_) { state = state.copyWith(isLoading: false); }
  }

  Future<void> searchReports(String query) async {
    try {
      final res = await _api.get('/reports/search', params: {'q': query});
      if (res.data['success'] == true) {
        final list = (res.data['data']['reports'] as List? ?? []);
        state = state.copyWith(searchResults: list.map((r) => ReportModel.fromJson(r)).toList());
      }
    } catch (_) {}
  }

  Future<void> loadLiveLocations() async {
    try {
      final res = await _api.get('/location/live');
      if (res.data['success'] == true) state = state.copyWith(staffLocations: List<Map<String, dynamic>>.from(res.data['data'] ?? []));
    } catch (_) {}
  }

  Future<void> exportReport(String format) async {
    try { await _api.post('/reports/export', data: {'format': format}); } catch (_) {}
  }

  Future<void> loadOwnerNotifications() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _api.get('/notifications/my');
      if (res.data['success'] == true) {
        state = state.copyWith(isLoading: false, ownerNotifications: List<Map<String, dynamic>>.from(res.data['data']?['notifications'] ?? []));
      }
    } catch (_) { state = state.copyWith(isLoading: false); }
  }

  Future<void> markOwnerNotificationsRead() async {
    try {
      await _api.post('/notifications/read-all');
      final updated = state.ownerNotifications.map((n) => {...n, 'isRead': true}).toList();
      state = state.copyWith(ownerNotifications: updated);
    } catch (_) {}
  }

  Future<void> broadcastNotification(String title, String body) async {
    try { await _api.post('/notifications/broadcast', data: {'title': title, 'body': body}); } catch (_) {}
  }

  Future<void> updateCompanyName(String name) async {
    try {
      final res = await _api.put('/owner/company-name', data: {'name': name});
      if (res.data['success'] == true) {
        final orgJson = res.data['data']?['org'];
        if (orgJson is Map) {
          final org = OrgModel.fromJson(Map<String, dynamic>.from(orgJson));
          await AuthStorage.updateOrg(org);
          state = state.copyWith(orgName: org.name);
        } else {
          await applyOrgName(name);
        }
      }
    } catch (_) {}
  }

  Future<void> applyOrgName(String name) async {
    final org = await AuthStorage.getOrg();
    if (org != null) await AuthStorage.updateOrg(org.copyWith(name: name));
    state = state.copyWith(orgName: name);
  }

  Future<void> syncOrgFromServer() async {
    try {
      final res = await _api.get('/auth/org');
      if (res.data['success'] == true && res.data['data'] != null) {
        final org = OrgModel.fromJson(Map<String, dynamic>.from(res.data['data']));
        await AuthStorage.updateOrg(org);
        state = state.copyWith(orgName: org.name, plan: org.plan);
      }
    } catch (_) {}
  }

  // FIX #10 — Get unread notification count for badge
  Future<int> getUnreadNotifCount() async {
    try {
      final res = await _api.get('/notifications/my');
      if (res.data['success'] == true) {
        return res.data['data']?['unreadCount'] ?? 0;
      }
      return 0;
    } catch (_) { return 0; }
  }


  // FIX 3+4: load with pagination + staff filter + date range
  Future<void> loadAllReports({String? filter, String? staffId, String? from, String? to, int page = 1, String status = 'submitted'}) async {
    try {
      final params = <String,dynamic>{'page': page, 'limit': 50, 'status': status};
      if (filter != null && filter.isNotEmpty) params['filter'] = filter;
      if (staffId != null) params['staffId'] = staffId;
      if (from != null)    params['from'] = from;
      if (to != null)      params['to']   = to;
      final res = await _api.get('/reports', params: params);
      if (res.data['success'] == true) {
        final newReports = (res.data['data']['reports'] as List).map((r) => ReportModel.fromJson(r)).toList();
        state = state.copyWith(
          allReports: page == 1 ? newReports : [...state.allReports, ...newReports],
          reportPagination: Map<String,dynamic>.from(res.data['data']['pagination'] ?? {}),
        );
      }
    } catch (_) {}
  }

  Future<void> loadMoreReports({String? filter, String? staffId, String? from, String? to, required int page, String status = 'submitted'}) async {
    await loadAllReports(filter: filter, staffId: staffId, from: from, to: to, page: page, status: status);
  }


  // ── Customer management ───────────────────────────
  Future<void> loadCustomers() async {
    try {
      final res = await _api.get('/customers');
      if (res.data['success'] == true) {
        final d = res.data['data'];
        state = state.copyWith(
          customers:      (d['customers'] as List).map((c) => CustomerModel.fromJson(c)).toList(),
          canAddCustomer: d['canAdd'] == true || (d['limit'] == -1) || ((d['total'] ?? 0) < (d['limit'] ?? 3)),
          customerLimit:  d['limit'] ?? 3,
        );
      }
    } catch (_) {}
  }

  Future<String?> addCustomer(String name, String phone, String address, String notes) async {
    try {
      final res = await _api.post('/customers', data: {'name': name, 'phone': phone, 'address': address, 'notes': notes});
      if (res.data['success'] == true) {
        await loadCustomers();
        return res.data['data']?['_id']?.toString();
      }
      return null;
    } catch (_) { return null; }
  }

  Future<void> editCustomer(String id, String name, String phone, String address, String notes) async {
    try {
      await _api.put('/customers/$id', data: {'name': name, 'phone': phone, 'address': address, 'notes': notes});
      await loadCustomers();
    } catch (_) {}
  }

  Future<void> deleteCustomer(String id) async {
    try { await _api.delete('/customers/$id'); await loadCustomers(); } catch (_) {}
  }

}