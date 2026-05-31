import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../models/payment_settings.dart';
import '../models/sms_gateway.dart';
import '../providers/auth_provider.dart';
import '../providers/config_provider.dart';
import 'sms_templates_tab.dart';
import 'user_management_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    context.read<ConfigProvider>().startListening();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (cfg.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Color(0xFF4FC3F7),
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white54),
            onPressed: () => context.read<AdminAuthProvider>().signOut(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Column(
        children: [
          _TabBar(selected: _tab, onTap: (i) => setState(() => _tab = i)),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _GlobalConfigTab(cfg: cfg),
                _ApiKeysTab(cfg: cfg),
                _SocialLinksTab(cfg: cfg),
                const UserManagementScreen(),
                _PaymentSettingsTab(cfg: cfg),
                const SmsTemplatesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab bar ─────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;
  const _TabBar({required this.selected, required this.onTap});

  static const _labels = [
    'Global',
    'API Keys',
    'Social',
    'Users',
    'Payment',
    'Templates',
  ];
  static const _icons = [
    Icons.tune,
    Icons.key,
    Icons.share,
    Icons.people,
    Icons.payments_outlined,
    Icons.description_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1B2A),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final active = i == selected;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active
                          ? const Color(0xFF4FC3F7)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _icons[i],
                      size: 20,
                      color: active ? const Color(0xFF4FC3F7) : Colors.white38,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: active
                            ? const Color(0xFF4FC3F7)
                            : Colors.white38,
                        fontWeight: active
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Global config tab ────────────────────────────────────────────────────────

class _GlobalConfigTab extends StatelessWidget {
  final ConfigProvider cfg;
  const _GlobalConfigTab({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final g = cfg.global;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(title: 'App Controls', icon: Icons.tune),
        const SizedBox(height: 12),
        _ToggleTile(
          title: 'App Enabled',
          subtitle: 'Master switch — disables entire app for all users',
          value: g.appEnabled,
          onChanged: (v) => cfg.saveGlobal(g.copyWith(appEnabled: v)),
          color: const Color(0xFF4FC3F7),
        ),
        _ToggleTile(
          title: 'User Registration',
          subtitle: 'Allow new users to create accounts',
          value: g.userRegistrationEnabled,
          onChanged: (v) =>
              cfg.saveGlobal(g.copyWith(userRegistrationEnabled: v)),
          color: const Color(0xFF81C784),
        ),
        _ToggleTile(
          title: 'SMS API',
          subtitle: 'Enable SMS-based payment tracking',
          value: g.smsApiEnabled,
          onChanged: (v) => cfg.saveGlobal(g.copyWith(smsApiEnabled: v)),
          color: const Color(0xFFFFB74D),
        ),
        _ToggleTile(
          title: 'Gmail API',
          subtitle: 'Enable Gmail-based payment tracking',
          value: g.gmailApiEnabled,
          onChanged: (v) => cfg.saveGlobal(g.copyWith(gmailApiEnabled: v)),
          color: const Color(0xFFE57373),
        ),
      ],
    );
  }
}

// ── API Keys tab ─────────────────────────────────────────────────────────────

class _ApiKeysTab extends StatelessWidget {
  final ConfigProvider cfg;
  const _ApiKeysTab({required this.cfg});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SmsProvidersSection(cfg: cfg),
        const SizedBox(height: 32),
        Divider(color: Colors.white12),
        const SizedBox(height: 24),
        _EmailAccountsSection(cfg: cfg),
        const SizedBox(height: 32),
        Divider(color: Colors.white12),
        const SizedBox(height: 24),
        _SmsOtpTemplateSection(cfg: cfg),
      ],
    );
  }
}

// ── Email Accounts section (inside API Keys tab) ─────────────────────────────

class _EmailAccountsSection extends StatelessWidget {
  final ConfigProvider cfg;
  const _EmailAccountsSection({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final accounts = cfg.emailAccounts;
    final hasActive = accounts.any((a) => a.isActive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SectionHeader(
              title: 'OTP Email (Gmail SMTP)',
              icon: Icons.mark_email_read_outlined,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: hasActive
                    ? const Color(0xFF81C784).withAlpha(30)
                    : Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasActive
                      ? const Color(0xFF81C784)
                      : Colors.red.shade300,
                ),
              ),
              child: Text(
                hasActive ? 'CONFIGURED' : 'NOT SET',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: hasActive
                      ? const Color(0xFF81C784)
                      : Colors.red.shade300,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFF4FC3F7)),
              tooltip: 'Add Gmail account',
              onPressed: () => _showEmailAccountDialog(context, cfg, null),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D).withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFB74D).withAlpha(60)),
          ),
          child: const Text(
            'Round-robin: first account sends 500 OTPs, then switches to the next.\n'
            'Use a Gmail App Password (not your account password).',
            style: TextStyle(color: Color(0xFFFFB74D), fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            child: const Text(
              'No Gmail accounts configured',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          )
        else
          ...accounts.map((a) => _EmailAccountCard(account: a, cfg: cfg)),
      ],
    );
  }
}

// ── SMS OTP Template section ──────────────────────────────────────────────────

class _SmsOtpTemplateSection extends StatefulWidget {
  final ConfigProvider cfg;
  const _SmsOtpTemplateSection({required this.cfg});

  @override
  State<_SmsOtpTemplateSection> createState() => _SmsOtpTemplateSectionState();
}

class _SmsOtpTemplateSectionState extends State<_SmsOtpTemplateSection> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    setState(() => _loading = true);
    final t = await widget.cfg.loadSmsOtpTemplate();
    if (mounted) {
      _ctrl.text = t;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _SectionHeader(
              title: 'SMS OTP Format',
              icon: Icons.message_outlined,
            ),
            const Spacer(),
            if (_loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4FC3F7),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D).withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFB74D).withAlpha(60)),
          ),
          child: const Text(
            'Use {code} where the 6-digit OTP should appear.\n'
            'Example: Your OTP is {code}. Do not share it with anyone.',
            style: TextStyle(color: Color(0xFFFFB74D), fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          maxLines: 3,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Enter SMS format...',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF0D1B2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 2),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: const Color(0xFF0D1B2A),
              ),
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save Format'),
              onPressed: () async {
                final text = _ctrl.text.trim();
                if (!text.contains('{code}')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Template must contain {code} placeholder'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                final ok = await widget.cfg.saveSmsOtpTemplate(text);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'SMS format saved'
                            : 'Save failed: ${widget.cfg.saveError}',
                      ),
                      backgroundColor: ok
                          ? const Color(0xFF81C784)
                          : Colors.red[700],
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Reset Default'),
              onPressed: () {
                setState(() {
                  _ctrl.text =
                      'আপনার Payment Checker OTP: {code}। কাউকে বলবেন না।';
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _EmailAccountCard extends StatelessWidget {
  final EmailAccount account;
  final ConfigProvider cfg;
  const _EmailAccountCard({required this.account, required this.cfg});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: account.isActive
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (account.name.isNotEmpty)
                      Text(
                        account.name,
                        style: const TextStyle(
                          color: Color(0xFF4FC3F7),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    Text(
                      account.email,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (account.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF81C784).withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: Color(0xFF81C784),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Limit: ${account.dailyLimit}  |  Sent: ${account.sentCount}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: account.isActive,
                onChanged: cfg.saving
                    ? null
                    : (v) => v
                          ? cfg.activateEmailAccount(account.id)
                          : cfg.deactivateEmailAccount(account.id),
                activeThumbColor: const Color(0xFF81C784),
                inactiveThumbColor: Colors.white38,
                inactiveTrackColor: Colors.white12,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF4FC3F7),
                  size: 20,
                ),
                tooltip: 'Edit',
                onPressed: () => _showEmailAccountDialog(context, cfg, account),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.red.shade300,
                  size: 20,
                ),
                tooltip: 'Delete',
                onPressed: () => _confirmDeleteEmail(context, cfg, account),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDeleteEmail(
    BuildContext context,
    ConfigProvider cfg,
    EmailAccount account,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E42),
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${account.email}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              cfg.deleteEmailAccount(account.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

void _showEmailAccountDialog(
  BuildContext context,
  ConfigProvider cfg,
  EmailAccount? existing,
) {
  final isEdit = existing != null;
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final emailCtrl = TextEditingController(text: existing?.email ?? '');
  final passCtrl = TextEditingController(text: existing?.appPassword ?? '');
  final limitCtrl = TextEditingController(
    text: (existing?.dailyLimit ?? 500).toString(),
  );
  bool obscurePass = true;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E42),
        title: Text(
          isEdit ? 'Edit Gmail Account' : 'Add Gmail Account',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(
                controller: nameCtrl,
                label: 'Account Name (optional)',
                hint: 'e.g. Primary Gmail',
              ),
              const SizedBox(height: 12),
              _DialogField(
                controller: emailCtrl,
                label: 'Gmail Address',
                hint: 'yourname@gmail.com',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscurePass,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'App Password',
                  hintText: 'xxxx xxxx xxxx xxxx',
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintStyle: const TextStyle(color: Colors.white24),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onPressed: () => setState(() => obscurePass = !obscurePass),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0D1B2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF4FC3F7),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DialogField(
                controller: limitCtrl,
                label: 'Daily Limit',
                hint: '500',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4FC3F7),
              foregroundColor: const Color(0xFF0D1B2A),
            ),
            icon: const Icon(Icons.save, size: 18),
            label: Text(isEdit ? 'Update' : 'Add'),
            onPressed: () async {
              final email = emailCtrl.text.trim();
              final pass = passCtrl.text.trim();
              final limit = int.tryParse(limitCtrl.text.trim()) ?? 500;
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Valid email address required'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (pass.length < 8) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('App Password must be at least 8 characters'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              final a = EmailAccount(
                id: existing?.id ?? '',
                name: nameCtrl.text.trim(),
                email: email,
                appPassword: pass,
                dailyLimit: limit,
                isActive: existing?.isActive ?? false,
              );
              final ok = isEdit
                  ? await cfg.updateEmailAccount(a)
                  : await cfg.addEmailAccount(a);
              if (!ok && ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Save failed: ${cfg.saveError}'),
                    backgroundColor: Colors.red[700],
                  ),
                );
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    ),
  );
}

// ── Social Links tab ─────────────────────────────────────────────────────────

class _SocialLinksTab extends StatefulWidget {
  final ConfigProvider cfg;
  const _SocialLinksTab({required this.cfg});

  @override
  State<_SocialLinksTab> createState() => _SocialLinksTabState();
}

class _SocialLinksTabState extends State<_SocialLinksTab> {
  late final TextEditingController _whatsapp;
  late final TextEditingController _facebook;
  late final TextEditingController _telegram;
  late final TextEditingController _youtube;

  /// true once the user has typed in (or cleared) a field — stops server
  /// polling from overwriting local edits.
  bool _whatsappDirty = false;
  bool _facebookDirty = false;
  bool _telegramDirty = false;
  bool _youtubeDirty = false;

  @override
  void initState() {
    super.initState();
    final s = widget.cfg.socialLinks;
    _whatsapp = TextEditingController(text: s.whatsapp);
    _facebook = TextEditingController(text: s.facebook);
    _telegram = TextEditingController(text: s.telegram);
    _youtube = TextEditingController(text: s.youtube);
    widget.cfg.addListener(_onConfigChanged);
  }

  @override
  void dispose() {
    widget.cfg.removeListener(_onConfigChanged);
    _whatsapp.dispose();
    _facebook.dispose();
    _telegram.dispose();
    _youtube.dispose();
    super.dispose();
  }

  /// Fill fields from the server only when the user hasn't touched them yet.
  void _onConfigChanged() {
    if (!mounted) return;
    final s = widget.cfg.socialLinks;
    if (!_whatsappDirty && s.whatsapp.isNotEmpty) _whatsapp.text = s.whatsapp;
    if (!_facebookDirty && s.facebook.isNotEmpty) _facebook.text = s.facebook;
    if (!_telegramDirty && s.telegram.isNotEmpty) _telegram.text = s.telegram;
    if (!_youtubeDirty && s.youtube.isNotEmpty) _youtube.text = s.youtube;
  }

  Future<void> _save() async {
    final ok = await widget.cfg.saveSocialLinks(
      SocialLinks(
        whatsapp: _whatsapp.text.trim(),
        facebook: _facebook.text.trim(),
        telegram: _telegram.text.trim(),
        youtube: _youtube.text.trim(),
      ),
    );
    if (ok) {
      _whatsappDirty = false;
      _facebookDirty = false;
      _telegramDirty = false;
      _youtubeDirty = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Social links saved' : 'Save failed: ${widget.cfg.saveError}',
        ),
        backgroundColor: ok ? const Color(0xFF388E3C) : Colors.red[700],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(title: 'Social Media Links', icon: Icons.share),
        const SizedBox(height: 12),
        _DarkField(
          controller: _whatsapp,
          label: 'WhatsApp',
          hint: 'https://wa.me/880XXXXXXXXXX',
          prefix: const Icon(Icons.chat, color: Color(0xFF25D366), size: 20),
          onChanged: (_) => _whatsappDirty = true,
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _facebook,
          label: 'Facebook',
          hint: 'https://facebook.com/YOUR_PAGE',
          prefix: const Icon(
            Icons.facebook,
            color: Color(0xFF1877F2),
            size: 20,
          ),
          onChanged: (_) => _facebookDirty = true,
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _telegram,
          label: 'Telegram',
          hint: 'https://t.me/YOUR_CHANNEL',
          prefix: const Icon(Icons.send, color: Color(0xFF229ED9), size: 20),
          onChanged: (_) => _telegramDirty = true,
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _youtube,
          label: 'YouTube',
          hint: 'https://youtube.com/@YOUR_CHANNEL',
          prefix: const Icon(
            Icons.play_circle,
            color: Color(0xFFFF0000),
            size: 20,
          ),
          onChanged: (_) => _youtubeDirty = true,
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: widget.cfg.saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Save Links'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4FC3F7),
            foregroundColor: const Color(0xFF0D1B2A),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Payment Settings (bKash) ────────────────────────────────────────────────

class _PaymentSettingsTab extends StatefulWidget {
  final ConfigProvider cfg;
  const _PaymentSettingsTab({required this.cfg});

  @override
  State<_PaymentSettingsTab> createState() => _PaymentSettingsTabState();
}

class _PaymentSettingsTabState extends State<_PaymentSettingsTab> {
  late final TextEditingController _apiKey;
  late final TextEditingController _secretKey;
  late final TextEditingController _appId;
  late final TextEditingController _password;
  late final TextEditingController _callbackUrl;
  bool _testMode = true;

  @override
  void initState() {
    super.initState();
    final p = widget.cfg.paymentSettings;
    _apiKey = TextEditingController(text: p.bkashApiKey);
    _secretKey = TextEditingController(text: p.bkashSecretKey);
    _appId = TextEditingController(text: p.bkashAppId);
    _password = TextEditingController(text: p.bkashPassword);
    _callbackUrl = TextEditingController(text: p.bkashCallbackUrl);
    _testMode = p.testMode;
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _secretKey.dispose();
    _appId.dispose();
    _password.dispose();
    _callbackUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await widget.cfg.savePaymentSettings(
      PaymentSettings(
        bkashApiKey: _apiKey.text.trim(),
        bkashSecretKey: _secretKey.text.trim(),
        bkashAppId: _appId.text.trim(),
        bkashPassword: _password.text.trim(),
        testMode: _testMode,
        bkashCallbackUrl: _callbackUrl.text.trim(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Payment settings saved'
              : 'Save failed: ${widget.cfg.saveError}',
        ),
        backgroundColor: ok ? const Color(0xFF388E3C) : Colors.red[700],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          title: 'Payment Settings (bKash)',
          icon: Icons.account_balance,
        ),
        const SizedBox(height: 8),
        const Text(
          'Credentials are stored in Firestore (config/paymentSettings). '
          'The User App uses Cloud Functions to create checkout sessions — secrets are not exposed in the app.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2E42),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _testMode
                  ? const Color(0xFFFFB74D).withAlpha(100)
                  : const Color(0xFF81C784).withAlpha(100),
            ),
          ),
          child: SwitchListTile(
            title: const Text(
              'Test mode',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _testMode
                  ? 'Sandbox / tokenized test endpoints'
                  : 'Live production bKash endpoints',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            value: _testMode,
            onChanged: (v) => setState(() => _testMode = v),
            activeThumbColor: const Color(0xFFFFB74D),
            inactiveThumbColor: const Color(0xFF81C784),
            inactiveTrackColor: Colors.white12,
          ),
        ),
        _DarkField(controller: _apiKey, label: 'BKASH_API_KEY', obscure: true),
        const SizedBox(height: 12),
        _DarkField(
          controller: _secretKey,
          label: 'BKASH_SECRET_KEY',
          obscure: true,
        ),
        const SizedBox(height: 12),
        _DarkField(controller: _appId, label: 'BKASH_APP_ID'),
        const SizedBox(height: 12),
        _DarkField(
          controller: _password,
          label: 'BKASH_PASSWORD',
          obscure: true,
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _callbackUrl,
          label: 'Callback URL (optional)',
          hint: 'https://your.app/bkash-callback — use in bKash app & WebView',
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: widget.cfg.saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Save payment settings'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4FC3F7),
            foregroundColor: const Color(0xFF0D1B2A),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4FC3F7), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF4FC3F7),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;

  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? color.withAlpha(80) : Colors.transparent,
        ),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: color,
        inactiveThumbColor: Colors.white38,
        inactiveTrackColor: Colors.white12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final Widget? prefix;
  final ValueChanged<String>? onChanged;

  const _DarkField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.prefix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: prefix,
        filled: true,
        fillColor: const Color(0xFF1A2E42),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 2),
        ),
      ),
    );
  }
}

// ── SMS Gateways tab ────────────────────────────────────────────────────────

class _SmsProvidersSection extends StatelessWidget {
  final ConfigProvider cfg;
  const _SmsProvidersSection({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final gateways = cfg.smsGateways;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _SectionHeader(title: 'SMS Providers', icon: Icons.sms),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFF4FC3F7)),
              tooltip: 'Add provider',
              onPressed: () => _showGatewayDialog(context, cfg, null),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (gateways.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            child: const Text(
              'No SMS providers configured',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          )
        else
          ...gateways.map((gw) => _GatewayCard(gw: gw, cfg: cfg)),
      ],
    );
  }
}

class _GatewayCard extends StatelessWidget {
  final SmsGateway gw;
  final ConfigProvider cfg;
  const _GatewayCard({required this.gw, required this.cfg});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: gw.isActive
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
                  gw.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (gw.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF81C784).withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: Color(0xFF81C784),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            gw.endpoint.isNotEmpty ? gw.endpoint : '(no endpoint)',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (gw.senderId.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Sender: ${gw.senderId}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          if (gw.username.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Username: ${gw.username}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: gw.isActive,
                onChanged: cfg.saving
                    ? null
                    : (v) => v
                          ? cfg.activateSmsGateway(gw.id)
                          : cfg.deactivateSmsGateway(gw.id),
                activeThumbColor: const Color(0xFF81C784),
                inactiveThumbColor: Colors.white38,
                inactiveTrackColor: Colors.white12,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF4FC3F7),
                  size: 20,
                ),
                tooltip: 'Edit',
                onPressed: () => _showGatewayDialog(context, cfg, gw),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.red.shade300,
                  size: 20,
                ),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, cfg, gw),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, ConfigProvider cfg, SmsGateway gw) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E42),
        title: const Text(
          'Delete Provider',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${gw.name}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              cfg.deleteSmsGateway(gw.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

void _showGatewayDialog(
  BuildContext context,
  ConfigProvider cfg,
  SmsGateway? existing,
) {
  final isEdit = existing != null;
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
  final usernameCtrl = TextEditingController(text: existing?.username ?? '');
  final endpointCtrl = TextEditingController(text: existing?.endpoint ?? '');
  final senderCtrl = TextEditingController(text: existing?.senderId ?? '');

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A2E42),
      title: Text(
        isEdit ? 'Edit Provider' : 'Add Provider',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogField(controller: nameCtrl, label: 'Provider Name'),
            const SizedBox(height: 12),
            _DialogField(controller: keyCtrl, label: 'API Key', obscure: true),
            const SizedBox(height: 12),
            _DialogField(
              controller: usernameCtrl,
              label: 'Username (optional)',
            ),
            const SizedBox(height: 12),
            _DialogField(
              controller: endpointCtrl,
              label: 'Endpoint URL',
              hint: 'https://api.example.com/sms',
            ),
            const SizedBox(height: 12),
            _DialogField(controller: senderCtrl, label: 'Sender ID (optional)'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
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
            final name = nameCtrl.text.trim();
            final key = keyCtrl.text.trim();
            final endpoint = endpointCtrl.text.trim();
            if (name.isEmpty || key.isEmpty || endpoint.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('Name, API Key, and Endpoint are required'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            final gw = SmsGateway(
              id: existing?.id ?? '',
              name: name,
              apiKey: key,
              username: usernameCtrl.text.trim(),
              endpoint: endpoint,
              senderId: senderCtrl.text.trim(),
              isActive: existing?.isActive ?? false,
            );
            final ok = isEdit
                ? await cfg.updateSmsGateway(gw)
                : await cfg.addSmsGateway(gw);
            if (!ok && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text('Save failed: ${cfg.saveError}'),
                  backgroundColor: Colors.red[700],
                ),
              );
              return;
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ],
    ),
  );
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;

  const _DialogField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF0D1B2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 2),
        ),
      ),
    );
  }
}
