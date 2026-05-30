import 'package:flutter/material.dart';
import '../models/sms_template.dart';
import '../services/api_service.dart';

class SmsTemplatesTab extends StatefulWidget {
  const SmsTemplatesTab({super.key});

  @override
  State<SmsTemplatesTab> createState() => _SmsTemplatesTabState();
}

class _SmsTemplatesTabState extends State<SmsTemplatesTab> {
  final _api = ApiService.instance;
  List<SmsTemplate> _templates = [];
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
      final res = await _api.getJson('/api/admin/sms-templates');
      if (res['success'] == true && res['templates'] is List) {
        final list = res['templates'] as List;
        setState(() {
          _templates = list
              .map((e) => SmsTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load templates';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteTemplate(SmsTemplate tpl) async {
    try {
      final res = await _api.deleteJson('/api/admin/sms-templates/${tpl.id}');
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template deleted'),
            backgroundColor: Color(0xFF388E3C),
          ),
        );
        _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  void _confirmDelete(SmsTemplate tpl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E42),
        title: const Text('Delete Template', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete template "${tpl.customerPreview}"? This will disable dynamic parsing for this provider tag.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteTemplate(tpl);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(SmsTemplate tpl, bool nextVal) async {
    try {
      final res = await _api.putJson('/api/admin/sms-templates/${tpl.id}', {
        'customer_preview': tpl.customerPreview,
        'sender_id': tpl.senderId,
        'formats': tpl.formats,
        'is_active': nextVal ? 1 : 0,
      });
      if (!mounted) return;
      if (res['success'] == true) {
        _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  void _showTemplateDialog(SmsTemplate? tpl) {
    final isEdit = tpl != null;
    final previewCtrl = TextEditingController(text: tpl?.customerPreview ?? '');
    final senderCtrl = TextEditingController(text: tpl?.senderId ?? '');

    // List of controllers for condition text fields
    final List<TextEditingController> conditionCtrls = [];
    if (isEdit && tpl.formats.isNotEmpty) {
      for (final fmt in tpl.formats) {
        conditionCtrls.add(TextEditingController(text: fmt));
      }
    } else {
      conditionCtrls.add(TextEditingController());
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A2E42),
              title: Text(isEdit ? 'Edit Template' : 'Add SMS Template',
                  style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'কাস্টমার প্রিভিউ (Customer Preview)',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      _DialogField(
                        controller: previewCtrl,
                        label: 'যেমন: bKash Personal, Nagad Personal',
                        hint: 'bKash Personal',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'সেন্ডার আইডি (Sender ID)',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      _DialogField(
                        controller: senderCtrl,
                        label: 'যেমন: bKash, NAGAD, 16216',
                        hint: 'bKash',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            'কন্ডিশন / ফরম্যাটসমূহ (Conditions)',
                            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Color(0xFF4FC3F7)),
                            onPressed: () {
                              setDialogState(() {
                                conditionCtrls.add(TextEditingController());
                              });
                            },
                            tooltip: 'Add format condition',
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (int i = 0; i < conditionCtrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: _DialogField(
                                  controller: conditionCtrls[i],
                                  label: 'কন্ডিশন ${i + 1} (SMS-এর ভেতরের টেক্সট)',
                                  hint: 'You have received cash in [amount] from [phone]',
                                ),
                              ),
                              if (conditionCtrls.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                                  onPressed: () {
                                    setDialogState(() {
                                      final ctrl = conditionCtrls.removeAt(i);
                                      ctrl.dispose();
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    for (final ctrl in conditionCtrls) {
                      ctrl.dispose();
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7),
                    foregroundColor: const Color(0xFF0D1B2A),
                  ),
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(isEdit ? 'Update' : 'Add'),
                  onPressed: () async {
                    final preview = previewCtrl.text.trim();
                    final sender = senderCtrl.text.trim();
                    final List<String> formats = conditionCtrls
                        .map((c) => c.text.trim())
                        .where((t) => t.isNotEmpty)
                        .toList();

                    if (preview.isEmpty || sender.isEmpty || formats.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Customer Preview, Sender ID, and at least one condition are required'),
                        backgroundColor: Colors.red,
                      ));
                      return;
                    }

                    try {
                      final body = {
                        'customer_preview': preview,
                        'sender_id': sender,
                        'formats': formats,
                        if (isEdit) 'is_active': tpl.isActive ? 1 : 0,
                      };

                      final path = isEdit
                          ? '/api/admin/sms-templates/${tpl.id}'
                          : '/api/admin/sms-templates';

                      final res = isEdit
                          ? await _api.putJson(path, body)
                          : await _api.postJson(path, body);

                      if (res['success'] == true) {
                        for (final ctrl in conditionCtrls) {
                          ctrl.dispose();
                        }
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(isEdit ? 'Template updated' : 'Template created'),
                          backgroundColor: const Color(0xFF388E3C),
                        ));
                        _load();
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text('Save failed: $e'),
                          backgroundColor: Colors.red[700],
                        ));
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4FC3F7),
        foregroundColor: const Color(0xFF0D1B2A),
        onPressed: () => _showTemplateDialog(null),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _templates.isEmpty
                  ? const Center(
                      child: Text(
                        'No SMS templates configured.\nClick the + button to add one.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: const Color(0xFF4FC3F7),
                      backgroundColor: const Color(0xFF1A2E42),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: _templates.length,
                        itemBuilder: (context, idx) {
                          final t = _templates[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2E42),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: t.isActive
                                    ? const Color(0xFF81C784).withAlpha(80)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t.customerPreview,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: t.isActive,
                                      onChanged: (val) => _toggleActive(t, val),
                                      activeThumbColor: const Color(0xFF81C784),
                                      inactiveThumbColor: Colors.white38,
                                      inactiveTrackColor: Colors.white12,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Sender ID Match: ${t.senderId}',
                                  style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'SMS Format Conditions:',
                                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                for (final fmt in t.formats)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('• ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                                        Expanded(
                                          child: Text(
                                            fmt,
                                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                const Divider(color: Colors.white10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF4FC3F7)),
                                      label: const Text('Edit', style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 13)),
                                      onPressed: () => _showTemplateDialog(t),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[300]),
                                      label: Text('Delete', style: TextStyle(color: Colors.red[300], fontSize: 13)),
                                      onPressed: () => _confirmDelete(t),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;

  const _DialogField({
    required this.controller,
    required this.label,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0D1B2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
