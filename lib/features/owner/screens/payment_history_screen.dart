import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(ownerControllerProvider).paymentHistory;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Payment History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : RefreshIndicator(
              color: AppColors.brand,
              backgroundColor: AppColors.dark2,
              onRefresh: _load,
              child: history.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Icon(Icons.receipt_long_outlined, color: AppColors.muted, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'No payments yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.silver, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Your subscription payments will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final item = history[i];
                        final plan = item['plan'] as String?;
                        final status = item['status'] as String?;
                        final amount = (item['amount'] as num?)?.toInt() ?? 0;
                        final createdAt = _parseDate(item['createdAt']);
                        final periodEnd = _parseDate(item['currentPeriodEnd']);

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.dark2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  _planLabel(plan),
                                  style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                '₹$amount',
                                style: const TextStyle(color: AppColors.brand, fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  (status ?? 'unknown').toUpperCase(),
                                  style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const Spacer(),
                              if (createdAt != null)
                                Text(
                                  DateFormat('d MMM yyyy').format(createdAt),
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                ),
                            ]),
                            if (periodEnd != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Valid until ${DateFormat('d MMM yyyy').format(periodEnd)}',
                                style: const TextStyle(color: AppColors.silver, fontSize: 12),
                              ),
                            ],
                          ]),
                        );
                      },
                    ),
            ),
    );
  }
}
