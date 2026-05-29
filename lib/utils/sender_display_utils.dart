import 'sender_match_utils.dart';

/// DBBL Rocket inbox short code (stored value for SMS matching).
const String kRocketSenderId = '16216';

/// User-facing label for [kRocketSenderId] on settings chips.
const String kRocketDisplayLabel = 'Rocket';

const Map<String, String> _storageToDisplay = {
  kRocketSenderId: kRocketDisplayLabel,
};

/// Chip / UI label for a stored allowed-sender value.
String displayLabelForStoredSender(String storageValue) =>
    _storageToDisplay[storageValue.trim()] ?? storageValue;

/// Normalizes user input before saving to SharedPreferences.
String canonicalizeAllowedSenderForStorage(String userInput) {
  final trimmed = userInput.trim();
  if (trimmed.isEmpty) return trimmed;

  final norm = normalizeSenderForMatch(trimmed);
  if (norm == 'rocket' || norm == '16216' || norm.contains('dbbl')) {
    return kRocketSenderId;
  }
  return trimmed;
}

/// Maps legacy `Rocket` entries to `16216` and dedupes by normalized form.
List<String> canonicalizeAllowedSenderList(List<String> senders) {
  final out = <String>[];
  for (final raw in senders) {
    final stored = canonicalizeAllowedSenderForStorage(raw);
    if (stored.isEmpty) continue;
    final norm = normalizeSenderForMatch(stored);
    final duplicate = out.any(
      (e) => normalizeSenderForMatch(e) == norm,
    );
    if (!duplicate) out.add(stored);
  }
  return out;
}
