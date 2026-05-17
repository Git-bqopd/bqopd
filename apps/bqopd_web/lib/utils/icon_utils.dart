/// Utility to clean up Flutter icon names for Material Symbols compatibility on the web.
String cleanIconName(String iconName) {
  final cleaned = iconName
      .replaceAll('_outlined', '')
      .replaceAll('_outline', '')
      .replaceAll('_border', '')
      .replaceAll('_filled', '');

  // Aligns 'settings' with Flutter's 'all_inclusive' (infinity symbol) representation
  if (cleaned == 'settings') {
    return 'all_inclusive';
  }
  return cleaned;
}