/// Normalizes sender IDs / phone numbers for comparison.
///
/// Removes spaces and hyphens, lowercases — so `01931666777` matches
/// `01931-666777` and `BKASH` matches `b-Kash`.
String normalizeSenderForMatch(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');
}

/// True when normalized [address] matches any [allowedSenders] entry (substring either way).
bool senderAddressMatchesAllowed(String? address, List<String> allowedSenders) {
  if (allowedSenders.isEmpty) return false;
  final normalizedAddress = normalizeSenderForMatch(address ?? '');
  if (normalizedAddress.isEmpty) return false;

  for (final sender in allowedSenders) {
    final key = normalizeSenderForMatch(sender);
    if (key.isEmpty) continue;
    if (normalizedAddress.contains(key) || key.contains(normalizedAddress)) {
      return true;
    }
  }
  return false;
}
