import 'dart:math';

const String base36Chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

String generateStandardCode() {
  final random = Random();
  String code = '';
  for (int i = 0; i < 7; i++) {
    code += base36Chars[random.nextInt(base36Chars.length)];
  }
  return code;
}

String generateVanityCode() {
  final random = Random();
  String randomPart = '';
  for (int i = 0; i < 3; i++) {
    randomPart += base36Chars[random.nextInt(base36Chars.length)];
  }
  final insertPos = random.nextInt(4);
  return '${randomPart.substring(0, insertPos)}bqopd${randomPart.substring(insertPos)}';
}

Future<String?> assignShortcodeLogic({
  required Future<bool> Function(String dbKey) checkUniqueness,
  required Future<void> Function(String dbKey, String displayCode) saveToDb,
  bool isVanity = false,
}) async {
  String displayCode;
  String dbKey;
  bool isUnique = false;
  int retries = 0;
  const int maxRetries = 10;

  while (!isUnique && retries < maxRetries) {
    displayCode = isVanity ? generateVanityCode() : generateStandardCode();
    dbKey = displayCode.toUpperCase();

    isUnique = await checkUniqueness(dbKey);

    if (isUnique) {
      await saveToDb(dbKey, displayCode);
      return displayCode;
    }
    retries++;
  }

  if (retries >= maxRetries) {
    throw Exception('Failed to generate a unique shortcode after $maxRetries retries.');
  }
  return null;
}