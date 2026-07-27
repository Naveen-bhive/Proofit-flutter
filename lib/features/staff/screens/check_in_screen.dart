import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/battery_optimization_service.dart';
import '../controllers/staff_controller.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});
  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> with WidgetsBindingObserver {
  double? _lat, _lng;
  String? _address;
  bool _locLoading = true;
  bool _submitting = false;
  bool _gpsOn = false;
  bool _hasAlwaysPermission = false;
  bool _hasPrecise = false;
  bool _batteryWarningReady = false;
  final _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshGatesAndLocation();
    }
  }

  Future<void> _bootstrap() async {
    await _refreshGatesAndLocation();
  }

  Future<void> _refreshGatesAndLocation() async {
    final gpsOn = await LocationService.isLocationServiceOn();
    final always = await LocationService.hasAlwaysPermission();
    final precise = await LocationService.hasPreciseLocation();
    final batteryShown = await BatteryOptimizationService.hasWarningBeenShown();
    if (!mounted) return;
    setState(() {
      _gpsOn = gpsOn;
      _hasAlwaysPermission = always;
      _hasPrecise = precise;
      _batteryWarningReady = batteryShown;
    });
    if (_lat == null) await _getLocation();
  }

  Future<bool> _ensureGpsOn() async {
    final on = await LocationService.isLocationServiceOn();
    if (on) {
      if (mounted) setState(() => _gpsOn = true);
      return true;
    }
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Turn on Location / GPS, then try again.'),
      backgroundColor: AppColors.red,
    ));
    await Geolocator.openLocationSettings();
    final again = await LocationService.isLocationServiceOn();
    if (mounted) setState(() => _gpsOn = again);
    return again;
  }

  Future<bool> _ensureBackgroundPermission({bool forcePrompt = false}) async {
    final already = await LocationService.hasAlwaysPermission();
    if (already) {
      if (mounted) setState(() => _hasAlwaysPermission = true);
      return true;
    }
    if (!forcePrompt || !mounted) return false;

    final granted = await LocationService.ensureAlwaysLocationPermission(context);
    if (mounted) setState(() => _hasAlwaysPermission = granted);
    return granted;
  }

  Future<bool> _ensurePrecise() async {
    if (await LocationService.hasPreciseLocation()) {
      if (mounted) setState(() => _hasPrecise = true);
      return true;
    }
    if (!mounted) return false;
    final ok = await LocationService.ensurePreciseLocation(context);
    if (mounted) setState(() => _hasPrecise = ok);
    return ok;
  }

  Future<bool> _ensureBatteryWarning() async {
    if (!mounted) return false;
    final ok = await BatteryOptimizationService.ensureWarningShownBeforeCheckIn(context);
    if (mounted) setState(() => _batteryWarningReady = ok);
    return ok;
  }

  Future<void> _getLocation() async {
    setState(() => _locLoading = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      final addr = await LocationService.getAddressFromCoords(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address = addr;
      });
    }
    if (mounted) setState(() => _locLoading = false);
  }

  Future<void> _checkIn() async {
    // 1) GPS on
    if (!await _ensureGpsOn()) return;

    // 2) Allow all the time
    final alwaysOk = await _ensureBackgroundPermission(forcePrompt: true);
    if (!alwaysOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select “Allow all the time” to check in. Live tracking needs background location.'),
        backgroundColor: AppColors.brand,
        duration: Duration(seconds: 4),
      ));
      return;
    }

    // 3) Precise location
    if (!await _ensurePrecise()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Turn on Precise location so your owner can track you accurately.'),
        backgroundColor: AppColors.brand,
        duration: Duration(seconds: 4),
      ));
      return;
    }

    // 4) Battery optimization warning must be shown
    if (!await _ensureBatteryWarning()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please review the battery warning so live tracking is not stopped by your phone.'),
        backgroundColor: AppColors.yellow,
        duration: Duration(seconds: 4),
      ));
      return;
    }

    if (_lat == null) {
      await _getLocation();
      if (_lat == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not get your location. Turn on GPS and try again.'),
          backgroundColor: AppColors.red,
        ));
        return;
      }
    }

    setState(() => _submitting = true);
    final ok = await ref.read(staffControllerProvider.notifier).checkIn(
          latitude: _lat!,
          longitude: _lng!,
          address: _address,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Checked in! Live location is now shared with your owner.'),
        backgroundColor: AppColors.green,
      ));
      // Soft follow-up for OEM autostart if still needed.
      await BatteryOptimizationService.maybePromptAfterCheckIn(context);
      if (!mounted) return;
      context.pop();
    }
  }

  Widget _gateChip({
    required bool ok,
    required String label,
    required VoidCallback? onFix,
  }) {
    final color = ok ? AppColors.green : AppColors.yellow;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
        if (!ok && onFix != null)
          GestureDetector(
            onTap: onFix,
            child: const Text('Fix', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minBodyHeight = MediaQuery.sizeOf(context).height
        - MediaQuery.paddingOf(context).vertical
        - kToolbarHeight
        - 48;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Check In')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minBodyHeight > 0 ? minBodyHeight : constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(children: [
                  const Spacer(),
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.green.withOpacity(0.08),
                      border: Border.all(color: AppColors.green.withOpacity(0.3), width: 2),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.login_rounded, color: AppColors.green, size: 40),
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
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.dark2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      Icon(_locLoading ? Icons.hourglass_empty : Icons.location_on_outlined,
                          color: _lat != null ? AppColors.green : AppColors.muted, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _locLoading ? 'Fetching location...' : _address ?? 'Location unavailable',
                          style: const TextStyle(color: AppColors.light, fontSize: 14),
                        ),
                      ),
                      if (!_locLoading)
                        GestureDetector(
                          onTap: _getLocation,
                          child: const Icon(Icons.refresh_rounded, color: AppColors.brand, size: 20),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Required for live tracking',
                      style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _gateChip(
                    ok: _gpsOn,
                    label: _gpsOn ? 'Location / GPS is on' : 'Location / GPS is off',
                    onFix: () => _ensureGpsOn(),
                  ),
                  _gateChip(
                    ok: _hasAlwaysPermission,
                    label: _hasAlwaysPermission
                        ? 'Allow all the time enabled'
                        : 'Allow all the time required',
                    onFix: () => _ensureBackgroundPermission(forcePrompt: true),
                  ),
                  _gateChip(
                    ok: _hasPrecise,
                    label: _hasPrecise ? 'Precise location enabled' : 'Precise location required',
                    onFix: () => _ensurePrecise(),
                  ),
                  _gateChip(
                    ok: _batteryWarningReady,
                    label: _batteryWarningReady
                        ? 'Battery warning reviewed'
                        : 'Battery optimization warning required',
                    onFix: () => _ensureBatteryWarning(),
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Check In Now',
                    isLoading: _submitting,
                    onPressed: _locLoading ? null : _checkIn,
                    icon: Icons.login_rounded,
                    color: AppColors.green,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ProofIt will keep a permanent notification while you are checked in and share your live location with your owner.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
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
}
