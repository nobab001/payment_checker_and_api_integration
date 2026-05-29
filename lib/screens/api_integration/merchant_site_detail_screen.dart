import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/merchant_site.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/merchant_api_repository.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/security_pin_dialog.dart';
import 'checkout_designer_screen.dart';

class MerchantSiteDetailScreen extends StatefulWidget {
  final int siteId;

  const MerchantSiteDetailScreen({super.key, required this.siteId});

  @override
  State<MerchantSiteDetailScreen> createState() =>
      _MerchantSiteDetailScreenState();
}

class _MerchantSiteDetailScreenState extends State<MerchantSiteDetailScreen> {
  final _repo = MerchantApiRepository.instance;
  MerchantSite? _site;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _repo.detail(widget.siteId);
      if (!mounted) return;
      setState(() {
        _site = d.site;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _regenerateKey() async {
    final pin = await promptAccountSecurityPin(
      context,
      title: 'API Key পরিবর্তন',
      message:
          'নতুন API Key তৈরি করতে আপনার অ্যাকাউন্ট Security PIN দিন। পুরনো Key কাজ করা বন্ধ হয়ে যাবে।',
    );
    if (pin == null || !mounted) return;

    try {
      await ApiService.instance.verifyDevicePin(pin);
      final keys = await _repo.regenerateKey(id: widget.siteId, pin: pin);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('নতুন API Key (একবারই)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Key ID: ${keys.apiKeyId}'),
              const SizedBox(height: 8),
              SelectableText(keys.apiSecret),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: keys.apiSecret));
                Navigator.pop(ctx);
              },
              child: const Text('Secret কপি'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ঠিক আছে'),
            ),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.friendlyErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final site = _site;

    return Scaffold(
      appBar: AppBar(
        title: Text(site?.siteName ?? 'সাইট'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : site == null
              ? const Center(child: Text('লোড হয়নি'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _copyRow('Gateway URL', site.gatewayUrl),
                    _copyRow(
                      'System Username',
                      site.gatewayUsername ?? (user?.id.toString() ?? ''),
                    ),
                    _copyRow('API Key ID', site.apiKeyId),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _regenerateKey,
                      icon: const Icon(Icons.refresh),
                      label: const Text('API Key পুনরায় তৈরি (PIN লাগবে)'),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => CheckoutDesignerScreen(
                              merchantId: site.id,
                              siteName: site.siteName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.design_services),
                      label: const Text('View Page / Checkout Designer'),
                    ),
                  ],
                ),
    );
  }

  Widget _copyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SelectableText(value),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label কপি হয়েছে')),
              );
            },
          ),
        ],
      ),
    );
  }
}
