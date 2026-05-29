import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import '../utils/pin_validation.dart';

/// Account security PIN (4–6 digits). Returns null if cancelled.
Future<String?> promptAccountSecurityPin(
  BuildContext context, {
  String title = 'নিরাপত্তা পিন',
  String message = 'অ্যাকাউন্ট খোলার সময় যে পিন সেট করেছিলেন সেটি দিন।',
}) async {
  final ctrl = TextEditingController();
  var obscure = true;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final canOk = canSubmitSecurityPin(ctrl.text);
        return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              obscureText: obscure,
              keyboardType: TextInputType.number,
              maxLength: 7,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Security PIN (৪–৬ সংখ্যা)',
                counterText: '',
                helperText: securityPinLengthHint(ctrl.text),
                helperStyle: TextStyle(
                  color: securityPinDigitCount(ctrl.text) > 6
                      ? Colors.red
                      : Colors.green.shade700,
                  fontSize: 12,
                ),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setLocal(() => obscure = !obscure),
                ),
              ),
              onChanged: (_) => setLocal(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: canOk
                ? () => Navigator.pop(ctx, ctrl.text.trim())
                : null,
            child: const Text('ঠিক আছে'),
          ),
        ],
      );
      },
    ),
  );
}
