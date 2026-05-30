import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Device already linked to another account — masked contact lines for security.
class DeviceBoundDialog extends StatelessWidget {
  final List<String> phones;
  final List<String> emails;

  const DeviceBoundDialog({
    super.key,
    this.phones = const [],
    this.emails = const [],
  });

  static Future<void> show(
    BuildContext context, {
    List<String> phones = const [],
    List<String> emails = const [],
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeviceBoundDialog(phones: phones, emails: emails),
    );
  }

  /// Replace the 6th, 7th and 8th digits (1-indexed) with `*`.
  /// Formatting characters (+, -, spaces) are preserved.
  static String _maskPhone(String raw) {
    int digitCount = 0;
    final buffer = StringBuffer();
    for (final ch in raw.split('')) {
      final isDigit = ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
      if (isDigit) {
        digitCount++;
        if (digitCount == 6 || digitCount == 7 || digitCount == 8) {
          buffer.write('*');
          continue;
        }
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }

  /// Mask 3-4 characters in the middle of the local part with `*`;
  /// everything else stays fully visible.
  static String _maskEmail(String raw) {
    final at = raw.indexOf('@');
    if (at == -1) return raw;
    final local = raw.substring(0, at);
    final domain = raw.substring(at);
    final len = local.length;

    if (len <= 4) {
      if (len <= 1) return '***$domain';
      if (len <= 3) return '${local[0]}${'*' * (len - 1)}$domain';
      return '${local[0]}***${local[len - 1]}$domain';
    }

    final maskCount = len >= 10 ? 4 : 3;
    final start = (len - maskCount) ~/ 2;
    final prefix = local.substring(0, start);
    final suffix = local.substring(start + maskCount);
    return '$prefix${'*' * maskCount}$suffix$domain';
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(
      fontSize: 14,
      height: 1.5,
      color: Color(0xFF37474F),
    );

    const hPad = 20.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(hPad, 44, hPad, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ডিভাইস যাচাই ব্যর্থ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'আপনার এই ডিভাইসটি',
                    textAlign: TextAlign.center,
                    style: bodyStyle,
                  ),
                  ...phones.map(
                    (p) => Text(
                      _maskPhone(p),
                      textAlign: TextAlign.center,
                      style: bodyStyle,
                    ),
                  ),
                  ...emails.map(
                    (e) => Text(
                      _maskEmail(e),
                      textAlign: TextAlign.center,
                      style: bodyStyle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'অ্যাকাউন্টের সাথে লিংক করা রয়েছে।',
                    textAlign: TextAlign.left,
                    style: bodyStyle,
                  ),
                  const Text(
                    'অর্থাৎ আপনি নতুন কোনো অ্যাকাউন্ট করতে পারবেন না।',
                    textAlign: TextAlign.left,
                    style: bodyStyle,
                  ),
                  const Text(
                    'আপনাকে আপনার আগের অ্যাকাউন্টটি ব্যবহার করতে হবে।',
                    textAlign: TextAlign.left,
                    style: bodyStyle,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.grey.shade600),
                tooltip: 'বন্ধ করুন',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
