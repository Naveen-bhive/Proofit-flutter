import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../controllers/owner_controller.dart';
import '../widgets/storage_addons_section.dart';

import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/services/meta_app_events_service.dart';
import '../../../shared/services/revenue_cat_service.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Razorpay? _razorpay;
  String? _pendingPlanSlug;
  String? _pendingPlanName;
  double? _pendingPlanAmount;
  bool _loading = false;
  bool _plansLoading = true;

  static const List<Color> _cardColors = [
    AppColors.blue,
    AppColors.brand,
    Color(0xFF8B5CF6)
  ];

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleWallet);
    Future.microtask(() async {
      await ref.read(ownerControllerProvider.notifier).loadSubscriptionStatus();
      await ref.read(ownerControllerProvider.notifier).loadAvailablePlans();
      if (mounted) setState(() => _plansLoading = false);
    });
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  int _planTier(Map<String, dynamic> plan) =>
      (plan['sortOrder'] as num?)?.toInt() ?? 0;

  Map<String, dynamic>? _currentPlan(
      List<Map<String, dynamic>> plans, String slug) {
    if (slug == 'free') return null;
    for (final p in plans) {
      if (p['slug'] == slug) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> _upgradePlans(
      List<Map<String, dynamic>> plans, int currentTier) {
    return plans.where((p) => _planTier(p) > currentTier).toList()
      ..sort((a, b) => _planTier(a).compareTo(_planTier(b)));
  }

  String _priceLabel(dynamic rawPrice, dynamic rawDurationDays) {
    final price =
        rawPrice is num ? rawPrice.toInt() : int.tryParse('$rawPrice') ?? 0;
    final durationDays = rawDurationDays is num
        ? rawDurationDays.toInt()
        : int.tryParse('$rawDurationDays') ?? 30;
    if (price <= 0 || durationDays <= 0) return 'Custom';
    return '\u20B9$price${durationDays == 30 ? '/mo' : '/${durationDays}d'}';
  }

  double _planAmount(Map<String, dynamic> plan) {
    final rawPrice = plan['price'];
    if (rawPrice is num) return rawPrice.toDouble();
    return double.tryParse('$rawPrice') ?? 0;
  }

  Future<void> _startPayment(Map<String, dynamic> plan) async {
    final planSlug = plan['slug'] as String? ?? '';
    final planName = plan['name'] as String? ?? 'Plan';
    if (planSlug.toLowerCase() == 'enterprise' ||
        planName.toLowerCase().contains('enterprise')) {
      context.push('/owner/enterprise-request');
      return;
    }
    final revenueCatProductId = plan['revenueCatProductId'] as String?;

    // iOS must go through RevenueCat/App Store — Apple requires IAP for
    // digital subscriptions. Android keeps the existing Razorpay flow.
    if (Platform.isIOS &&
        revenueCatProductId != null &&
        revenueCatProductId.isNotEmpty) {
      await _startIosPurchase(
        planSlug,
        planName,
        revenueCatProductId,
        _planAmount(plan),
      );
      return;
    }

    setState(() {
      _pendingPlanSlug = planSlug;
      _pendingPlanName = planName;
      _pendingPlanAmount = _planAmount(plan);
      _loading = true;
    });
    try {
      final result = await ref
          .read(ownerControllerProvider.notifier)
          .createOrder(planSlug);
      final data = result.data;
      debugPrint('Razorpay create-order: data=$data error=${result.error}');
      if (data == null) {
        throw Exception(result.error ?? 'Could not start payment');
      }

      final user = await AuthStorage.getUser();
      await MetaAppEventsService.logCheckoutStarted(
        planSlug: planSlug,
        planName: planName,
        amount: _pendingPlanAmount ?? 0,
      );

      _razorpay!.open({
        'key': data['key'],
        'amount': data['amount'] is int
            ? data['amount']
            : int.parse('${data['amount']}'),
        'currency': 'INR',
        'order_id': data['orderId'],
        'name': 'ProofIt',
        'description': '$planName Plan',
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
        'theme': {'color': '#2F80ED'},
      });
    } catch (e, st) {
      debugPrint('Razorpay start failed: $e\n$st');
      if (mounted) {
        showErrorSnackBar(context, e,
            fallback: 'Could not start payment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startIosPurchase(
    String planSlug,
    String planName,
    String revenueCatProductId,
    double amount,
  ) async {
    setState(() {
      _pendingPlanSlug = planSlug;
      _pendingPlanName = planName;
      _pendingPlanAmount = amount;
      _loading = true;
    });
    try {
      await MetaAppEventsService.logCheckoutStarted(
        planSlug: planSlug,
        planName: planName,
        amount: amount,
      );
      final product = await RevenueCatService.getProduct(revenueCatProductId);
      if (product == null) {
        throw Exception('This plan is not available for purchase right now.');
      }

      await RevenueCatService.purchase(product);

      // Backend re-verifies against RevenueCat's own servers before activating —
      // this call is what actually flips the org's plan, not the purchase itself.
      final ok =
          await ref.read(ownerControllerProvider.notifier).syncIapPurchase();
      await ref.read(ownerControllerProvider.notifier).loadSubscriptionStatus();
      final activatedPlan = ref.read(ownerControllerProvider).plan;
      if (!ok && activatedPlan != planSlug) {
        throw Exception('Verification failed');
      }
      await ref.read(ownerControllerProvider.notifier).loadAvailablePlans();
      await MetaAppEventsService.logSubscriptionPurchased(
        planSlug: planSlug,
        planName: planName,
        amount: _pendingPlanAmount ?? 0,
        orderId: revenueCatProductId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Plan activated!'),
            backgroundColor: AppColors.green));
        context.pop();
      }
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      debugPrint(
          'RevenueCat purchase failed: code=${e.code} rcErrorCode=$errorCode message=${e.message} details=${e.details}');
      final cancelled = errorCode == PurchasesErrorCode.purchaseCancelledError;
      if (!cancelled && mounted) {
        showErrorSnackBar(context, e,
            fallback: 'Could not complete purchase. Please try again.');
      }
    } catch (e) {
      debugPrint('IAP purchase/verification failed: $e');
      if (mounted) {
        showErrorSnackBar(context, e,
            fallback: 'Payment verification failed. Please contact support.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleSuccess(PaymentSuccessResponse r) async {
    try {
      final ok = await ref.read(ownerControllerProvider.notifier).verifyPayment(
            orderId: r.orderId ?? '',
            paymentId: r.paymentId ?? '',
            signature: r.signature ?? '',
          );
      await ref.read(ownerControllerProvider.notifier).loadSubscriptionStatus();
      final activatedPlan = ref.read(ownerControllerProvider).plan;
      final expectedPlan = _pendingPlanSlug;
      if (!ok && (expectedPlan == null || activatedPlan != expectedPlan)) {
        throw Exception('Verification failed');
      }
      await ref.read(ownerControllerProvider.notifier).loadAvailablePlans();
      await MetaAppEventsService.logSubscriptionPurchased(
        planSlug: activatedPlan,
        planName: _pendingPlanName ?? activatedPlan,
        amount: _pendingPlanAmount ?? 0,
        orderId: r.orderId ?? r.paymentId ?? '',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Plan activated!'),
            backgroundColor: AppColors.green));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e,
            fallback: 'Payment verification failed. Please contact support.');
      }
    }
  }

  void _handleError(PaymentFailureResponse r) {
    debugPrint('Razorpay error: code=${r.code} message=${r.message}');
    if (mounted) {
      final msg = friendlyErrorMessage(
        r.message ?? 'Payment cancelled',
        fallback: 'Payment was not completed. Please try again.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.red),
      );
    }
  }

  void _handleWallet(ExternalWalletResponse r) {}

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final slug = state.plan;
    final plans = state.availablePlans;
    final currentPlan = _currentPlan(plans, slug);
    final currentTier =
        slug == 'free' ? 0 : (currentPlan != null ? _planTier(currentPlan) : 0);
    final upgrades = _upgradePlans(plans, currentTier);

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          const PageHeader(title: 'Subscription'),
          Expanded(
            child: _plansLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (slug == 'free') ...[
                        _freeBanner(),
                      ] else if (currentPlan != null) ...[
                        _sectionLabel('Current plan', active: true),
                        _planCard(
                          plan: currentPlan,
                          color: AppColors.brand,
                          isCurrent: true,
                          expiresAt: state.subscriptionExpiresAt,
                        ),
                      ] else ...[
                        _sectionLabel('Current plan', active: true),
                        _legacyCurrentBanner(slug, state.subscriptionExpiresAt),
                      ],
                      if (upgrades.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _sectionLabel('Available upgrades'),
                        ...upgrades.asMap().entries.map((entry) {
                          final i = entry.key;
                          final p = entry.value;
                          return _planCard(
                            plan: p,
                            color: _cardColors[i % _cardColors.length],
                            isCurrent: false,
                            onUpgrade: _loading ? null : () => _startPayment(p),
                          );
                        }),
                      ] else if (slug != 'free' && currentPlan != null) ...[
                        SurfaceCard(
                          radius: 18,
                          gradient: const LinearGradient(colors: [Color(0xFFF1F5FF), AppColors.white]),
                          borderColor: AppColors.brandBorder.withValues(alpha: 0.6),
                          padding: const EdgeInsets.all(16),
                          child: const Row(children: [
                            IconTile(icon: Icons.shield_outlined, color: AppColors.brand, background: AppColors.white, size: 40, iconSize: 20),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text("You're on the highest plan. No further upgrades available.",
                                  style: TextStyle(color: AppColors.light, fontSize: 13.5, height: 1.45)),
                            ),
                          ]),
                        ),
                      ] else if (plans.isEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            'No plans available right now. Please check back later.',
                            style: TextStyle(color: AppColors.silver, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SurfaceCard(
                        radius: 18,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Need Plan Adjustments?',
                                    style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
                                SizedBox(height: 2),
                                Text('Contact your ProofIt account manager',
                                    style: TextStyle(color: AppColors.silver, fontSize: 12.5)),
                              ]),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/owner/enterprise-request'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(10)),
                                child: const Text('Get in touch',
                                    style: TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ]),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppColors.borderSoft)),
                          GestureDetector(
                            onTap: () => context.push('/owner/payment-history'),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('View billing history & invoices',
                                  style: TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.brand),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      // Storage used + the current plan's add-ons, same as Media and Storage.
                      const StorageAddOnsSection(showUsage: true),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text, {bool active = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Row(children: [
          Text(text.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.silver, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
          const Spacer(),
          if (active) const SoftBadge(label: 'Active', color: AppColors.greenDark, dot: true, fontSize: 12),
        ]),
      );

  Widget _freeBanner() => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: AppColors.amberSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.yellow.withValues(alpha: 0.35)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: AppColors.amberDark, size: 18),
          SizedBox(width: 10),
          Expanded(
              child: Text(
            'You are on the Free plan (1 staff). Upgrade to unlock more seats, export, live map and more.',
            style: TextStyle(color: AppColors.amberDark, fontSize: 13, height: 1.4),
          )),
        ]),
      );

  Widget _legacyCurrentBanner(String slug, DateTime? expiresAt) => SurfaceCard(
        radius: 22,
        borderColor: AppColors.brand,
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${slug[0].toUpperCase()}${slug.substring(1)}',
                style: AppTextStyles.h2.copyWith(fontSize: 24)),
            if (expiresAt != null)
              Text('Renews ${DateFormat('d MMM yyyy').format(expiresAt)}',
                  style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
          ])),
          const IconTile(icon: Icons.workspace_premium_outlined, color: AppColors.brand, size: 48, iconSize: 26),
        ]),
      );

  /// "5 GB storage included", for plans with the Storage feature.
  /// (Storage add-ons are sold separately — see the Storage section below.)
  List<String> _storageLines(Map<String, dynamic> plan) {
    final flags = plan['flags'];
    final storage = plan['storage'];
    if (flags is! Map || flags['storage'] != true || storage is! Map) return const [];
    final included = storage['includedGb'];
    return [if (included != null) '$included GB storage included'];
  }

  Widget _planCard({
    required Map<String, dynamic> plan,
    required Color color,
    required bool isCurrent,
    DateTime? expiresAt,
    VoidCallback? onUpgrade,
  }) {
    final features = [..._storageLines(plan), ...List<String>.from(plan['features'] ?? const [])];
    final maxStaff = plan['maxStaff']?.toString() ?? '-';
    final name = plan['name'] as String? ?? 'Plan';
    final description = (plan['description'] ?? '').toString();
    final priceLabel = _priceLabel(plan['price'], plan['durationDays']);
    final isEnterprise = name.toLowerCase().contains('enterprise');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isCurrent ? color : AppColors.border, width: isCurrent ? 1.6 : 1),
        boxShadow: AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0)]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: AppTextStyles.h2.copyWith(fontSize: 24)),
                    if (description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(description, style: const TextStyle(color: AppColors.silver, fontSize: 12.5, height: 1.35)),
                      ),
                    if (isCurrent && expiresAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Renews ${DateFormat('d MMM yyyy').format(expiresAt)}',
                            style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
                      ),
                    if (!isEnterprise) ...[
                      const SizedBox(height: 6),
                      _limit(Icons.people_outline, '$maxStaff staff'),
                    ],
                  ]),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                    boxShadow: AppColors.softShadow,
                  ),
                  child: Text(priceLabel,
                      style: AppTextStyles.h3.copyWith(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ]),
              if (features.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: AppColors.borderSoft)),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
                          child: Icon(Icons.check_rounded, color: color, size: 14),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(f, style: const TextStyle(color: AppColors.light, fontSize: 14.5))),
                      ]),
                    )),
              ] else
                const SizedBox(height: 16),
              const SizedBox(height: 6),
              if (isCurrent)
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                    boxShadow: AppColors.softShadow,
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.verified_outlined, color: color, size: 18),
                    const SizedBox(width: 8),
                    Text('Current Plan', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
                )
              else
                PrimaryButton(
                  label: isEnterprise ? 'Contact Sales' : 'Upgrade to $name',
                  color: color,
                  height: 50,
                  loading: _loading && _pendingPlanName == name,
                  onPressed: onUpgrade,
                ),
            ]),
          ),
        ]),
      ),
    );
  }
  Widget _limit(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppColors.silver, size: 14),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(color: AppColors.silver, fontSize: 12)),
      ]);
}
