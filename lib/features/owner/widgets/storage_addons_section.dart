import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../shared/models/storage_models.dart';
import '../../../shared/permissions/permission_session.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/widgets/ui_kit.dart';

/// Storage add-ons for the owner's current plan: active packs (with Renew)
/// and packs to buy, paid with Razorpay. Prices and sizes come from the
/// plan's settings in the admin panel. Used on Media and Storage and on the
/// Subscription screen.
class StorageAddOnsSection extends ConsumerStatefulWidget {
  /// Shows a compact "X used of Y · Manage" line (Subscription screen).
  final bool showUsage;
  /// Called after a purchase so the parent can refresh its own figures.
  final VoidCallback? onPurchased;

  const StorageAddOnsSection({super.key, this.showUsage = false, this.onPurchased});

  @override
  ConsumerState<StorageAddOnsSection> createState() => _StorageAddOnsSectionState();
}

class _StorageAddOnsSectionState extends ConsumerState<StorageAddOnsSection> {
  Razorpay? _razorpay;
  StorageSummary? _summary;
  List<AddOnProduct> _products = [];
  bool _loading = true;
  String? _buyingProductId;

  ApiService get _api => ref.read(apiServiceProvider);

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
    _load();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_api.get('/storage/summary'), _api.get('/storage/addons')]);
      final addOns = results[1].data['data'] as Map;
      if (!mounted) return;
      setState(() {
        _summary = StorageSummary.fromJson(Map<String, dynamic>.from(results[0].data['data'] as Map));
        _products = [
          for (final p in (addOns['products'] as List? ?? const [])) AddOnProduct.fromJson(Map<String, dynamic>.from(p as Map)),
        ];
      });
    } catch (_) {
      // Storage is optional on these screens; leave the section empty.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buy(AddOnProduct product, {String? renewAddOnId}) async {
    setState(() => _buyingProductId = product.id);
    try {
      final res = await _api.post('/storage/addons/order', data: {
        'productId': product.id,
        if (renewAddOnId != null) 'renewAddOnId': renewAddOnId,
      });
      final d = res.data['data'] as Map;
      final user = await AuthStorage.getUser();
      _razorpay!.open({
        'key': d['key'],
        'amount': d['amount'],
        'currency': d['currency'] ?? 'INR',
        'order_id': d['orderId'],
        'name': 'ProofIt',
        'description': d['productName'] ?? product.name,
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
        'theme': {'color': '#2F80ED'},
      });
    } catch (e) {
      if (mounted) {
        setState(() => _buyingProductId = null);
        showErrorSnackBar(context, e, fallback: 'Could not start payment. Please try again.');
      }
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    try {
      final res = await _api.post('/storage/addons/verify', data: {
        'razorpay_order_id': r.orderId,
        'razorpay_payment_id': r.paymentId,
        'razorpay_signature': r.signature,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.data['message']?.toString() ?? 'Storage added'),
        backgroundColor: AppColors.greenDark,
      ));
    } catch (e) {
      // e.g. the payment is captured a moment later — the webhook activates it.
      if (mounted) {
        showErrorSnackBar(context, e,
            fallback: 'Payment received. Storage will be added as soon as the payment is confirmed.');
      }
    } finally {
      if (mounted) setState(() => _buyingProductId = null);
      await _load();
      widget.onPurchased?.call();
    }
  }

  void _onPaymentError(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _buyingProductId = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(friendlyErrorMessage(r.message ?? 'Payment cancelled', fallback: 'Payment was not completed.')),
      backgroundColor: AppColors.red,
    ));
  }

  /// Renewing buys the same pack size; the new period starts when the current one ends.
  void _renew(ActiveAddOn a) {
    final match = _products.where((p) => p.sizeGb * 1024 * 1024 * 1024 == a.sizeBytes).toList();
    if (match.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This pack is not offered on your current plan. Choose another size.'),
      ));
      return;
    }
    _buy(match.first, renewAddOnId: a.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final s = _summary;
    final active = s?.activeAddOns ?? const <ActiveAddOn>[];
    if (!widget.showUsage && _products.isEmpty && active.isEmpty) return const SizedBox.shrink();
    final fmt = DateFormat('d MMM yyyy');
    final iosNoIap = Platform.isIOS;
    // Staff with storage access can see the packs; only the owner pays.
    final canBuy = ref.watch(permissionSessionProvider).isOwner;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionLabel(widget.showUsage ? 'Storage' : 'More storage'),
      if (widget.showUsage && s != null)
        SurfaceCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          onTap: () => context.push('/owner/storage'),
          child: Row(children: [
            const IconTile(icon: Icons.sd_storage_outlined, color: AppColors.purple),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${formatBytes(s.usedBytes)} used of ${formatBytes(s.capacityBytes)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                Text('Included with your plan: ${formatBytes(s.includedBytes)}${s.addOnBytes > 0 ? ' · add-ons ${formatBytes(s.addOnBytes)}' : ''}',
                    style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
              ]),
            ),
            const Text('Manage', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600)),
          ]),
        ),
      for (final a in active)
        SurfaceCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const IconTile(icon: Icons.cloud_done_outlined, color: AppColors.greenDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                Text(
                  a.isCurrent
                      ? 'Active until ${a.expiresAt != null ? fmt.format(a.expiresAt!.toLocal()) : '-'}'
                      : 'Starts ${a.startsAt != null ? fmt.format(a.startsAt!.toLocal()) : '-'} (renewal)',
                  style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
                ),
              ]),
            ),
            if (a.isCurrent && canBuy && !iosNoIap && _products.isNotEmpty)
              TextButton(onPressed: _buyingProductId != null ? null : () => _renew(a), child: const Text('Renew')),
          ]),
        ),
      for (final p in _products)
        SurfaceCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const IconTile(icon: Icons.add_to_drive_outlined, color: AppColors.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('+${p.sizeGb} GB storage', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                Text('₹${NumberFormat('#,##,##0.##', 'en_IN').format(p.price)} for ${p.durationDays} days',
                    style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
              ]),
            ),
            if (canBuy && !iosNoIap)
              _buyingProductId == p.id
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                  : TextButton(onPressed: _buyingProductId != null ? null : () => _buy(p), child: const Text('Buy')),
          ]),
        ),
      if (!canBuy && _products.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Only the owner can buy more storage.', style: TextStyle(color: AppColors.silver, fontSize: 12)),
        ),
      if (canBuy && iosNoIap && _products.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Storage add-ons can be purchased from the ProofIt Android app. Storage bought there applies to your whole organisation.',
              style: TextStyle(color: AppColors.silver, fontSize: 12)),
        ),
    ]);
  }
}
