import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/auth_provider.dart';
import '../services/payment_service.dart';
import '../utils/constants.dart';

/// Load bKash checkout (VPS API) and complete wallet top-up on success.
class PaymentGatewayScreen extends StatefulWidget {
  const PaymentGatewayScreen({super.key});

  @override
  State<PaymentGatewayScreen> createState() => _PaymentGatewayScreenState();
}

class _PaymentGatewayScreenState extends State<PaymentGatewayScreen> {
  final _amountCtrl = TextEditingController(text: '100');
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted);

  bool _busy = false;
  String? _error;
  WalletTopUpStart? _session;
  int _nav = 0;
  bool _completionDone = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  String? _paymentIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return uri.queryParameters['paymentID'] ??
        uri.queryParameters['paymentId'] ??
        uri.queryParameters['payment_id'];
  }

  Future<void> _maybeComplete(String url) async {
    final pid = _paymentIdFromUrl(url);
    if (pid == null || pid.isEmpty) return;
    final sess = _session;
    if (sess == null || _completionDone) return;
    _completionDone = true;
    setState(() => _busy = true);
    try {
      await PaymentService.instance.completeWalletTopUp(
        pendingId: sess.pendingId,
        paymentID: pid,
      );
      if (!mounted) return;
      await context.read<AuthProvider>().refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ওয়ালেটে টাকা যোগ হয়েছে'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _completionDone = false;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startCheckout() async {
    if (context.read<AuthProvider>().user == null) {
      setState(() => _error = 'লগইন প্রয়োজন');
      return;
    }
    final raw = double.tryParse(_amountCtrl.text.trim());
    if (raw == null || raw < 10) {
      setState(() => _error = 'কমপক্ষে ৳১০ দিন');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await PaymentService.instance.startWalletTopUp(raw);
      if (!mounted) return;
      _completionDone = false;
      _session = start;
      _web
        ..setNavigationDelegate(
          NavigationDelegate(
            onUrlChange: (UrlChange change) {
              final u = change.url;
              if (u != null) _maybeComplete(u);
            },
            onNavigationRequest: (request) {
              _maybeComplete(request.url);
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(start.bkashURL));
      setState(() {
        _busy = false;
        _nav = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final fmt = NumberFormat('#,##0.00', 'en');
    final bal = user?.balance ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add balance (bKash)'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('লগইন প্রয়োজন'))
          : _nav == 0
              ? _amountStep(context, fmt, bal)
              : Stack(
                  children: [
                    WebViewWidget(controller: _web),
                    if (_busy)
                      const ColoredBox(
                        color: Colors.black38,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
    );
  }

  Widget _amountStep(BuildContext context, NumberFormat fmt, double bal) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'বর্তমান ওয়ালেট: ৳ ${fmt.format(bal)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'SMS ইনবক্সের ব্যালেন্স আলাদা। এখানে টাকা যোগ করলে সাবস্ক্রিপশন ও প্রিমিয়াম ফিচার কেনা যাবে।',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.35),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'টাকার পরিমাণ (BDT)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _startCheckout,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('bKash দিয়ে পেমেন্ট করুন'),
        ),
        const SizedBox(height: 16),
        const Text(
          'পেমেন্ট শেষ হলে পেজ স্বয়ংক্রিয়ভাবে সম্পন্ন করার চেষ্টা করবে। '
          'না হলে আবার চেষ্টা করুন বা সহায়তা নিন।',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
