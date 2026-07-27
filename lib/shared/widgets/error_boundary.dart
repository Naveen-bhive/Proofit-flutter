import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  const ErrorBoundary({super.key, required this.child});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.dark,
        body: SafeArea(child: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.error_outline, color: AppColors.red, size: 40),
            ),
            const SizedBox(height: 20),
            const Text('Something went wrong', style: TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text(
              'The app hit an unexpected error.\nPlease restart to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.silver, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => setState(() => _error = null),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                minimumSize: const Size(180, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ]),
        ))),
      );
    }
    return widget.child;
  }
}

// Global error handler — catches unhandled Flutter errors
class AppErrorHandler {
  static void init() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      // In production: send to crash reporting (Sentry, Firebase Crashlytics)
      debugPrint('Flutter error: ${details.exception}');
      debugPrint('Stack: ${details.stack}');
    };
  }
}