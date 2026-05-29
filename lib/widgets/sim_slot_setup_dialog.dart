import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Polite Bengali guidance when SIM slot cannot be turned on yet.
class SimSlotSetupDialog {
  SimSlotSetupDialog._();

  static const _sim1Message =
      'অনুগ্রহ করে প্রথমে আপনার মোবাইলের ১ নম্বর সিমের সঠিক নাম্বারটি বসান। এরপর নিচে থেকে যেকোনো একটি সেন্ডার আইডি সিলেক্ট করুন অথবা প্লাস (+) আইকনে ক্লিক করে নিজের মতো একটি সেন্ডার আইডি তৈরি করুন। এই ধাপগুলো সম্পন্ন করার পরেই কেবল সিম ১-এর এসএমএস সার্ভিসটি চালু করতে পারবেন এবং অ্যাপটি স্বয়ংক্রিয়ভাবে এসএমএস স্ক্যান করা শুরু করবে।';

  static const _sim2Message =
      'অনুগ্রহ করে প্রথমে আপনার মোবাইলের ২ নম্বর সিমের সঠিক নাম্বারটি বসান। এরপর নিচে থেকে যেকোনো একটি সেন্ডার আইডি সিলেক্ট করুন অথবা প্লাস (+) আইকনে ক্লিক করে নিজের মতো একটি সেন্ডার আইডি তৈরি করুন। এই ধাপগুলো সম্পন্ন করার পরেই কেবল সিম ২-এর এসএমএস সার্ভিসটি চালু করতে পারবেন এবং অ্যাপটি স্বয়ংক্রিয়ভাবে এসএমএস স্ক্যান করা শুরু করবে।';

  static Future<void> show(BuildContext context, {required int simSlot}) {
    final title = simSlot == 1 ? 'সিম ১ সেটআপ' : 'সিম ২ সেটআপ';
    final message = simSlot == 1 ? _sim1Message : _sim2Message;

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.sim_card_alert_outlined, color: AppColors.primary, size: 40),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('বুঝেছি'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
