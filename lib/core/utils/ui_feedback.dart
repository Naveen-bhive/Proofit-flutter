import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'api_error_utils.dart';

void showErrorSnackBar(
  BuildContext context,
  dynamic error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(friendlyErrorMessage(error, fallback: fallback)),
      backgroundColor: AppColors.red,
    ),
  );
}
