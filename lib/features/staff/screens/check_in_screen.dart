import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/work_mode_badge.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/battery_optimization_service.dart';
import '../../../shared/services/review_service.dart';
import '../controllers/staff_controller.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});
  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen>
    with WidgetsBindingObserver {
  double? _lat, _lng;
  String? _address;
  bool _locLoading = true;
  bool _submitting = false;
  bool _gpsOn = false;
  bool _hasAlwaysPermission = false;
  bool _hasPrecise = false;
  bool _batteryWarningReady = false;
  bool _success = false;
  DateTime? _checkedInAt;
  final _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(staffControllerProvider.notifier).loadCheckInStatus());
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

    final granted =
        await LocationService.ensureAlwaysLocationPermission(context);
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
    final ok = await BatteryOptimizationService.ensureWarningShownBeforeCheckIn(
        context);
    if (mounted) setState(() => _batteryWarningReady = ok);
    return ok;
  }

  Future<void> _getLocation() async {
    setState(() => _locLoading = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      final addr = await LocationService.getAddressFromCoords(
          pos.latitude, pos.longitude);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(Platform.isIOS
            ? 'Location permission is required to check in.'
            : 'Select "Allow all the time" to check in. Live tracking needs background location.'),
        backgroundColor: AppColors.brand,
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    // 3) Precise location
    if (!await _ensurePrecise()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Turn on Precise location so your owner can track you accurately.'),
        backgroundColor: AppColors.brand,
        duration: Duration(seconds: 4),
      ));
      return;
    }

    // 4) Battery optimization warning must be shown
    if (!await _ensureBatteryWarning()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Please review the battery warning so live tracking is not stopped by your phone.'),
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
          content:
              Text('Could not get your location. Turn on GPS and try again.'),
          backgroundColor: AppColors.red,
        ));
        return;
      }
    }

    setState(() => _submitting = true);
    final result = await ref.read(staffControllerProvider.notifier).checkIn(
          latitude: _lat!,
          longitude: _lng!,
          address: _address,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) {
      ReviewService.maybePromptAfterSuccess();
      // Soft follow-up for OEM autostart if still needed.
      await BatteryOptimizationService.maybePromptAfterCheckIn(context);
      if (!mounted) return;
      setState(() {
        _success = true;
        _checkedInAt = DateTime.now();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(result.message ?? 'Could not check in. Please try again.'),
        backgroundColor: AppColors.red,
      ));
    }
  }

  Widget _gateChip({
    required bool ok,
    required String label,
    required VoidCallback? onFix,
  }) {
    final color = ok ? AppColors.green : AppColors.yellow;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: AppColors.amberSoft,
              borderRadius: BorderRadius.circular(9)),
          child: Icon(ok ? Icons.check_rounded : Icons.warning_amber_rounded,
              color: ok ? AppColors.greenDark : AppColors.yellow, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500))),
        GestureDetector(
          onTap: ok ? null : onFix,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: ok ? AppColors.greenDark : AppColors.yellow,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(ok ? 'Fixed' : 'Fix',
                style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ),
        ),
      ]),
    );
  }

  Widget _clockDial() {
    return Container(
      width: 220,
      height: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFDBEAFE), Color(0xFFF8FAFC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: AppColors.brandBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: AppColors.brand.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 10))
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.white, Color(0xFFF1F5FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(DateFormat('hh:mm a').format(_now),
                style: AppTextStyles.h1
                    .copyWith(fontSize: 30, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Text(DateFormat('d MMM yyyy').format(_now),
              style: const TextStyle(color: AppColors.silver, fontSize: 13.5)),
          const SizedBox(height: 10),
          const SoftBadge(
              label: 'Shift Start',
              color: AppColors.brand,
              dot: true,
              uppercase: true,
              fontSize: 11),
        ]),
      ),
    );
  }

  Widget _locationCard() {
    final hasFix = _lat != null;
    return SurfaceCard(
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        IconTile(
          icon: Icons.location_on_outlined,
          color: hasFix ? AppColors.greenDark : AppColors.silver,
          background: hasFix ? AppColors.greenSoft : AppColors.dark4,
          size: 40,
          iconSize: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _locLoading
                  ? 'Fetching location...'
                  : (_address ??
                      (hasFix ? 'Location found' : 'Location unavailable')),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              hasFix
                  ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                  : (_locLoading
                      ? 'Waiting for GPS signal'
                      : 'GPS signal not detected'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ]),
        ),
        if (!_locLoading)
          GestureDetector(
            onTap: _getLocation,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(Icons.refresh_rounded, color: AppColors.brand, size: 22),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_success) return _successView();
    final staffState = ref.watch(staffControllerProvider);
    final issues = [
      _gpsOn,
      _hasAlwaysPermission,
      _hasPrecise,
      _batteryWarningReady
    ].where((ok) => !ok).length;

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          const PageHeader(title: 'Check In'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(children: [
                const SizedBox(height: 4),
                _clockDial(),
                const SizedBox(height: 22),
                _locationCard(),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.dark2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WorkModeBadge(
                            mode: staffState.workLocation, compact: true),
                        const SizedBox(height: 6),
                        Text(
                          !staffState.attendancePolicyLoaded
                              ? 'Loading your attendance location rule…'
                              : staffState.attendanceLocationRestricted
                              ? staffState.attendanceRadiusMeters == null
                                  ? 'Check in within your designated office attendance area.'
                                  : 'Check in within ${staffState.attendanceRadiusMeters} m of your office.'
                              : 'Your check-in is not limited to the office area.',
                          style: const TextStyle(
                              color: AppColors.silver,
                              fontSize: 12,
                              height: 1.4),
                        ),
                      ]),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(
                    child: Text(
                      'REQUIRED FOR LIVE TRACKING',
                      style: TextStyle(
                          color: AppColors.silver,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8),
                    ),
                  ),
                  if (issues > 0)
                    SoftBadge(
                      label: '$issues issue${issues == 1 ? '' : 's'}',
                      color: AppColors.amberDark,
                      background: AppColors.amberSoft,
                      fontSize: 11.5,
                    )
                  else
                    const SoftBadge(
                        label: 'All set',
                        color: AppColors.greenDark,
                        fontSize: 11.5),
                ]),
                const SizedBox(height: 10),
                _gateChip(
                  ok: _gpsOn,
                  label:
                      _gpsOn ? 'Location / GPS is on' : 'Location / GPS is off',
                  onFix: () => _ensureGpsOn(),
                ),
                _gateChip(
                  ok: _hasAlwaysPermission,
                  label: Platform.isIOS
                      ? (_hasAlwaysPermission
                          ? 'Location permission enabled'
                          : 'Location permission required')
                      : (_hasAlwaysPermission
                          ? 'Allow all the time enabled'
                          : 'Allow all the time required'),
                  onFix: () => _ensureBackgroundPermission(forcePrompt: true),
                ),
                _gateChip(
                  ok: _hasPrecise,
                  label: _hasPrecise
                      ? 'Precise location enabled'
                      : 'Precise location required',
                  onFix: () => _ensurePrecise(),
                ),
                _gateChip(
                  ok: _batteryWarningReady,
                  label: _batteryWarningReady
                      ? 'Battery warning reviewed'
                      : 'Battery optimization warning',
                  onFix: () => _ensureBatteryWarning(),
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Check In Now',
                  icon: Icons.login_rounded,
                  height: 56,
                  color: AppColors.green,
                  gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)]),
                  loading: _submitting,
                  onPressed: _locLoading ? null : _checkIn,
                ),
                const SizedBox(height: 12),
                Text(
                  Platform.isIOS
                      ? 'ProofIt shares your live location with your owner while the app is open.'
                      : 'ProofIt will keep a permanent notification while you are checked in and share your live location with your owner/admin.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.silver, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 14),
                SecondaryButton(
                    label: 'Cancel', onPressed: () => context.pop()),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _successView() {
    final at = _checkedInAt ?? DateTime.now();
    final org = ref.watch(staffControllerProvider).orgName;
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Column(children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.green.withValues(alpha: 0.10),
                    border: Border.all(
                        color: AppColors.green.withValues(alpha: 0.18),
                        width: 10),
                  ),
                  child: Center(
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                            colors: [AppColors.green, AppColors.greenDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        boxShadow: AppColors.glow(AppColors.green),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: AppColors.white, size: 42),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text('Successfully Checked In!',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h1.copyWith(fontSize: 24)),
                const SizedBox(height: 10),
                const Text(
                  'Your work session has started and GPS tracking is now actively synced.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.silver, fontSize: 14.5, height: 1.5),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(DateFormat('h:mm a').format(at),
                        style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('•',
                            style: TextStyle(color: AppColors.muted))),
                    Text(DateFormat('d MMM yyyy').format(at),
                        style: const TextStyle(
                            color: AppColors.light, fontSize: 13)),
                    const SizedBox(width: 10),
                    const SoftBadge(
                        label: 'Shift Active',
                        color: AppColors.greenDark,
                        uppercase: true,
                        fontSize: 10.5),
                  ]),
                ),
                const SizedBox(height: 22),
                SurfaceCard(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(children: [
                    Row(children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                              color: AppColors.green, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('SESSION DETAILS',
                            style: TextStyle(
                                color: AppColors.silver,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                      ),
                      const Icon(Icons.sync_rounded,
                          color: AppColors.brand, size: 15),
                      const SizedBox(width: 4),
                      const Text('Live Sync',
                          style: TextStyle(
                              color: AppColors.brand,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, color: AppColors.borderSoft)),
                    _sessionRow(
                        Icons.location_on_outlined,
                        AppColors.greenDark,
                        'Check-in Location',
                        _address ??
                            (_lat != null
                                ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                                : '-'),
                        trailing: _lat != null
                            ? const SoftBadge(
                                label: 'GPS',
                                color: AppColors.greenDark,
                                fontSize: 11)
                            : null),
                    _sessionRow(Icons.schedule_rounded, AppColors.brand,
                        'Shift Started At', DateFormat('h:mm:ss a').format(at)),
                    _sessionRow(
                        Icons.shield_outlined,
                        AppColors.yellow,
                        'Supervisor Visibility',
                        org.isEmpty
                            ? 'Owner / Admin (Live)'
                            : '$org Admin (Live)'),
                  ]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.dark4,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const IconTile(
                            icon: Icons.notifications_none_rounded,
                            color: AppColors.light,
                            background: AppColors.white,
                            size: 32,
                            iconSize: 17,
                            radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              const TextSpan(
                                  text: 'Foreground tracking is active. ',
                                  style: TextStyle(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w700)),
                              TextSpan(
                                  text: Platform.isIOS
                                      ? 'ProofIt shares your location while the app is open.'
                                      : 'ProofIt will keep a persistent notification to ensure reliable location updates.'),
                            ]),
                            style: const TextStyle(
                                color: AppColors.light,
                                fontSize: 13,
                                height: 1.45),
                          ),
                        ),
                      ]),
                ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSoft))),
            child: PrimaryButton(
              label: 'Go to Assigned Jobs',
              trailingIcon: Icons.arrow_forward_rounded,
              color: AppColors.greenDark,
              height: 54,
              onPressed: () => context.pushReplacement('/staff/jobs'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sessionRow(IconData icon, Color color, String title, String value,
          {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(
              icon: icon, color: color, size: 36, iconSize: 18, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: AppColors.silver, fontSize: 12.5)),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      );
}
