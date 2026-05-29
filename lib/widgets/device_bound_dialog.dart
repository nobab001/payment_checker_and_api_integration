import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Device already linked to another account — plain text lines for contacts.
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
                (p) => Text(p, textAlign: TextAlign.center, style: bodyStyle),
              ),
              ...emails.map(
                (e) => Text(e, textAlign: TextAlign.center, style: bodyStyle),
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
