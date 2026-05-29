import 'package:flutter/material.dart';

import '../../models/checkout_layout.dart';
import '../../repositories/merchant_api_repository.dart';
import '../../repositories/sim_filter_local_repository.dart';
import '../../services/api_service.dart';
import '../../utils/checkout_sim_sources.dart';
import '../../utils/constants.dart';

class CheckoutDesignerScreen extends StatefulWidget {
  final int merchantId;
  final String siteName;

  const CheckoutDesignerScreen({
    super.key,
    required this.merchantId,
    required this.siteName,
  });

  @override
  State<CheckoutDesignerScreen> createState() => _CheckoutDesignerScreenState();
}

class _CheckoutDesignerScreenState extends State<CheckoutDesignerScreen> {
  final _repo = MerchantApiRepository.instance;
  CheckoutLayout _layout = CheckoutLayout.empty();
  List<CheckoutSimSource> _sources = [];
  final Map<String, TextEditingController> _titleControllers = {};
  bool _previewMode = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final ctrl in _titleControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final prefs = await SimFilterLocalRepository.instance.loadSettings();
      final detail = await _repo.detail(widget.merchantId);
      if (!mounted) return;
      for (final id in detail.layout.blockOrder) {
        _titleControllers[id] = TextEditingController(text: detail.layout.blocks[id]?.title ?? '');
      }
      setState(() {
        _sources = buildCheckoutSimSources(prefs);
        _layout = detail.layout;
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repo.saveLayout(widget.merchantId, _layout);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checkout লেআউট সেভ হয়েছে'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.friendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reorderBlocks(int oldIndex, int newIndex) {
    if (_previewMode) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final order = List<String>.from(_layout.blockOrder);
      final item = order.removeAt(oldIndex);
      order.insert(newIndex, item);
      _layout = CheckoutLayout(
        version: _layout.version,
        blockOrder: order,
        blocks: _layout.blocks,
      );
    });
  }

  void _reorderNumbers(String blockId, int oldIndex, int newIndex) {
    if (_previewMode) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final block = _layout.blocks[blockId]!;
      final nums = List<CheckoutNumberSlot>.from(block.numbers);
      final item = nums.removeAt(oldIndex);
      nums.insert(newIndex, item);
      for (var i = 0; i < nums.length; i++) {
        nums[i] = nums[i].copyWith(position: i + 1);
      }
      _layout = CheckoutLayout(
        version: _layout.version,
        blockOrder: _layout.blockOrder,
        blocks: {
          ..._layout.blocks,
          blockId: CheckoutBlockConfig(
            id: blockId,
            title: block.title,
            numbers: nums,
          ),
        },
      );
    });
  }

  void _toggleSource(String blockId, CheckoutSimSource src, bool on) {
    if (_previewMode) return;
    if (on) {
      final block = _layout.blocks[blockId];
      if (block != null && block.numbers.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('একটি ব্লকে সর্বোচ্চ ৫টি নম্বর বসানো যাবে।'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }
    setState(() {
      final block = _layout.blocks[blockId]!;
      var nums = List<CheckoutNumberSlot>.from(block.numbers);
      if (on) {
        if (!nums.any((n) => n.simSlot == src.simSlot && n.phone == src.phone)) {
          nums.add(CheckoutNumberSlot(
            simSlot: src.simSlot,
            phone: src.phone,
            enabled: true,
            position: nums.length + 1,
          ));
        }
      } else {
        nums.removeWhere(
          (n) => n.simSlot == src.simSlot && n.phone == src.phone,
        );
        for (var i = 0; i < nums.length; i++) {
          nums[i] = nums[i].copyWith(position: i + 1);
        }
      }
      _layout = CheckoutLayout(
        version: _layout.version,
        blockOrder: _layout.blockOrder,
        blocks: {
          ..._layout.blocks,
          blockId: CheckoutBlockConfig(
            id: blockId,
            title: block.title,
            numbers: nums,
          ),
        },
      );
    });
  }

  bool _isSourceOn(String blockId, CheckoutSimSource src) {
    final nums = _layout.blocks[blockId]?.numbers ?? [];
    return nums.any(
      (n) => n.simSlot == src.simSlot && n.phone == src.phone && n.enabled,
    );
  }

  String _getFriendlyBlockName(String blockId) {
    switch (blockId) {
      case 'bkash_personal':
        return 'বিকাশ পার্সোনাল';
      case 'nagad_personal':
        return 'নগদ পার্সোনাল';
      case 'rocket_personal':
        return 'রকেট পার্সোনাল';
      case 'upay_personal':
        return 'উপায় পার্সোনাল';
      case 'bkash_agent':
        return 'বিকাশ এজেন্ট';
      case 'nagad_agent':
        return 'নগদ এজেন্ট';
      case 'bank_accounts':
        return 'ব্যাংক অ্যাকাউন্টস';
      default:
        return blockId;
    }
  }

  void _showBankDialog(String blockId, {int? indexToEdit}) {
    final block = _layout.blocks[blockId]!;
    final enabledNums = block.numbers.where((n) => n.enabled).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final isEditing = indexToEdit != null;
    final editSlot = isEditing ? enabledNums[indexToEdit] : null;

    final bankCtrl = TextEditingController(text: editSlot?.bankName ?? '');
    final nameCtrl = TextEditingController(text: editSlot?.accountName ?? '');
    final branchCtrl = TextEditingController(text: editSlot?.branch ?? '');
    final numCtrl = TextEditingController(text: editSlot?.phone ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEditing ? 'ব্যাংক অ্যাকাউন্ট পরিবর্তন' : 'নতুন ব্যাংক অ্যাকাউন্ট যোগ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bankCtrl,
                decoration: const InputDecoration(labelText: 'ব্যাংকের নাম (যেমন DBBL)'),
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'অ্যাকাউন্ট নাম (যেমন John Doe)'),
              ),
              TextField(
                controller: branchCtrl,
                decoration: const InputDecoration(labelText: 'শাখা (যেমন Motijheel)'),
              ),
              TextField(
                controller: numCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'অ্যাকাউন্ট নম্বর'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () {
              final bankName = bankCtrl.text.trim();
              final accountName = nameCtrl.text.trim();
              final branch = branchCtrl.text.trim();
              final phone = numCtrl.text.trim();

              if (bankName.isEmpty || phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ব্যাংকের নাম এবং অ্যাকাউন্ট নম্বর বাধ্যতামূলক')),
                );
                return;
              }

              setState(() {
                var nums = List<CheckoutNumberSlot>.from(block.numbers);
                if (isEditing) {
                  final idx = nums.indexWhere(
                    (n) => n.phone == editSlot!.phone && n.bankName == editSlot.bankName,
                  );
                  if (idx != -1) {
                    nums[idx] = CheckoutNumberSlot(
                      simSlot: editSlot!.simSlot,
                      phone: phone,
                      enabled: true,
                      position: editSlot.position,
                      bankName: bankName,
                      accountName: accountName,
                      branch: branch,
                      accountNumber: phone,
                    );
                  }
                } else {
                  if (nums.where((n) => n.enabled).length >= 5) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('একটি ব্লকে সর্বোচ্চ ৫টি নম্বর বসানো যাবে।')),
                    );
                    Navigator.pop(ctx);
                    return;
                  }
                  nums.add(CheckoutNumberSlot(
                    simSlot: 1,
                    phone: phone,
                    enabled: true,
                    position: nums.length + 1,
                    bankName: bankName,
                    accountName: accountName,
                    branch: branch,
                    accountNumber: phone,
                  ));
                }

                _layout = CheckoutLayout(
                  version: _layout.version,
                  blockOrder: _layout.blockOrder,
                  blocks: {
                    ..._layout.blocks,
                    blockId: CheckoutBlockConfig(
                      id: blockId,
                      title: block.title,
                      numbers: nums,
                    ),
                  },
                );
              });
              Navigator.pop(ctx);
            },
            child: Text(isEditing ? 'পরিবর্তন করুন' : 'যোগ করুন'),
          ),
        ],
      ),
    );
  }

  void _deleteBank(String blockId, int indexToDelete) {
    final block = _layout.blocks[blockId]!;
    final enabledNums = block.numbers.where((n) => n.enabled).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final deleteSlot = enabledNums[indexToDelete];

    setState(() {
      var nums = List<CheckoutNumberSlot>.from(block.numbers);
      nums.removeWhere((n) => n.phone == deleteSlot.phone && n.bankName == deleteSlot.bankName);
      for (var i = 0; i < nums.length; i++) {
        nums[i] = nums[i].copyWith(position: i + 1);
      }

      _layout = CheckoutLayout(
        version: _layout.version,
        blockOrder: _layout.blockOrder,
        blocks: {
          ..._layout.blocks,
          blockId: CheckoutBlockConfig(
            id: blockId,
            title: block.title,
            numbers: nums,
          ),
        },
      );
    });
  }

  IconData _getOperatorIcon(String blockId) {
    if (blockId == 'bank_accounts') return Icons.account_balance;
    return Icons.phone_android;
  }

  Color _getOperatorColor(String blockId) {
    if (blockId.startsWith('bkash')) return const Color(0xFFD12053);
    if (blockId.startsWith('nagad')) return const Color(0xFFF37021);
    if (blockId.startsWith('rocket')) return const Color(0xFF8C3494);
    if (blockId.startsWith('upay')) return const Color(0xFF005A9C);
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Checkout — ${widget.siteName}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (!_loading && !_saving)
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save),
              tooltip: 'সেভ',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Edit Mode')),
                      ButtonSegment(value: true, label: Text('Customer Preview')),
                    ],
                    selected: {_previewMode},
                    onSelectionChanged: (s) {
                      setState(() => _previewMode = s.first);
                    },
                  ),
                ),
                Expanded(
                  child: _previewMode ? _buildCustomerPreview() : _buildEditMode(),
                ),
              ],
            ),
    );
  }

  Widget _buildCustomerPreview() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.siteName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E),
            ),
          ),
          const SizedBox(height: 12),
          for (final blockId in _layout.blockOrder) ...[
            _buildCustomerBlock(blockId),
          ],
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ট্রানজেকশন আইডি (TrxID)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF333333)),
                  ),
                  const SizedBox(height: 6),
                  const TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: 'TrxID লিখুন',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'টাকার পরিমাণ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF333333)),
                  ),
                  const SizedBox(height: 6),
                  const TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: '1250',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'অর্ডার নম্বর (ঐচ্ছিক)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF333333)),
                  ),
                  const SizedBox(height: 6),
                  const TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: 'ORDER-123',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      disabledBackgroundColor: const Color(0xFF1A237E).withAlpha(150),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'পেমেন্ট যাচাই করুন',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerBlock(String blockId) {
    final block = _layout.blocks[blockId]!;
    final numbers = block.numbers.where((n) => n.enabled).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    if (numbers.isEmpty && blockId != 'bank_accounts') {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 10),
            if (numbers.isEmpty)
              const Text(
                'কোনো নম্বর ম্যাপ করা হয়নি।',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final n in numbers) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _getOperatorIcon(blockId),
                            color: _getOperatorColor(blockId),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              blockId == 'bank_accounts'
                                  ? [
                                      n.bankName,
                                      n.accountName,
                                      n.branch,
                                      n.phone,
                                    ].where((e) => (e ?? '').isNotEmpty).join(' — ')
                                  : n.phone,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditMode() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _layout.blockOrder.length,
      onReorder: _reorderBlocks,
      itemBuilder: (context, index) {
        final blockId = _layout.blockOrder[index];
        final block = _layout.blocks[blockId]!;
        final blockSources = sourcesForBlock(_sources, blockId);
        final enabledNums = block.numbers
            .where((n) => n.enabled)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));

        return Card(
          key: ValueKey(blockId),
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            initiallyExpanded: index < 2,
            title: Text(
              _getFriendlyBlockName(blockId),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.primary,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: TextField(
                  controller: _titleControllers[blockId],
                  decoration: const InputDecoration(
                    labelText: 'ব্লক শিরোনাম (Title)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    _layout.blocks[blockId] = CheckoutBlockConfig(
                      id: blockId,
                      title: val,
                      numbers: _layout.blocks[blockId]!.numbers,
                    );
                  },
                ),
              ),
              const Divider(),
              if (blockId == 'bank_accounts') ...[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showBankDialog(blockId),
                        icon: const Icon(Icons.add),
                        label: const Text('নতুন ব্যাংক অ্যাকাউন্ট যোগ করুন'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ] else if (blockSources.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'নম্বর ম্যাপ করুন (Device Settings থেকে)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...blockSources.map((src) {
                        return SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'SIM ${src.simSlot}: ${src.phone}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(src.providerTag, style: const TextStyle(fontSize: 11)),
                          value: _isSourceOn(blockId, src),
                          onChanged: (v) => _toggleSource(blockId, src, v),
                        );
                      }),
                    ],
                  ),
                ),
                const Divider(),
              ],
              if (enabledNums.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'কোনো নম্বর যোগ করা হয়নি',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text(
                    'নম্বরগুলোর সিরিয়াল সাজান (চেপে ধরে ড্র্যাগ করুন)',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: enabledNums.length,
                  onReorder: (o, n) => _reorderNumbers(blockId, o, n),
                  itemBuilder: (ctx, ni) {
                    final n = enabledNums[ni];
                    final label = blockId == 'bank_accounts'
                        ? [
                            n.bankName,
                            n.accountName,
                            n.branch,
                            n.phone,
                          ].where((e) => (e ?? '').isNotEmpty).join(' — ')
                        : n.phone;
                    return ListTile(
                      key: ValueKey('$blockId-${n.simSlot}-${n.phone}-$ni'),
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: AppColors.primary.withAlpha(30),
                        child: Text(
                          '${n.position}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                      title: Text(
                        label,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      subtitle: blockId == 'bank_accounts' ? null : Text('SIM ${n.simSlot}', style: const TextStyle(fontSize: 10)),
                      trailing: blockId == 'bank_accounts'
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () => _showBankDialog(blockId, indexToEdit: ni),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  onPressed: () => _deleteBank(blockId, ni),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }}
