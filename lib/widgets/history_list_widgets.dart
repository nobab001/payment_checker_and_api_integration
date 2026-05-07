import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sms_record.dart';
import '../providers/sms_provider.dart';
import '../utils/sms_parser.dart';

String historyDeviceLabel() {
  if (kIsWeb) return 'Web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.iOS:
      return 'iOS';
    case TargetPlatform.linux:
      return 'Linux';
    case TargetPlatform.macOS:
      return 'macOS';
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.fuchsia:
      return 'Fuchsia';
  }
}

class HistoryListEmptyState extends StatelessWidget {
  final bool hasRecords;
  final VoidCallback onImport;

  const HistoryListEmptyState({
    super.key,
    required this.hasRecords,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    if (hasRecords) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'কোনো SMS মেলেনি',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'অন্য কীওয়ার্ড দিয়ে খুঁজুন',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            'কোনো SMS রেকর্ড নেই',
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.sync),
            label: const Text('ইনবক্স থেকে আনুন'),
          ),
        ],
      ),
    );
  }
}

class SmsHistoryListTile extends StatelessWidget {
  final SmsRecord record;

  const SmsHistoryListTile({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final sms = context.watch<SmsProvider>();
    final sold = sms.isSoldOut(record);
    final trx = SmsParser.extractTransactionId(record.m) ?? '—';
    final subtitle = 'TrxID: $trx | Device: ${historyDeviceLabel()}';
    final dateFmt = DateFormat('d MMM, h:mm a');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
      elevation: sold ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: sold ? Colors.red.shade300 : Colors.grey.shade200,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        tileColor: sold ? Colors.red[100] : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        title: Text(
          SmsParser.historyTitleLine(record),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: sold ? Colors.red.shade900 : Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateFmt.format(record.time),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: sold ? Colors.grey : Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            elevation: sold ? 0 : 2,
          ),
          onPressed: () => sms.toggleSoldOut(record),
          child: Text(
            sold ? 'SOLDOUT' : 'CHECK',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
