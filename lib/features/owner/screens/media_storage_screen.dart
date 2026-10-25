import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../shared/models/storage_models.dart';
import '../../../shared/services/auth_storage.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/video_player_screen.dart';

/// Owner settings → Media and Storage: how much of the organisation's
/// storage is used, every stored photo and video (select + delete, like
/// WhatsApp's storage manager), and storage add-ons to buy or renew.
class MediaStorageScreen extends ConsumerStatefulWidget {
  const MediaStorageScreen({super.key});
  @override
  ConsumerState<MediaStorageScreen> createState() => _MediaStorageScreenState();
}

class _MediaStorageScreenState extends ConsumerState<MediaStorageScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);
  Razorpay? _razorpay;

  StorageSummary? _summary;
  List<AddOnProduct> _products = [];
  final Map<String, List<StoredMedia>> _items = {'image': [], 'video': []};
  final Map<String, bool> _hasMore = {'image': true, 'video': true};
  final Map<String, int> _page = {'image': 0, 'video': 0};
  final Set<String> _selected = {};
  String _sort = 'date';
  bool _loading = true;
  bool _loadingMore = false;
  bool _deleting = false;
  String? _buyingProductId;
  String? _error;

  String get _kind => _tabs.index == 0 ? 'image' : 'video';
  ApiService get _api => ref.read(apiServiceProvider);

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
    _refreshAll();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tabs.indexIsChanging) return;
    setState(_selected.clear);
    if (_items[_kind]!.isEmpty && _hasMore[_kind]!) _loadMore();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([_loadSummary(), _loadAddOns(), _reloadList()]);
    } catch (e) {
      _error = friendlyErrorMessage(e, fallback: 'Could not load storage. Pull to retry.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSummary() async {
    final res = await _api.get('/storage/summary');
    if (mounted) setState(() => _summary = StorageSummary.fromJson(Map<String, dynamic>.from(res.data['data'] as Map)));
  }

  Future<void> _loadAddOns() async {
    final res = await _api.get('/storage/addons');
    final d = res.data['data'] as Map;
    if (!mounted) return;
    setState(() => _products = [
          for (final p in (d['products'] as List? ?? const [])) AddOnProduct.fromJson(Map<String, dynamic>.from(p as Map)),
        ]);
  }

  Future<void> _reloadList() async {
    for (final k in ['image', 'video']) {
      _items[k] = [];
      _page[k] = 0;
      _hasMore[k] = true;
    }
    _selected.clear();
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final kind = _kind;
    if (_loadingMore || !_hasMore[kind]!) return;
    setState(() => _loadingMore = true);
    try {
      final page = _page[kind]! + 1;
      final res = await _api.get('/storage/media', params: {'kind': kind, 'page': '$page', 'limit': '60', 'sort': _sort});
      final d = res.data['data'] as Map;
      final list = [for (final m in (d['items'] as List)) StoredMedia.fromJson(Map<String, dynamic>.from(m as Map))];
      if (!mounted) return;
      setState(() {
        _items[kind]!.addAll(list);
        _page[kind] = page;
        _hasMore[kind] = d['pagination']?['hasMore'] == true;
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load media.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Delete ──────────────────────────────────────────────────

  Future<void> _deleteSelected([List<StoredMedia>? only]) async {
    final targets = only ?? _items[_kind]!.where((m) => _selected.contains(m.id)).toList();
    if (targets.isEmpty) return;
    final bytes = targets.fold<int>(0, (s, m) => s + m.bytes);
    final linked = targets.where((m) => m.reportId != null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${targets.length} item${targets.length == 1 ? '' : 's'}?'),
        content: Text(
          'This frees ${formatBytes(bytes)} and can\'t be undone.'
          '${linked > 0 ? '\n\n$linked ${linked == 1 ? 'is' : 'are'} attached to reports. The reports stay, but will show "Deleted to free storage" in place of the file, including in PDFs.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final res = await _api.post('/storage/media/delete', data: {'ids': targets.map((m) => m.id).toList()});
      _applyDeleteResult(Map<String, dynamic>.from(res.data['data'] as Map), res.data['message']?.toString());
    } on DioException catch (e) {
      // 502 = nothing could be deleted; the body still says which and why.
      final body = e.response?.data;
      final data = body is Map ? body['data'] : null;
      if (data is Map && mounted) {
        _applyDeleteResult(Map<String, dynamic>.from(data), body['message']?.toString());
      } else if (mounted) {
        showErrorSnackBar(context, e, fallback: 'Could not delete. Nothing was removed — please retry.');
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not delete. Nothing was removed — please retry.');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _applyDeleteResult(Map<String, dynamic> d, String? message) {
    final deleted = {for (final id in (d['deleted'] as List? ?? const [])) id.toString()};
    final failed = (d['failed'] as List? ?? const []).length;
    setState(() {
      for (final k in _items.keys) {
        _items[k]!.removeWhere((m) => deleted.contains(m.id));
      }
      _selected.removeAll(deleted);
      if (d['summary'] is Map) _summary = StorageSummary.fromJson(Map<String, dynamic>.from(d['summary'] as Map));
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message ?? (failed > 0 ? '$failed item${failed == 1 ? '' : 's'} could not be deleted. Please retry.' : 'Deleted')),
      backgroundColor: failed > 0 ? AppColors.red : AppColors.greenDark,
    ));
  }

  // ── Add-on purchase (Razorpay; iOS needs App Store IAP) ─────

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
      // e.g. payment captured a moment later — the webhook activates it.
      if (mounted) {
        showErrorSnackBar(context, e,
            fallback: 'Payment received. Storage will be added as soon as the payment is confirmed.');
      }
    } finally {
      if (mounted) setState(() => _buyingProductId = null);
      await _loadSummary();
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

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(children: [
          selecting ? _selectionHeader() : PageHeader(title: 'Media and Storage', actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort_rounded, color: AppColors.text),
              initialValue: _sort,
              onSelected: (v) {
                setState(() => _sort = v);
                _reloadList();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'date', child: Text('Newest first')),
                PopupMenuItem(value: 'size', child: Text('Largest first')),
              ],
            ),
          ]),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _refreshAll,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _loadMore();
                        return false;
                      },
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            sliver: SliverList(delegate: SliverChildListDelegate([
                              if (_error != null) _errorBox(_error!),
                              if (_summary != null) _summaryCard(_summary!),
                              if (_products.isNotEmpty || (_summary?.activeAddOns.isNotEmpty ?? false)) _addOnsSection(),
                              const SizedBox(height: 8),
                              TabBar(
                                controller: _tabs,
                                labelColor: AppColors.text,
                                unselectedLabelColor: AppColors.silver,
                                indicatorColor: AppColors.brand,
                                tabs: [
                                  Tab(text: 'Photos${_summary != null ? ' (${_summary!.imageCount})' : ''}'),
                                  Tab(text: 'Videos${_summary != null ? ' (${_summary!.videoCount})' : ''}'),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ])),
                          ),
                          _grid(),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: _loadingMore
                                  ? const Center(child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2))
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _selectionHeader() {
    final items = _items[_kind]!;
    final bytes = items.where((m) => _selected.contains(m.id)).fold<int>(0, (s, m) => s + m.bytes);
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_selected.clear)),
        Expanded(child: Text('${_selected.length} selected · ${formatBytes(bytes)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        TextButton(
          onPressed: () => setState(() => items.length == _selected.length ? _selected.clear() : _selected.addAll(items.map((m) => m.id))),
          child: Text(items.length == _selected.length ? 'None' : 'All'),
        ),
        _deleting
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.red)))
            : IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red), onPressed: _deleteSelected),
      ]),
    );
  }

  Widget _errorBox(String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(color: AppColors.red, fontSize: 13)),
      );

  Widget _summaryCard(StorageSummary s) {
    final cap = s.capacityBytes == 0 ? 1 : s.capacityBytes;
    final photoFrac = (s.imageBytes / cap).clamp(0.0, 1.0);
    final videoFrac = (s.videoBytes / cap).clamp(0.0, 1.0 - photoFrac);
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatBytes(s.usedBytes), style: const TextStyle(color: AppColors.text, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('used of ${formatBytes(s.capacityBytes)}', style: const TextStyle(color: AppColors.silver, fontSize: 14)),
          ),
          const Spacer(),
          Text('${formatBytes(s.freeBytes)} free', style: TextStyle(color: s.overQuota ? AppColors.red : AppColors.greenDark, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              Expanded(flex: (photoFrac * 1000).round(), child: const ColoredBox(color: AppColors.brand)),
              Expanded(flex: (videoFrac * 1000).round(), child: const ColoredBox(color: AppColors.purple)),
              Expanded(flex: ((1 - photoFrac - videoFrac).clamp(0.0, 1.0) * 1000).round(), child: const ColoredBox(color: AppColors.dark4)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _legend(AppColors.brand, 'Photos', s.imageBytes),
          _legend(AppColors.purple, 'Videos', s.videoBytes),
        ]),
        const Divider(height: 24, color: AppColors.borderSoft),
        Text(
          'Included with your plan: ${formatBytes(s.includedBytes)}'
          '${s.addOnBytes > 0 ? '  ·  Add-ons: ${formatBytes(s.addOnBytes)}' : ''}',
          style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
        ),
        if (s.overQuota || s.percentUsed >= 90) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: s.overQuota ? AppColors.redSoft : AppColors.amberSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(
              s.overQuota
                  ? 'Storage is full. Staff can\'t upload new photos or videos until you delete media or add storage.'
                  : 'Storage is almost full. Delete old media or add storage to keep uploads working.',
              style: TextStyle(color: s.overQuota ? AppColors.red : AppColors.amberDark, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _legend(Color c, String label, int bytes) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label  ${formatBytes(bytes)}', style: const TextStyle(color: AppColors.light, fontSize: 12.5)),
      ]);

  Widget _addOnsSection() {
    final s = _summary;
    final fmt = DateFormat('d MMM yyyy');
    final iosNoIap = Platform.isIOS;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('More storage'),
      for (final a in s?.activeAddOns ?? const <ActiveAddOn>[])
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
            if (a.isCurrent && !iosNoIap && _products.isNotEmpty)
              TextButton(
                onPressed: _buyingProductId != null ? null : () => _renew(a),
                child: const Text('Renew'),
              ),
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
                Text('₹${NumberFormat('#,##,##0.##', 'en_IN').format(p.price)} for ${p.durationDays} days${p.description.isNotEmpty ? ' · ${p.description}' : ''}',
                    style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
              ]),
            ),
            if (!iosNoIap)
              _buyingProductId == p.id
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                  : TextButton(onPressed: _buyingProductId != null ? null : () => _buy(p), child: const Text('Buy')),
          ]),
        ),
      if (iosNoIap && _products.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Storage add-ons can be purchased from the ProofIt Android app. Storage bought there applies to your whole organisation.',
              style: TextStyle(color: AppColors.silver, fontSize: 12)),
        ),
    ]);
  }

  /// Renewing buys the same pack size; the new period starts when the current one ends.
  void _renew(ActiveAddOn a) {
    final match = _products.where((p) => p.sizeGb * 1024 * 1024 * 1024 == a.sizeBytes).toList();
    if (match.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This pack is no longer sold. Choose another size below.'),
      ));
      return;
    }
    _buy(match.first, renewAddOnId: a.id);
  }

  Widget _grid() {
    final items = _items[_kind]!;
    if (items.isEmpty && !_loadingMore) {
      return SliverToBoxAdapter(
        child: SoftEmptyState(
          icon: _kind == 'image' ? Icons.photo_outlined : Icons.videocam_outlined,
          title: _kind == 'image' ? 'No photos stored' : 'No videos stored',
          subtitle: 'Report photos and videos uploaded by your team appear here.',
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
        delegate: SliverChildBuilderDelegate((context, i) => _tile(items[i]), childCount: items.length),
      ),
    );
  }

  Widget _tile(StoredMedia m) {
    final selected = _selected.contains(m.id);
    void toggle() => setState(() => selected ? _selected.remove(m.id) : _selected.add(m.id));
    return GestureDetector(
      onLongPress: toggle,
      onTap: _selected.isNotEmpty ? toggle : () => _showDetails(m),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(
            color: AppColors.dark4,
            child: m.thumbnailUrl != null
                ? Image.network(m.thumbnailUrl!, fit: BoxFit.cover, cacheWidth: 300,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.muted))
                : Icon(m.isVideo ? Icons.videocam_outlined : Icons.image_outlined, color: AppColors.muted),
          ),
          if (m.isVideo) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30)),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(5)),
              child: Text(
                [formatBytes(m.bytes), if (m.isVideo) formatDuration(m.durationSec)].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (selected) Container(color: AppColors.brand.withValues(alpha: 0.35)),
          if (_selected.isNotEmpty)
            Positioned(
              top: 5,
              right: 5,
              child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: Colors.white, size: 22),
            ),
        ]),
      ),
    );
  }

  void _showDetails(StoredMedia m) {
    final fmt = DateFormat('d MMM yyyy, h:mm a');
    AppSheet.show<void>(
      context,
      builder: (ctx) => AppSheet(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.originalFilename ?? (m.isVideo ? 'Video' : 'Photo'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.text)),
          const SizedBox(height: 10),
          _kv('Size', formatBytes(m.bytes)),
          if (m.isVideo && m.durationSec != null) _kv('Length', formatDuration(m.durationSec)),
          if (m.createdAt != null) _kv('Uploaded', fmt.format(m.createdAt!.toLocal())),
          _kv('Report', m.reportTitle == null ? 'Not attached to a report' : '${m.reportTitle}${m.slot != null ? ' (${m.slot})' : ''}'),
          if (m.staffName != null) _kv('By', m.staffName!),
          _kv('In report PDF', m.isVideo ? 'No — shared as a separate file' : 'Yes'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: SecondaryButton(
                label: m.isVideo ? 'Play' : 'View',
                icon: m.isVideo ? Icons.play_arrow_rounded : Icons.open_in_full_rounded,
                height: 46,
                onPressed: m.url == null ? null : () {
                  Navigator.pop(ctx);
                  _open(m);
                },
              ),
            ),
            if (m.reportId != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: 'Report',
                  icon: Icons.description_outlined,
                  height: 46,
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/owner/report/${m.reportId}');
                  },
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            color: AppColors.red,
            height: 46,
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSelected([m]);
            },
          ),
        ]),
      ),
    );
  }

  void _open(StoredMedia m) {
    if (m.isVideo) {
      VideoPlayerScreen.open(context, url: m.url, title: m.reportTitle ?? 'Video');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(m.reportTitle ?? 'Photo')),
        body: PhotoView(imageProvider: NetworkImage(m.url!)),
      ),
    ));
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.silver, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );
}
