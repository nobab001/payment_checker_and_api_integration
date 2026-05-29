/// Digits only, length for live button state.
int securityPinDigitCount(String pin) =>
    pin.replaceAll(RegExp(r'\D'), '').length;

/// Submit enabled at 4–6 digits; disabled below 4 or at 7+.
bool canSubmitSecurityPin(String pin) {
  final n = securityPinDigitCount(pin);
  return n >= 4 && n <= 6;
}

/// Account security PIN: 4–6 digits only.
bool isValidSecurityPin(String pin) {
  final p = pin.trim();
  return RegExp(r'^\d{4,6}$').hasMatch(p);
}

/// Hint under the field while typing.
String? securityPinLengthHint(String pin) {
  final n = securityPinDigitCount(pin);
  if (n == 0) return null;
  if (n < 4) return 'আরো ${4 - n} সংখ্যা (মোট ৪–৬)';
  if (n > 6) return '৬ সংখ্যার বেশি হবে না';
  return 'পিন ঠিক আছে ($n সংখ্যা)';
}

String? validateSecurityPin(String? value, {bool required = true}) {
  final p = value?.trim() ?? '';
  if (p.isEmpty) {
    return required ? 'পিন দিন' : null;
  }
  if (!isValidSecurityPin(p)) {
    return 'পিন ৪ থেকে ৬ সংখ্যার হতে হবে (শুধু সংখ্যা)';
  }
  return null;
}
