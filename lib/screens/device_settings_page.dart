import 'dart:async';

import 'package:flutter/material.dart';

import '../models/checkout_layout.dart';
import '../models/child_device_remote_config.dart';
import '../models/device_model.dart';
import '../models/sim_filter_preferences.dart';
import '../repositories/child_device_config_repository.dart';
import '../repositories/sim_filter_local_repository.dart';
import '../models/sms_template.dart';
import '../services/sms_template_cache.dart';
import '../services/sms_automation_prefs.dart';
import '../services/sms_service_state_prefs.dart';
import '../utils/bd_phone_utils.dart';
import '../utils/constants.dart';
import '../utils/device_setup_validator.dart';
import '../utils/sender_display_utils.dart';
import '../utils/sender_match_utils.dart';
import '../widgets/custom_mobile_field.dart';
import '../widgets/sim_slot_setup_dialog.dart';

/// SIM 1 / SIM 2 filters: local SharedPreferences on this phone;
/// remote API when parent edits a child device.
class DeviceSettingsPage extends StatefulWidget {
  final DeviceModel device;
  final VoidCallback? onSaved;
  final bool remoteChildMode;

  const DeviceSettingsPage({
    super.key,
    required this.device,
    this.onSaved,
    this.remoteChildMode = false,
  });

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  final _localRepo = SimFilterLocalRepository.instance;
  final _remoteRepo = ChildDeviceConfigRepository();
  final _sim1Input = TextEditingController();
  final _sim2Input = TextEditingController();
  final _sim1Phone = TextEditingController();
  final _sim2Phone = TextEditingController();

  SimFilterPreferences _prefs = SimFilterPreferences.defaults();
  ChildDeviceRemoteConfig? _remoteConfig;
  List<SmsTemplate> _adminTemplates = [];
  bool _loading = true;
  bool _saving = false;
  bool _savingOnPop = false;
  String? _loadError;

  bool get _isRemote => widget.remoteChildMode;

  @override
  void initState() {
    super.initState();
    _sim1Phone.addListener(_onFormFieldsChanged);
    _sim2Phone.addListener(_onFormFieldsChanged);
    _load();
  }

  @override
  void dispose() {
    _sim1Phone.removeListener(_onFormFieldsChanged);
    _sim2Phone.removeListener(_onFormFieldsChanged);
    if (!_isRemote) {
      unawaited(_flushToDisk());
    }
    _sim1Input.dispose();
    _sim2Input.dispose();
    _sim1Phone.dispose();
    _sim2Phone.dispose();
    super.dispose();
  }

  /// Last-chance persist when leaving the page (back / swipe away app).
  Future<void> _flushToDisk() async {
    try {
      _prefs = _prefsWithPhoneFields();
      await _localRepo.save(_prefs);
    } catch (_) {}
  }

  Future<void> _saveOnPop() async {
    try {
      if (_isRemote) return;
      _prefs = _prefsWithPhoneFields();
      await _localRepo.save(_prefs);
      final isConfig = DeviceSetupValidator.isDeviceConfigured(_prefs);
      await SmsServiceStatePrefs.setDeviceConfigured(isConfig);
    } catch (_) {}
  }


  void _onFormFieldsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _sim1Ready => DeviceSetupValidator.slotReady(
        phone: BdPhoneUtils.sanitize(_sim1Phone.text),
        providerTags: _prefs.sim1ProviderTags,
        customSenders: _prefs.sim1CustomSenders,
      );

  bool get _sim2Ready => DeviceSetupValidator.slotReady(
        phone: BdPhoneUtils.sanitize(_sim2Phone.text),
        providerTags: _prefs.sim2ProviderTags,
        customSenders: _prefs.sim2CustomSenders,
      );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await SmsTemplateCache.instance.refreshFromServer(force: true);
      final templates = SmsTemplateCache.instance.templates;

      if (_isRemote) {
        final cfg = await _remoteRepo.fetchForChild(widget.device);
        if (mounted) {
          var prefs = _prefsFromRemote(cfg, templates);
          
          bool forceUpdate = false;
          final sim1Ready = DeviceSetupValidator.slotReady(
            phone: prefs.sim1Number,
            providerTags: prefs.sim1ProviderTags,
            customSenders: prefs.sim1CustomSenders,
          );
          final sim2Ready = DeviceSetupValidator.slotReady(
            phone: prefs.sim2Number,
            providerTags: prefs.sim2ProviderTags,
            customSenders: prefs.sim2CustomSenders,
          );

          if (prefs.sim1Active && !sim1Ready) {
            prefs = prefs.copyWith(sim1Active: false);
            forceUpdate = true;
          }
          if (prefs.sim2Active && !sim2Ready) {
            prefs = prefs.copyWith(sim2Active: false);
            forceUpdate = true;
          }

          setState(() {
            _remoteConfig = cfg;
            _prefs = prefs;
            _adminTemplates = templates;
            _sim1Phone.text = prefs.sim1Number;
            _sim2Phone.text = prefs.sim2Number;
          });

          if (forceUpdate) {
            await _remoteRepo.save(_remoteFromPrefs());
          }
        }
      } else {
        final local = await _localRepo.loadSettings();
        if (mounted) {
          var prefs = local;
          bool forceUpdate = false;
          final sim1Ready = DeviceSetupValidator.slotReady(
            phone: prefs.sim1Number,
            providerTags: prefs.sim1ProviderTags,
            customSenders: prefs.sim1CustomSenders,
          );
          final sim2Ready = DeviceSetupValidator.slotReady(
            phone: prefs.sim2Number,
            providerTags: prefs.sim2ProviderTags,
            customSenders: prefs.sim2CustomSenders,
          );

          if (prefs.sim1Active && !sim1Ready) {
            prefs = prefs.copyWith(sim1Active: false);
            forceUpdate = true;
          }
          if (prefs.sim2Active && !sim2Ready) {
            prefs = prefs.copyWith(sim2Active: false);
            forceUpdate = true;
          }

          setState(() {
            _prefs = prefs;
            _adminTemplates = templates;
            _sim1Phone.text = prefs.sim1Number;
            _sim2Phone.text = prefs.sim2Number;
          });

          if (forceUpdate) {
            await _localRepo.save(prefs);
          }
          
          if (sim1Ready || sim2Ready) {
            await SmsAutomationPrefs.setConfigured(true);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  SimFilterPreferences _prefsFromRemote(
    ChildDeviceRemoteConfig cfg,
    List<SmsTemplate> templates,
  ) {
    final sim1Allowed = cfg.sim1.allowedSenders;
    final sim2Allowed = cfg.sim2.allowedSenders;

    final templatePreviews = templates.map((t) => t.customerPreview).toSet();

    final sim1ProviderTags = sim1Allowed.where((s) => templatePreviews.contains(s)).toList();
    final sim1CustomSenders = sim1Allowed.where((s) => !templatePreviews.contains(s)).toList();

    final sim2ProviderTags = sim2Allowed.where((s) => templatePreviews.contains(s)).toList();
    final sim2CustomSenders = sim2Allowed.where((s) => !templatePreviews.contains(s)).toList();

    return SimFilterPreferences(
      sim1Active: cfg.sim1.active,
      sim1AllowedSenders: List<String>.from(sim1Allowed),
      sim1Number: widget.device.sim1Number ?? '',
      sim1ProviderTags: sim1ProviderTags,
      sim1CustomSenders: sim1CustomSenders,
      sim2Active: cfg.sim2.active,
      sim2AllowedSenders: List<String>.from(sim2Allowed),
      sim2Number: widget.device.sim2Number ?? '',
      sim2ProviderTags: sim2ProviderTags,
      sim2CustomSenders: sim2CustomSenders,
      bankAccounts: cfg.bankAccounts,
    );
  }

  ChildDeviceRemoteConfig _remoteFromPrefs() {
    final base = _remoteConfig ?? ChildDeviceRemoteConfig.fromDevice(widget.device);
    return base.copyWith(
      sim1: SimSlotRemoteConfig(
        active: _prefs.sim1Active,
        allowedSenders: _prefs.sim1AllowedSenders,
      ),
      sim2: SimSlotRemoteConfig(
        active: _prefs.sim2Active,
        allowedSenders: _prefs.sim2AllowedSenders,
      ),
      sim1Number: _prefs.sim1Number,
      sim2Number: _prefs.sim2Number,
      bankAccounts: _prefs.bankAccounts,
    );
  }

  SimFilterPreferences _prefsWithPhoneFields() {
    final sim1Allowed = <String>{
      ..._prefs.sim1ProviderTags,
      ..._prefs.sim1CustomSenders,
    }.toList();
    if (sim1Allowed.isEmpty) {
      sim1Allowed.addAll(SimFilterPreferences.defaultSenders);
    }
    final sim2Allowed = <String>{
      ..._prefs.sim2ProviderTags,
      ..._prefs.sim2CustomSenders,
    }.toList();
    if (sim2Allowed.isEmpty) {
      sim2Allowed.addAll(SimFilterPreferences.defaultSenders);
    }
    return _prefs.copyWith(
      sim1Number: BdPhoneUtils.sanitize(_sim1Phone.text),
      sim1AllowedSenders: sim1Allowed,
      sim2Number: BdPhoneUtils.sanitize(_sim2Phone.text),
      sim2AllowedSenders: sim2Allowed,
    );
  }

  /// Writes SIM fields to SharedPreferences immediately (survives kill/reboot).
  Future<void> _persistLocally({
    bool markConfigured = true,
    bool verify = false,
  }) async {
    if (_isRemote) return;
    _prefs = _prefsWithPhoneFields();
    if (verify) {
      await _localRepo.saveVerified(_prefs);
    } else {
      await _localRepo.save(_prefs);
    }
    if (markConfigured) {
      final isConfig = DeviceSetupValidator.isDeviceConfigured(_prefs);
      await SmsServiceStatePrefs.setDeviceConfigured(isConfig);
    }
  }

  Future<void> _onSim1Toggle(bool? value) async {
    if (value == null) return;
    if (value) {
      if (!_sim1Ready) {
        await SimSlotSetupDialog.show(context, simSlot: 1);
        return;
      }
      setState(() => _prefs = _prefs.copyWith(sim1Active: true));
      await _persistLocally(verify: true);
      return;
    }
    setState(() => _prefs = _prefs.copyWith(sim1Active: false));
    await _persistLocally(verify: true);
  }

  Future<void> _onSim2Toggle(bool? value) async {
    if (value == null) return;
    if (value) {
      if (!_sim2Ready) {
        await SimSlotSetupDialog.show(context, simSlot: 2);
        return;
      }
      setState(() => _prefs = _prefs.copyWith(sim2Active: true));
      await _persistLocally(verify: true);
      return;
    }
    setState(() => _prefs = _prefs.copyWith(sim2Active: false));
    await _persistLocally(verify: true);
  }

  Future<void> _addCustomSender(bool sim1) async {
    final ctrl = sim1 ? _sim1Input : _sim2Input;
    final value = ctrl.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom Sender ID লিখুন')),
      );
      return;
    }
    final stored = canonicalizeAllowedSenderForStorage(value);
    if (stored.isEmpty) return;
    setState(() {
      final list = sim1 ? _prefs.sim1CustomSenders : _prefs.sim2CustomSenders;
      if (list.any((e) => normalizeSenderForMatch(e) == normalizeSenderForMatch(stored))) {
        return;
      }
      _prefs = sim1
          ? _prefs.copyWith(sim1CustomSenders: [...list, stored])
          : _prefs.copyWith(sim2CustomSenders: [...list, stored]);
      ctrl.clear();
    });
    unawaited(_persistLocally());
  }

  void _removeCustomSender(bool sim1, String sender) {
    setState(() {
      if (sim1) {
        _prefs = _prefs.copyWith(
          sim1CustomSenders:
              _prefs.sim1CustomSenders.where((s) => s != sender).toList(),
        );
      } else {
        _prefs = _prefs.copyWith(
          sim2CustomSenders:
              _prefs.sim2CustomSenders.where((s) => s != sender).toList(),
        );
      }
    });
    unawaited(_persistLocally());
  }

  void _toggleProvider(bool sim1, String tag, bool selected) {
    setState(() {
      final list = sim1 ? _prefs.sim1ProviderTags : _prefs.sim2ProviderTags;
      final next = List<String>.from(list);
      if (selected) {
        if (!next.contains(tag)) next.add(tag);
      } else {
        next.remove(tag);
      }
      _prefs = sim1
          ? _prefs.copyWith(sim1ProviderTags: next)
          : _prefs.copyWith(sim2ProviderTags: next);
    });
    unawaited(_persistLocally());
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      _prefs = _prefsWithPhoneFields();
      final err = DeviceSetupValidator.validatePreferences(_prefs);
      if (err != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (_isRemote) {
        await _remoteRepo.save(_remoteFromPrefs());
      } else {
        await _localRepo.saveVerified(_prefs);
        try {
          await _remoteRepo.save(_remoteFromPrefs());
        } catch (e) {
          debugPrint('[DeviceSettingsPage] failed to sync settings to server: $e');
        }
        await SmsServiceStatePrefs.setDeviceConfigured(true);
        await SmsTemplateCache.instance.refreshFromServer(force: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRemote
                ? 'Child device settings updated remotely'
                : 'SIM settings saved on this device',
          ),
          backgroundColor: Colors.green,
        ),
      );
      widget.onSaved?.call();
      setState(() => _savingOnPop = true);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isRemote
        ? 'Child device settings'
        : 'SIM & sender filters';

    return PopScope(
      canPop: _savingOnPop || _isRemote,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        setState(() {
          _savingOnPop = true;
        });
        await _saveOnPop();
        if (context.mounted) {
          Navigator.pop(context, result);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isRemote)
                  _infoBanner(
                    'Remote configuration for ${widget.device.displayDeviceName}.',
                  )
                else
                  _infoBanner(
                    'SIM 1 and SIM 2 are configured separately. '
                    'Each ON slot needs a valid mobile number and at least one sender. '
                    'Tap Save, then enable monitoring from the Home dashboard.',
                  ),
                if (_loadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Could not refresh: $_loadError',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ],
                const SizedBox(height: 8),
                _simSection(
                  simSlot: 1,
                  title: 'SIM 1',
                  icon: Icons.sim_card,
                  active: _prefs.sim1Active,
                  slotReady: _sim1Ready,
                  input: _sim1Input,
                  phoneController: _sim1Phone,
                  providerTags: _prefs.sim1ProviderTags,
                  onToggle: _onSim1Toggle,
                  customSenders: _prefs.sim1CustomSenders,
                  onAddCustom: () => _addCustomSender(true),
                  onRemoveCustom: (s) => _removeCustomSender(true, s),
                  onProviderToggle: (tag, v) => _toggleProvider(true, tag, v),
                ),
                const SizedBox(height: 16),
                _simSection(
                  simSlot: 2,
                  title: 'SIM 2',
                  icon: Icons.sim_card_outlined,
                  active: _prefs.sim2Active,
                  slotReady: _sim2Ready,
                  input: _sim2Input,
                  phoneController: _sim2Phone,
                  providerTags: _prefs.sim2ProviderTags,
                  onToggle: _onSim2Toggle,
                  customSenders: _prefs.sim2CustomSenders,
                  onAddCustom: () => _addCustomSender(false),
                  onRemoveCustom: (s) => _removeCustomSender(false, s),
                  onProviderToggle: (tag, v) => _toggleProvider(false, tag, v),
                ),
                const SizedBox(height: 16),
                _bankSection(),
                const SizedBox(height: 20),
                Card(
                  color: Colors.blue.shade50,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Save your SIM numbers and senders here first.\n'
                            'Then on Home (Dashboard) tap Start Monitoring.\n'
                            '1. Native code detects SIM slot (1 or 2)\n'
                            '2. Matching provider templates extract Amount / TrxID\n'
                            '3. Parsed data syncs to server when monitoring is ON',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _infoBanner(String text) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.tune, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
          ],
        ),
      ),
    );
  }

  Widget _simSection({
    required int simSlot,
    required String title,
    required IconData icon,
    required bool active,
    required bool slotReady,
    required List<String> customSenders,
    required TextEditingController input,
    required TextEditingController phoneController,
    required List<String> providerTags,
    required Future<void> Function(bool?) onToggle,
    required VoidCallback onAddCustom,
    required ValueChanged<String> onRemoveCustom,
    required void Function(String tag, bool selected) onProviderToggle,
  }) {
    final canTurnOn = slotReady;
    final phoneValid =
        BdPhoneUtils.isValid(BdPhoneUtils.sanitize(phoneController.text));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Switch(
                  value: active,
                  onChanged: (v) => onToggle(v),
                  activeThumbColor: AppColors.primary,
                ),
                Text(
                  active ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: active ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (!canTurnOn && !active) ...[
              const SizedBox(height: 6),
              Text(
                'প্রথমে ১১ অঙ্কের নম্বর ও একটি Sender সেট করুন, তারপর সুইচ চালু করুন',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
            const Divider(height: 24),
            Text(
              'SIM mobile number ($title)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            CustomMobileField(
              controller: phoneController,
              enabled: !_isRemote,
              labelText: '01XXXXXXXXX',
              hintText: _isRemote ? 'নম্বর পরিবর্তন করা যাবে না' : '+880 / স্পেস / - স্বয়ংক্রিয় সরানো হবে',
              onChanged: (_) => unawaited(_persistLocally(markConfigured: false)),
            ),
            if (phoneController.text.isNotEmpty && !phoneValid)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'সঠিক ১১ অঙ্কের বাংলাদেশি নম্বর দিন (013–019)',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Option A — Admin templates ($title)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            if (_adminTemplates.isEmpty)
              Text(
                'কোনো টেমপ্লেট নেই। Admin app থেকে SMS rule যোগ করুন।',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in _adminTemplates)
                    FilterChip(
                      label: Text(t.customerPreview),
                      selected: providerTags.contains(t.customerPreview),
                      onSelected: (v) => onProviderToggle(t.customerPreview, v),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Text(
              'Option B — Custom sender ($title)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'কাস্টম Sender — সব এসএমএস catch-all মোডে পড়া হবে',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in customSenders)
                  InputChip(
                    label: Text(displayLabelForStoredSender(s)),
                    onDeleted: () => onRemoveCustom(s),
                    deleteIcon: const Icon(Icons.remove_circle_outline, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    enabled: true,
                    decoration: const InputDecoration(
                      hintText: 'Custom Sender ID (bKash / 017… / MYBANK)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => onAddCustom(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onAddCustom,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add custom sender',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bankSection() {
    final list = _prefs.bankAccounts;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance, color: AppColors.primary),
                const SizedBox(width: 12),
                const Text(
                  'ব্যাংক অ্যাকাউন্টসমূহ (সর্বোচ্চ ৫টি)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (list.length < 5)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                    onPressed: () => _showBankDialog(),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'কোনো ব্যাংক অ্যাকাউন্ট যোগ করা হয়নি।',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, idx) {
                  final b = list[idx];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${b.bankName} — ${b.phone}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Name: ${b.accountName ?? ''}\nBranch: ${b.branch ?? ''}',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _showBankDialog(indexToEdit: idx),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          onPressed: () => _deleteBank(idx),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showBankDialog({int? indexToEdit}) {
    final isEditing = indexToEdit != null;
    final editSlot = isEditing ? _prefs.bankAccounts[indexToEdit] : null;

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
                textCapitalization: TextCapitalization.characters,
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
                final list = List<CheckoutNumberSlot>.from(_prefs.bankAccounts);
                if (isEditing) {
                  list[indexToEdit] = CheckoutNumberSlot(
                    simSlot: 1,
                    phone: phone,
                    enabled: editSlot?.enabled ?? true,
                    position: editSlot?.position ?? (indexToEdit + 1),
                    bankName: bankName,
                    accountName: accountName,
                    branch: branch,
                    accountNumber: phone,
                  );
                } else {
                  list.add(CheckoutNumberSlot(
                    simSlot: 1,
                    phone: phone,
                    enabled: true,
                    position: list.length + 1,
                    bankName: bankName,
                    accountName: accountName,
                    branch: branch,
                    accountNumber: phone,
                  ));
                }
                _prefs = _prefs.copyWith(bankAccounts: list);
              });
              unawaited(_persistLocally());
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(isEditing ? 'পরিবর্তন করুন' : 'যোগ করুন'),
          ),
        ],
      ),
    );
  }

  void _deleteBank(int index) {
    setState(() {
      final list = List<CheckoutNumberSlot>.from(_prefs.bankAccounts)..removeAt(index);
      for (var i = 0; i < list.length; i++) {
        list[i] = list[i].copyWith(position: i + 1);
      }
      _prefs = _prefs.copyWith(bankAccounts: list);
    });
    unawaited(_persistLocally());
  }
}
