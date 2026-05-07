import '../models/sms_record.dart';

class SmsParser {
  static final _amountRx = RegExp(
    r'(?:Tk|BDT|৳)\s*([\d,]+\.?\d*)|([\d,]+\.?\d*)\s*(?:Tk|BDT|টাকা)',
    caseSensitive: false,
  );

  static final _balanceRx = RegExp(
    r'[Bb]alance[:\s]*(?:Tk|BDT)?\s*([\d,]+\.?\d*)|ব্যালেন্স[:\s]*([\d,]+\.?\d*)',
    caseSensitive: false,
  );

  static String detectSender(String address) {
    final a = address.toLowerCase();
    if (a.contains('bkash')) return 'bKash';
    if (a.contains('nagad')) return 'Nagad';
    if (a.contains('rocket') || a.contains('dbbl')) return 'Rocket';
    if (a.contains('upay') || a.contains('ucb')) return 'Upay';
    return '';
  }

  static bool isValidSender(String address) {
    final a = address.toLowerCase();
    return a.contains('bkash') ||
        a.contains('nagad') ||
        a.contains('rocket') ||
        a.contains('dbbl') ||
        a.contains('upay') ||
        a.contains('ucb');
  }

  static double extractAmount(String body) {
    final m = _amountRx.firstMatch(body);
    if (m == null) return 0.0;
    final raw = (m.group(1) ?? m.group(2) ?? '0').replaceAll(',', '');
    return double.tryParse(raw) ?? 0.0;
  }

  static String extractBalance(String body) {
    final matches = _balanceRx.allMatches(body).toList();
    if (matches.isNotEmpty) {
      final last = matches.last;
      return (last.group(1) ?? last.group(2) ?? '0').replaceAll(',', '');
    }
    // Fallback: last Tk amount in message is likely the balance
    final allAmounts = _amountRx.allMatches(body).toList();
    if (allAmounts.isEmpty) return '0';
    final last = allAmounts.last;
    return (last.group(1) ?? last.group(2) ?? '0').replaceAll(',', '');
  }

  static String detectType(String body) {
    final b = body.toLowerCase();
    if (b.contains('received') ||
        b.contains('credited') ||
        b.contains('পেয়েছেন')) {
      return 'recv';
    }
    if (b.contains('sent') ||
        b.contains('payment') ||
        b.contains('পাঠিয়েছেন') ||
        b.contains('deducted')) {
      return 'send';
    }
    if (b.contains('cash out') ||
        b.contains('cashout') ||
        b.contains('withdraw')) {
      return 'out';
    }
    if (b.contains('add money') ||
        b.contains('cash in') ||
        b.contains('recharge')) {
      return 'in';
    }
    if (b.contains('request')) { return 'req'; }
    return 'txn';
  }

  static String typeLabel(String tp) {
    const labels = {
      'recv': 'Received',
      'send': 'Sent',
      'out': 'Cash Out',
      'in': 'Cash In',
      'req': 'Request',
      'txn': 'Transaction',
    };
    return labels[tp] ?? 'Transaction';
  }

  /// bKash/Nagad-style Trx / Txn IDs in SMS body.
  static String? extractTransactionId(String body) {
    final patterns = [
      RegExp(r'(?:TrxID|Transaction\s*ID|Txn\s*ID|Trx\s*[:\s]+)\s*[:\s]*([A-Z0-9]{6,})',
          caseSensitive: false),
      RegExp(r'(?:ট্রানজেকশন\s*আইডি|লেনদেন\s*আইডি)[:\s]*([A-Z0-9]{6,})',
          caseSensitive: false),
    ];
    for (final rx in patterns) {
      final m = rx.firstMatch(body);
      if (m != null && m.groupCount >= 1) {
        final id = m.group(1)?.trim();
        if (id != null && id.isNotEmpty) return id.toUpperCase();
      }
    }
    return null;
  }

  /// First Bangladesh mobile 11-digit number in body, or null.
  static String? extractBdMobile(String body) {
    final m = RegExp(r'\b01[3-9]\d{8}\b').firstMatch(body);
    return m?.group(0);
  }

  /// `01912345678` → `019XXXXXXXX`
  static String maskBdMobile(String phone) {
    if (phone.length < 11) return phone;
    return '${phone.substring(0, 3)}XXXXXXXX';
  }

  /// One-line summary: "Received 500 Tk from 019XXXXXXXX"
  static String historyTitleLine(SmsRecord r) {
    final tp = typeLabel(r.tp);
    final amt = r.am == r.am.roundToDouble()
        ? r.am.toStringAsFixed(0)
        : r.am.toStringAsFixed(2);
    final raw = extractBdMobile(r.m);
    final from = raw != null ? maskBdMobile(raw) : r.s;
    return '$tp $amt Tk from $from';
  }
}
