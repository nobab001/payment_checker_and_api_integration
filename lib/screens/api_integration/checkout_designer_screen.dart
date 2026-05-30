import 'package:flutter/material.dart';

import '../../constants/checkout_blocks.dart';
import '../../models/checkout_layout.dart';
import '../../models/device_model.dart';
import '../../repositories/merchant_api_repository.dart';
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

  List<CheckoutSimSource> _buildActiveDevicesSimSources(List<DeviceModel> devices) {
    final out = <CheckoutSimSource>[];
    for (final device in devices) {
      if (!device.isActiveDevice) continue;
      final sims = device.simSettings;
      if (sims == null) continue;

      void addSlot(int slot, String? number, List<String> tags, bool active) {
        final phone = (number ?? '').trim();
        if (!active || phone.length < 11) return;
        for (final tag in tags) {
          final blockId = CheckoutBlocks.blockIdForProviderTag(tag);
          if (blockId == null) continue;
          out.add(CheckoutSimSource(
            simSlot: slot,
            phone: phone,
            providerTag: tag,
            blockId: blockId,
          ));
        }
      }

      addSlot(1, device.sim1Number, sims.sim1.filters, sims.sim1.isEnabled);
      addSlot(2, device.sim2Number, sims.sim2.filters, sims.sim2.isEnabled);
    }
    return out;
  }

  List<CheckoutNumberSlot> _buildActiveDevicesBankAccounts(List<DeviceModel> devices) {
    final out = <CheckoutNumberSlot>[];
    for (final device in devices) {
      if (!device.isActiveDevice) continue;
      final sims = device.simSettings;
      if (sims == null) continue;
      out.addAll(sims.bankAccounts);
    }
    // Deduplicate bank accounts by accountNumber / bankName
    final seen = <String>{};
    final unique = <CheckoutNumberSlot>[];
    for (final b in out) {
      final key = '${b.bankName}_${b.phone}';
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(b);
      }
    }
    return unique;
  }

  List<CheckoutNumberSlot> _reconcileBlockNumbers({
    required String blockId,
    required List<CheckoutSimSource> dynamicSources,
    required List<CheckoutNumberSlot> dynamicBanks,
    required List<CheckoutNumberSlot> savedNumbers,
  }) {
    final reconciled = <CheckoutNumberSlot>[];

    if (blockId == 'bank_accounts') {
      for (final bank in dynamicBanks) {
        final existing = savedNumbers.firstWhere(
          (n) => n.phone == bank.phone && n.bankName == bank.bankName,
          orElse: () => CheckoutNumberSlot(
            simSlot: 1,
            phone: bank.phone,
            enabled: false, // default disabled if not saved yet
            position: 999,
            bankName: bank.bankName,
            accountName: bank.accountName,
            branch: bank.branch,
            accountNumber: bank.phone,
          ),
        );
        reconciled.add(existing);
      }
    } else {
      final blockSources = dynamicSources.where((s) => s.blockId == blockId).toList();
      for (final src in blockSources) {
        final existing = savedNumbers.firstWhere(
          (n) => n.phone == src.phone && n.simSlot == src.simSlot,
          orElse: () => CheckoutNumberSlot(
            simSlot: src.simSlot,
            phone: src.phone,
            enabled: false, // default disabled if not saved yet
            position: 999,
          ),
        );
        reconciled.add(existing);
      }
    }

    // Sort by saved position, then phone number
    reconciled.sort((a, b) {
      final posComp = a.position.compareTo(b.position);
      if (posComp != 0) return posComp;
      return a.phone.compareTo(b.phone);
    });

    // Normalize positions to range [1..N]
    for (var i = 0; i < reconciled.length; i++) {
      reconciled[i] = reconciled[i].copyWith(position: i + 1);
    }

    return reconciled;
  }

  Future<void> _init() async {
    try {
      // 1. Fetch all user devices from API
      final devicesRes = await ApiService.instance.fetchDevices();
      final List<DeviceModel> devices = [];
      if (devicesRes['success'] == true && devicesRes['devices'] is List) {
        for (final d in devicesRes['devices']) {
          devices.add(DeviceModel.fromJson(Map<String, dynamic>.from(d as Map)));
        }
      }

      // 2. Fetch merchant site details
      final detail = await _repo.detail(widget.merchantId);
      var layout = detail.layout;

      // 3. Extract dynamic numbers from active devices
      final dynamicSources = _buildActiveDevicesSimSources(devices);
      final dynamicBanks = _buildActiveDevicesBankAccounts(devices);

      // 4. Reconcile layout mapping
      final updatedBlocks = <String, CheckoutBlockConfig>{};
      for (final id in layout.blockOrder) {
        final block = layout.blocks[id]!;
        final reconciled = _reconcileBlockNumbers(
          blockId: id,
          dynamicSources: dynamicSources,
          dynamicBanks: dynamicBanks,
          savedNumbers: block.numbers,
        );
        updatedBlocks[id] = block.copyWith(numbers: reconciled);
      }

      layout = CheckoutLayout(
        version: layout.version,
        blockOrder: layout.blockOrder,
        blocks: updatedBlocks,
      );

      if (!mounted) return;

      for (final id in layout.blockOrder) {
        _titleControllers[id] = TextEditingController(text: layout.blocks[id]?.title ?? '');
      }

      setState(() {
        _layout = layout;
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
          blockId: block.copyWith(numbers: nums),
        },
      );
    });
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
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 16),
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
          Text(
            widget.siteName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E),
            ),
          ),
          const SizedBox(height: 8),
          for (final blockId in _layout.blockOrder) ...[
            _buildCustomerBlock(blockId),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomerBlock(String blockId) {
    final block = _layout.blocks[blockId]!;
    if (!block.enabled) return const SizedBox.shrink();

    final numbers = block.numbers.where((n) => n.enabled).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    if (numbers.isEmpty) {
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
        final allBlockNumbers = block.numbers;

        return Card(
          key: ValueKey(blockId),
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            initiallyExpanded: index < 2,
            leading: const Icon(Icons.drag_indicator, color: Colors.grey),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    _getFriendlyBlockName(blockId),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: block.enabled ? AppColors.primary : Colors.grey,
                    ),
                  ),
                ),
                Switch(
                  value: block.enabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() {
                      _layout.blocks[blockId] = block.copyWith(enabled: val);
                    });
                  },
                ),
              ],
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
                    _layout.blocks[blockId] = block.copyWith(title: val);
                  },
                ),
              ),
              const Divider(),
              if (allBlockNumbers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'মোবাইল সেটিংস থেকে কোনো নম্বর সেট করা নেই',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text(
                    'নম্বরগুলোর সিরিয়াল সাজান (ড্র্যাগ করুন) এবং টগল দিয়ে অন/অফ করুন',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: allBlockNumbers.length,
                  onReorder: (o, n) => _reorderNumbers(blockId, o, n),
                  itemBuilder: (ctx, ni) {
                    final n = allBlockNumbers[ni];
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
                      leading: const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: n.enabled ? null : TextDecoration.lineThrough,
                          color: n.enabled ? Colors.black : Colors.grey,
                        ),
                      ),
                      subtitle: blockId == 'bank_accounts'
                          ? null
                          : Text(
                              'SIM ${n.simSlot}',
                              style: TextStyle(
                                fontSize: 10,
                                color: n.enabled ? Colors.grey : Colors.grey.shade400,
                              ),
                            ),
                      trailing: Switch(
                        value: n.enabled,
                        activeThumbColor: AppColors.primary,
                        onChanged: (val) {
                          setState(() {
                            final list = List<CheckoutNumberSlot>.from(block.numbers);
                            list[ni] = n.copyWith(enabled: val);
                            _layout.blocks[blockId] = block.copyWith(numbers: list);
                          });
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
