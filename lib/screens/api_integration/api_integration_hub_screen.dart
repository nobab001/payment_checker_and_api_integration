import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/merchant_site.dart';
import '../../repositories/merchant_api_repository.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import 'checkout_designer_screen.dart';
import 'merchant_site_detail_screen.dart';

class ApiIntegrationHubScreen extends StatefulWidget {
  const ApiIntegrationHubScreen({super.key});

  @override
  State<ApiIntegrationHubScreen> createState() =>
      _ApiIntegrationHubScreenState();
}

class _ApiIntegrationHubScreenState extends State<ApiIntegrationHubScreen> {
  final _repo = MerchantApiRepository.instance;
  List<MerchantSite> _sites = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.list();
      if (!mounted) return;
      setState(() {
        _sites = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.friendlyErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _addSite() async {
    final nameCtrl = TextEditingController();
    final domainCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('নতুন ওয়েবসাইট যোগ করুন'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'সাইটের নাম (যেমন Daraz)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: domainCtrl,
              decoration: const InputDecoration(
                labelText: 'ডোমেইন (যেমন daraz.com)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('যোগ করুন'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final created = await _repo.create(
        siteName: nameCtrl.text.trim(),
        domainAddress: domainCtrl.text.trim(),
      );
      if (created.apiSecretOnce != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('API Secret (একবারই দেখানো হবে)'),
            content: SelectableText(created.apiSecretOnce!),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: created.apiSecretOnce!),
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('কপি'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ঠিক আছে'),
              ),
            ],
          ),
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _toggleActive(MerchantSite site, bool v) async {
    try {
      await _repo.setActive(site.id, v);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Integration'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSite,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('আবার চেষ্টা'),
                        ),
                      ],
                    ),
                  ),
                )
              : _sites.isEmpty
                  ? const Center(
                      child: Text(
                        'কোনো সাইট যোগ করা হয়নি। + বাটনে Daraz/Alibaba যোগ করুন।',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          const Text(
                            'ওয়েবসাইটসমূহ (Merchant Sites)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final s in _sites)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(s.siteName),
                                subtitle: Text(
                                  '${s.domainAddress}\n${s.gatewayUrl}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                isThreeLine: true,
                                trailing: Switch(
                                  value: s.isActive,
                                  onChanged: (v) => _toggleActive(s, v),
                                ),
                                onTap: () async {
                                  await Navigator.push<void>(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          MerchantSiteDetailScreen(siteId: s.id),
                                    ),
                                  );
                                  await _load();
                                },
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 650,
                            child: CheckoutDesignerScreen(
                              merchantId: _sites.first.id,
                              siteName: _sites.first.siteName,
                              isEmbedded: true,
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
