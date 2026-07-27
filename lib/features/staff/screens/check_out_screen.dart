import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/location_service.dart';
import '../controllers/staff_controller.dart';
import '../utils/attendance_gates.dart';

class CheckOutScreen extends ConsumerStatefulWidget {
  const CheckOutScreen({super.key});
  @override
  ConsumerState<CheckOutScreen> createState() => _CheckOutScreenState();
}

class _CheckOutScreenState extends ConsumerState<CheckOutScreen> {
  double? _lat, _lng;
  String? _address;
  bool _locLoading = true;
  bool _submitting = false;
  bool _checkingGate = true;
  final _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _getLocation();
    Future.microtask(_prepare);
  }

  Future<void> _prepare() async {
    await ref.read(staffControllerProvider.notifier).loadCheckInStatus();
    if (!mounted) return;
    final allowed = await AttendanceGates.allowCheckOut(context, ref);
    if (!mounted) return;
    if (!allowed) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/staff');
      }
      return;
    }
    setState(() => _checkingGate = false);
  }

  Future<void> _getLocation() async {
    setState(() => _locLoading = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      final addr = await LocationService.getAddressFromCoords(pos.latitude, pos.longitude);
      setState(() { _lat = pos.latitude; _lng = pos.longitude; _address = addr; });
    }
    setState(() => _locLoading = false);
  }

  String _formatDuration(DateTime? checkInTime) {
    if (checkInTime == null) return '--';
    final localCheckIn = parseApiDate(checkInTime) ?? checkInTime;
    final diff = _now.difference(localCheckIn);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return '${h}h ${m}m';
  }

  Future<void> _checkOut() async {
    if (_lat == null) { _getLocation(); return; }
    setState(() => _submitting = true);
    final result = await ref.read(staffControllerProvider.notifier)
        .checkOut(latitude: _lat!, longitude: _lng!, address: _address);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Checked out! Good work today.'), backgroundColor: AppColors.brand));
      context.pop();
      return;
    }

    final message = result.message ??
        'Complete the job first by submitting a report before checking out.';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.brand));

    if (result.jobId != null && result.jobId!.isNotEmpty) {
      final title = Uri.encodeComponent(result.jobTitle ?? 'Assigned job');
      context.pushReplacement('/staff/submit?jobId=${result.jobId}&jobTitle=$title');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    if (_checkingGate) {
      return const Scaffold(
        backgroundColor: AppColors.dark,
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Check Out')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final minBodyHeight = MediaQuery.sizeOf(context).height
              - MediaQuery.paddingOf(context).vertical
              - kToolbarHeight
              - 48;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minBodyHeight > 0 ? minBodyHeight : constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(children: [
                  const Spacer(),
                  Container(
                    width: 180, height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brand.withOpacity(0.08),
                      border: Border.all(color: AppColors.brand.withOpacity(0.3), width: 2),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.logout_rounded, color: AppColors.brand, size: 40),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(DateFormat('hh:mm a').format(_now),
                            style: const TextStyle(color: AppColors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                      ),
                      Text(DateFormat('d MMM yyyy').format(_now),
                          style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                    ]),
                  ),
                  const SizedBox(height: 32),
                  Row(children: [
                    Expanded(child: _summaryCard('Duration', _formatDuration(state.checkInTime), Icons.timer_outlined, AppColors.blue)),
                    const SizedBox(width: 12),
                    Expanded(child: _summaryCard('Reports Done', '${state.submittedToday}', Icons.assignment_turned_in_outlined, AppColors.green)),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Icon(_locLoading ? Icons.hourglass_empty : Icons.location_on_outlined,
                          color: _lat != null ? AppColors.green : AppColors.muted, size: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Text(
                        _locLoading ? 'Fetching location...' : _address ?? 'Location unavailable',
                        style: const TextStyle(color: AppColors.light, fontSize: 14),
                      )),
                    ]),
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Check Out Now',
                    isLoading: _submitting,
                    onPressed: _locLoading ? null : _checkOut,
                    icon: Icons.logout_rounded,
                  ),
                  const SizedBox(height: 12),
                  AppButton(label: 'Cancel', isOutlined: true, onPressed: () => context.pop()),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
      ]),
    );
  }
}