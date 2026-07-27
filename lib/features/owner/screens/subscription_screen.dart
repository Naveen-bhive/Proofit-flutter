import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/owner_controller.dart';

import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../shared/services/auth_storage.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Razorpay? _razorpay;
  String?   _selectedPlanSlug;
  String?   _selectedPlanName;
  bool      _loading = false;
  bool      _plansLoading = true;

  static const List<Color> _cardColors = [AppColors.blue, AppColors.brand, Color(0xFF8B5CF6)];

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR,   _handleError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleWallet);
    Future.microtask(() async {
      await ref.read(ownerControllerProvider.notifier).loadSubscriptionStatus();
      await ref.read(ownerControllerProvider.notifier).loadAvailablePlans();
      if (mounted) setState(() => _plansLoading = false);
    });
  }

  @override
  void dispose() { _razorpay?.clear(); super.dispose(); }

  int _planTier(Map<String, dynamic> plan) => (plan['sortOrder'] as num?)?.toInt() ?? 0;

  Map<String, dynamic>? _currentPlan(List<Map<String, dynamic>> plans, String slug) {
    if (slug == 'free') return null;
    for (final p in plans) {
      if (p['slug'] == slug) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> _upgradePlans(List<Map<String, dynamic>> plans, int currentTier) {
    return plans
        .where((p) => _planTier(p) > currentTier)
        .toList()
      ..sort((a, b) => _planTier(a).compareTo(_planTier(b)));
  }

  Future<void> _startPayment(String planSlug, String planName, int price) async {
    setState(() { _selectedPlanSlug = planSlug; _selectedPlanName = planName; _loading = true; });
    try {
      final result = await ref.read(ownerControllerProvider.notifier).createOrder(planSlug);
      final data = result.data;
      if (data == null) throw Exception(result.error ?? 'Could not start payment');

      final user = await AuthStorage.getUser();

      _razorpay!.open({
        'key':         data['key'],
        'amount':      data['amount'] is int ? data['amount'] : int.parse('${data['amount']}'),
        'currency':    'INR',
        'order_id':    data['orderId'],
        'name':        'ProofIt',
        'description': '$planName Plan',
        'prefill':     {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
        'theme':       {'color': '#FF4D00'},
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not start payment. Please try again.');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  void _handleSuccess(PaymentSuccessResponse r) async {
    try {
      final ok = await ref.read(ownerControllerProvider.notifier).verifyPayment(
        orderId: r.orderId ?? '',
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
        plan: _selectedPlanSlug ?? '',
      );
      if (!ok) throw Exception('Verification failed');
      await ref.read(ownerControllerProvider.notifier).loadSubscriptionStatus();
      await ref.read(ownerControllerProvider.notifier).loadAvailablePlans();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan activated!'), backgroundColor: AppColors.green));
        context.pop();
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Payment verification failed. Please contact support.');
    }
  }

  void _handleError(PaymentFailureResponse r) {
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
    final slug  = state.plan;
    final plans = state.availablePlans;
    final currentPlan = _currentPlan(plans, slug);
    final currentTier = slug == 'free' ? 0 : (currentPlan != null ? _planTier(currentPlan) : 0);
    final upgrades = _upgradePlans(plans, currentTier);

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Subscription')),
      body: _plansLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
        : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        if (slug == 'free') ...[
          _freeBanner(),
        ] else if (currentPlan != null) ...[
          _sectionLabel('Current plan'),
          _planCard(
            plan: currentPlan,
            color: AppColors.brand,
            isCurrent: true,
            expiresAt: state.subscriptionExpiresAt,
          ),
        ] else ...[
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
              onUpgrade: _loading ? null : () => _startPayment(
                p['slug'] as String? ?? '',
                p['name'] as String? ?? 'Plan',
                (p['price'] as num?)?.toInt() ?? 0,
              ),
            );
          }),
        ] else if (slug != 'free' && currentPlan != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.dark2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              "You're on the highest plan. No further upgrades available.",
              style: TextStyle(color: AppColors.silver, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ] else if (plans.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'No plans available right now. Please check back later.',
              style: const TextStyle(color: AppColors.silver, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],

        const SizedBox(height: 40),
      ])),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: Text(text, style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
  );

  Widget _freeBanner() => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: AppColors.yellow.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.yellow.withOpacity(0.3)),
    ),
    child: const Row(children: [
      Icon(Icons.info_outline, color: AppColors.yellow, size: 18),
      SizedBox(width: 10),
      Expanded(child: Text(
        'You are on the Free plan (1 staff). Upgrade to unlock more seats, export, live map and more.',
        style: TextStyle(color: AppColors.yellow, fontSize: 13),
      )),
    ]),
  );

  Widget _legacyCurrentBanner(String slug, DateTime? expiresAt) => Container(
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: AppColors.brand.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.brand.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.workspace_premium_outlined, color: AppColors.brand, size: 28),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Current Plan', style: TextStyle(color: AppColors.silver, fontSize: 12)),
        Text('${slug[0].toUpperCase()}${slug.substring(1)}',
          style: const TextStyle(color: AppColors.brand, fontSize: 22, fontWeight: FontWeight.w800)),
      ])),
      if (expiresAt != null)
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Renews', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          Text(DateFormat('d MMM yyyy').format(expiresAt),
            style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
    ]),
  );

  Widget _planCard({
    required Map<String, dynamic> plan,
    required Color color,
    required bool isCurrent,
    DateTime? expiresAt,
    VoidCallback? onUpgrade,
  }) {
    final features = List<String>.from(plan['features'] ?? const []);
    final maxStaff = plan['maxStaff']?.toString() ?? '-';
    final price = plan['price'] ?? 0;
    final durationDays = plan['durationDays'] ?? 30;
    final name = plan['name'] as String? ?? 'Plan';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isCurrent ? color.withOpacity(0.08) : AppColors.dark2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCurrent ? color : AppColors.border, width: isCurrent ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800))),
            Text(
              '₹$price${durationDays == 30 ? '/mo' : '/${durationDays}d'}',
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ]),
          if (isCurrent && expiresAt != null) ...[
            const SizedBox(height: 6),
            Text('Renews ${DateFormat('d MMM yyyy').format(expiresAt)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          _limit(Icons.people_outline, '$maxStaff staff'),
          if (features.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.check_rounded, color: color, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(f, style: const TextStyle(color: AppColors.light, fontSize: 13))),
              ]),
            )),
          ],
          const SizedBox(height: 16),
          if (isCurrent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text('Current Plan', style: TextStyle(color: color, fontWeight: FontWeight.w700))),
            )
          else
            ElevatedButton(
              onPressed: onUpgrade,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Upgrade to $name',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
        ]),
      ),
    );
  }

  Widget _limit(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, color: AppColors.silver, size: 14),
    const SizedBox(width: 4),
    Text(text, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
  ]);
}
