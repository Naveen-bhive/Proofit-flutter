import 'package:flutter/services.dart';

/// Field validators for the owner profile (company name, mobile number, address).
/// Rules mirror the backend (backend/src/utils/orgProfile.js).
class ProfileValidators {
  ProfileValidators._();

  // Indian mobile numbers: 10 digits, first digit 6-9.
  static final _mobileRe = RegExp(r'^[6-9]\d{9}$');

  /// Strips separators and a +91 / 91 / 0 prefix, leaving the 10 local digits.
  static String normalizeMobile(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  static String? companyName(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Company name is required';
    if (t.length < 2) return 'Enter at least 2 characters';
    return null;
  }

  static String? mobile(String? v) {
    final t = normalizeMobile(v ?? '');
    if (t.isEmpty) return 'Mobile number is required';
    if (!_mobileRe.hasMatch(t)) return 'Enter a valid 10-digit mobile number starting with 6, 7, 8 or 9';
    return null;
  }

  static String? address(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Address is required';
    if (t.length < 5) return 'Enter a complete address';
    if (t.length > 300) return 'Address is too long (max 300 characters)';
    return null;
  }
}

/// Keeps a mobile number field to digits only, at most 10 of them. Pasted
/// numbers with +91 / 91 / 0 prefixes are trimmed down to the 10 local digits.
class MobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = ProfileValidators.normalizeMobile(newValue.text);
    if (digits.length > 10) digits = digits.substring(0, 10);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
