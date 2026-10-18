import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../controllers/owner_controller.dart';

class PaymentHistoryScreen extends ConsumerStatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  ConsumerState<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await ref.read(ownerControllerProvider.notifier).loadPaymentHistory();
    if (mounted) setState(() => _loading = false);
  }

  String _planLabel(String? slug) {
    if (slug == null || slug.isEmpty) return 'Plan';
    return '${slug[0].toUpperCase()}${slug.substring(1)}';
  }

  Color _statusColor(String? status) => switch (status) {
    'active' => AppColors.green,
    'failed' => AppColors.red,
    'expired' => AppColors.yellow,
    'pending' => AppColors.yellow,
    _ => AppColors.silver,
  };

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  String _billingMethod(Map<String, dynamic> item) {
    if (item['isCustom'] == true) return 'Direct Enterprise Agreement';
    return switch (item['provider']) {
      'revenuecat' => 'App Store',
      'razorpay' => 'Razorpay',
      _ => '-',
    };
  }

  String _invoiceId(Map<String, dynamic> item) {
    final id = (item['razorpaySubscriptionId'] ?? item['razorpayOrderId'] ?? item['_id'] ?? '').toString();
    if (id.isEmpty) return '-';
    return id.length > 16 ? id.substring(id.length - 12).toUpperCase() : id.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(ownerControllerProvider).paymentHistory;

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          const PageHeader(title: 'Payment History'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _load,
                    child: history.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 110),
                              SoftEmptyState(
                                icon: Icons.receipt_long_outlined,
                                title: 'No payments yet',
                                subtitle: 'Your subscription payments will appear here.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            itemCount: history.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                            itemBuilder: (_, i) => _card(history[i], i == 0),
                          ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> item, bool first) {
    final plan = item['plan'] as String?;
    final status = (item['status'] as String?) ?? 'unknown';
    final amount = (item['amount'] as num?)?.toInt() ?? 0;
    final createdAt = _parseDate(item['createdAt']);
    final periodEnd = _parseDate(item['currentPeriodEnd'] ?? item['expiresAt']);
    final current = first && status == 'active';
    final color = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: 4, decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(current ? 'CURRENT PLAN' : 'SUBSCRIPTION',
                        style: const TextStyle(color: AppColors.brand, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    Text(_planLabel(plan), style: AppTextStyles.h2.copyWith(fontSize: 22)),
                    if (createdAt != null)
                      Text('Started ${DateFormat('d MMM yyyy').format(createdAt)}',
                          style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
                  ]),
                ),
                Text('₹$amount', style: AppTextStyles.h2.copyWith(color: AppColors.brand, fontSize: 24)),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.dark3,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Row(children: [
                  SoftBadge(label: status, color: color == AppColors.green ? AppColors.greenDark : color, dot: true, uppercase: true, fontSize: 12),
                  const Spacer(),
                  if (periodEnd != null) ...[
                    const Icon(Icons.event_outlined, size: 15, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: status == 'active' ? 'Renews: ' : 'Valid until: '),
                      TextSpan(text: DateFormat('d MMM yyyy').format(periodEnd),
                          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                    ]), style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                  ],
                ]),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: AppColors.borderSoft)),
              _kv('Billing Method', Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 14, color: AppColors.brand),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_billingMethod(item),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ])),
              const SizedBox(height: 10),
              _kv('Invoice ID', Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(6)),
                child: Text(_invoiceId(item),
                    style: const TextStyle(color: AppColors.light, fontSize: 12, fontWeight: FontWeight.w600)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _kv(String k, Widget v) => Row(children: [
        Text(k, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(child: Align(alignment: Alignment.centerRight, child: v)),
      ]);
}
