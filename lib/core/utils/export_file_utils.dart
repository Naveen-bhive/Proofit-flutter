/// Makes user-provided labels safe to use as a single filename component.
///
/// Company names can contain a slash or another path separator (for example,
/// "A/B Services"). Writing an export with that raw name creates a nested,
/// non-existent directory and makes the download appear to fail.
String exportFileNamePart(String value, {String fallback = 'reports'}) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');

  return sanitized.isEmpty ? fallback : sanitized;
}
