import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../models/payment_settings.dart';
import '../models/sms_gateway.dart';
import '../providers/auth_provider.dart';
import '../providers/config_provider.dart';
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
        title: const Text('Admin Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (cfg.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Color(0xFF4FC3F7), strokeWidth: 2),
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
                _SmsGatewaysTab(cfg: cfg),
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
    'SMS',
  ];
  static const _icons = [
    Icons.tune,
    Icons.key,
    Icons.share,
    Icons.people,
    Icons.payments_outlined,
    Icons.sms,
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
                    Icon(_icons[i],
                        size: 20,
                        color: active
                            ? const Color(0xFF4FC3F7)
                            : Colors.white38),
                    const SizedBox(height: 4),
                    Text(_labels[i],
                        style: TextStyle(
                          fontSize: 11,
                          color: active
                              ? const Color(0xFF4FC3F7)
                              : Colors.white38,
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
                        )),
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
          onChanged: (v) =>
              cfg.saveGlobal(g.copyWith(appEnabled: v)),
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
          onChanged: (v) =>
              cfg.saveGlobal(g.copyWith(smsApiEnabled: v)),
          color: const Color(0xFFFFB74D),
        ),
        _ToggleTile(
          title: 'Gmail API',
          subtitle: 'Enable Gmail-based payment tracking',
          value: g.gmailApiEnabled,
          onChanged: (v) =>
              cfg.saveGlobal(g.copyWith(gmailApiEnabled: v)),
          color: const Color(0xFFE57373),
        ),
      ],
    );
  }
}

// ── API Keys tab ─────────────────────────────────────────────────────────────

class _ApiKeysTab extends StatefulWidget {
  final ConfigProvider cfg;
  const _ApiKeysTab({required this.cfg});

  @override
  State<_ApiKeysTab> createState() => _ApiKeysTabState();
}

class _ApiKeysTabState extends State<_ApiKeysTab> {
  late final TextEditingController _smsKey;
  late final TextEditingController _smsEndpoint;
  late final TextEditingController _gmailKey;
  late final TextEditingController _gmailEndpoint;

  @override
  void initState() {
    super.initState();
    final k = widget.cfg.apiKeys;
    _smsKey = TextEditingController(text: k.smsApiKey);
    _smsEndpoint = TextEditingController(text: k.smsApiEndpoint);
    _gmailKey = TextEditingController(text: k.gmailApiKey);
    _gmailEndpoint = TextEditingController(text: k.gmailApiEndpoint);
  }

  @override
  void dispose() {
    _smsKey.dispose();
    _smsEndpoint.dispose();
    _gmailKey.dispose();
    _gmailEndpoint.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await widget.cfg.saveApiKeys(ApiKeys(
      smsApiKey: _smsKey.text.trim(),
      smsApiEndpoint: _smsEndpoint.text.trim(),
      gmailApiKey: _gmailKey.text.trim(),
      gmailApiEndpoint: _gmailEndpoint.text.trim(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'API keys saved' : 'Save failed: ${widget.cfg.saveError}'),
      backgroundColor: ok ? const Color(0xFF388E3C) : Colors.red[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(title: 'SMS API', icon: Icons.sms),
        const SizedBox(height: 12),
        _DarkField(controller: _smsKey, label: 'SMS API Key', obscure: true),
        const SizedBox(height: 12),
        _DarkField(
            controller: _smsEndpoint,
            label: 'SMS API Endpoint',
            hint: 'https://api.example.com/sms'),
        const SizedBox(height: 24),
        _SectionHeader(title: 'Gmail API', icon: Icons.email_outlined),
        const SizedBox(height: 12),
        _DarkField(
            controller: _gmailKey, label: 'Gmail API Key', obscure: true),
        const SizedBox(height: 12),
        _DarkField(
            controller: _gmailEndpoint,
            label: 'Gmail API Endpoint',
            hint: 'https://api.example.com/gmail'),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: widget.cfg.saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Save API Keys'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4FC3F7),
            foregroundColor: const Color(0xFF0D1B2A),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 32),
        Divider(color: Colors.white12),
        const SizedBox(height: 24),
        _EmailConfigSection(cfg: widget.cfg),
      ],
    );
  }
}

// ── Email Config section (inside API Keys tab) ───────────────────────────────

class _EmailConfigSection extends StatefulWidget {
  final ConfigProvider cfg;
  const _EmailConfigSection({required this.cfg});

  @override
  State<_EmailConfigSection> createState() => _EmailConfigSectionState();
}

class _EmailConfigSectionState extends State<_EmailConfigSection> {
  late final TextEditingController _gmailAddr;
  late final TextEditingController _appPass;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    final e = widget.cfg.emailConfig;
    _gmailAddr = TextEditingController(text: e.gmailAddress);
    _appPass = TextEditingController(text: e.appPassword);
  }

  @override
  void dispose() {
    _gmailAddr.dispose();
    _appPass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final addr = _gmailAddr.text.trim();
    final pass = _appPass.text;
    if (addr.isEmpty || !addr.contains('@gmail.com')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Valid @gmail.com address required'),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (pass.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('App Password must be at least 8 characters'),
            backgroundColor: Colors.red),
      );
      return;
    }
    final ok = await widget.cfg.saveEmailConfig(
        EmailConfig(gmailAddress: addr, appPassword: pass));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'OTP email credentials saved' : 'Save failed: ${widget.cfg.saveError}'),
      backgroundColor: ok ? const Color(0xFF388E3C) : Colors.red[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.cfg.emailConfig.isConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SectionHeader(title: 'OTP Email (Gmail SMTP)', icon: Icons.mark_email_read_outlined),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: configured
                    ? const Color(0xFF81C784).withAlpha(30)
                    : Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: configured
                        ? const Color(0xFF81C784)
                        : Colors.red.shade300),
              ),
              child: Text(
                configured ? 'CONFIGURED' : 'NOT SET',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: configured
                      ? const Color(0xFF81C784)
                      : Colors.red.shade300,
                ),
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
            'Use a Gmail App Password (not your account password).\n'
            'Generate at: myaccount.google.com → Security → 2-Step Verification → App Passwords',
            style: TextStyle(color: Color(0xFFFFB74D), fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),
        _DarkField(
          controller: _gmailAddr,
          label: 'Gmail Address',
          hint: 'yourname@gmail.com',
          prefix: const Icon(Icons.email_outlined, color: Colors.white38, size: 20),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _appPass,
          obscureText: _obscurePass,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'App Password',
            hintText: 'xxxx xxxx xxxx xxxx',
            labelStyle: const TextStyle(color: Colors.white54),
            hintStyle: const TextStyle(color: Colors.white24),
            prefixIcon: const Icon(Icons.vpn_key_outlined,
                color: Colors.white38, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscurePass ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                  size: 20),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
            filled: true,
            fillColor: const Color(0xFF1A2E42),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF4FC3F7), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: widget.cfg.saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Save Email Credentials'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF81C784),
            foregroundColor: const Color(0xFF0D1B2A),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
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

  @override
  void initState() {
    super.initState();
    final s = widget.cfg.socialLinks;
    _whatsapp = TextEditingController(text: s.whatsapp);
    _facebook = TextEditingController(text: s.facebook);
    _telegram = TextEditingController(text: s.telegram);
    _youtube = TextEditingController(text: s.youtube);
  }

  @override
  void dispose() {
    _whatsapp.dispose();
    _facebook.dispose();
    _telegram.dispose();
    _youtube.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await widget.cfg.saveSocialLinks(SocialLinks(
      whatsapp: _whatsapp.text.trim(),
      facebook: _facebook.text.trim(),
      telegram: _telegram.text.trim(),
      youtube: _youtube.text.trim(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Social links saved' : 'Save failed: ${widget.cfg.saveError}'),
      backgroundColor: ok ? const Color(0xFF388E3C) : Colors.red[700],
    ));
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
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _facebook,
          label: 'Facebook',
          hint: 'https://facebook.com/YOUR_PAGE',
          prefix:
              const Icon(Icons.facebook, color: Color(0xFF1877F2), size: 20),
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _telegram,
          label: 'Telegram',
          hint: 'https://t.me/YOUR_CHANNEL',
          prefix: const Icon(Icons.send, color: Color(0xFF229ED9), size: 20),
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _youtube,
          label: 'YouTube',
          hint: 'https://youtube.com/@YOUR_CHANNEL',
          prefix:
              const Icon(Icons.play_circle, color: Color(0xFFFF0000), size: 20),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final ok = await widget.cfg.savePaymentSettings(PaymentSettings(
      bkashApiKey: _apiKey.text.trim(),
      bkashSecretKey: _secretKey.text.trim(),
      bkashAppId: _appId.text.trim(),
      bkashPassword: _password.text.trim(),
      testMode: _testMode,
      bkashCallbackUrl: _callbackUrl.text.trim(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Payment settings saved'
          : 'Save failed: ${widget.cfg.saveError}'),
      backgroundColor: ok ? const Color(0xFF388E3C) : Colors.red[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(title: 'Payment Settings (bKash)', icon: Icons.account_balance),
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
            title: const Text('Test mode',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
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
        _DarkField(
          controller: _apiKey,
          label: 'BKASH_API_KEY',
          obscure: true,
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _secretKey,
          label: 'BKASH_SECRET_KEY',
          obscure: true,
        ),
        const SizedBox(height: 12),
        _DarkField(
          controller: _appId,
          label: 'BKASH_APP_ID',
        ),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        Text(title,
            style: const TextStyle(
              color: Color(0xFF4FC3F7),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            )),
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
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: color,
        inactiveThumbColor: Colors.white38,
        inactiveTrackColor: Colors.white12,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  const _DarkField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.prefix,
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
        prefixIcon: prefix,
        filled: true,
        fillColor: const Color(0xFF1A2E42),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Color(0xFF4FC3F7), width: 2),
        ),
      ),
    );
  }
}

// ── SMS Gateways tab ────────────────────────────────────────────────────────

class _SmsGatewaysTab extends StatelessWidget {
  final ConfigProvider cfg;
  const _SmsGatewaysTab({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final gateways = cfg.smsGateways;
    return ListView(
      padding: const EdgeInsets.all(20),
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
                child: Text(gw.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              if (gw.isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF81C784).withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: const Text('ACTIVE',
                      style: TextStyle(
                          color: Color(0xFF81C784),
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(gw.endpoint.isNotEmpty ? gw.endpoint : '(no endpoint)',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (gw.senderId.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Sender: ${gw.senderId}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
                icon: const Icon(Icons.edit_outlined,
                    color: Color(0xFF4FC3F7), size: 20),
                tooltip: 'Edit',
                onPressed: () =>
                    _showGatewayDialog(context, cfg, gw),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Colors.red.shade300, size: 20),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, cfg, gw),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, ConfigProvider cfg, SmsGateway gw) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E42),
        title: const Text('Delete Provider',
            style: TextStyle(color: Colors.white)),
        content: Text('Delete "${gw.name}"? This cannot be undone.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              cfg.deleteSmsGateway(gw.id);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

void _showGatewayDialog(
    BuildContext context, ConfigProvider cfg, SmsGateway? existing) {
  final isEdit = existing != null;
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
  final endpointCtrl =
      TextEditingController(text: existing?.endpoint ?? '');
  final senderCtrl =
      TextEditingController(text: existing?.senderId ?? '');

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A2E42),
      title: Text(isEdit ? 'Edit Provider' : 'Add Provider',
          style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogField(controller: nameCtrl, label: 'Provider Name'),
            const SizedBox(height: 12),
            _DialogField(
                controller: keyCtrl, label: 'API Key', obscure: true),
            const SizedBox(height: 12),
            _DialogField(
                controller: endpointCtrl,
                label: 'Endpoint URL',
                hint: 'https://api.example.com/sms'),
            const SizedBox(height: 12),
            _DialogField(
                controller: senderCtrl,
                label: 'Sender ID (optional)'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child:
              const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4FC3F7),
            foregroundColor: const Color(0xFF0D1B2A),
          ),
          icon: const Icon(Icons.save, size: 18),
          label: Text(isEdit ? 'Update' : 'Add'),
          onPressed: () {
            final name = nameCtrl.text.trim();
            final key = keyCtrl.text.trim();
            final endpoint = endpointCtrl.text.trim();
            if (name.isEmpty || key.isEmpty || endpoint.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('Name, API Key, and Endpoint are required'),
                backgroundColor: Colors.red,
              ));
              return;
            }
            final gw = SmsGateway(
              id: existing?.id ?? '',
              name: name,
              apiKey: key,
              endpoint: endpoint,
              senderId: senderCtrl.text.trim(),
              isActive: existing?.isActive ?? false,
            );
            if (isEdit) {
              cfg.updateSmsGateway(gw);
            } else {
              cfg.addSmsGateway(gw);
            }
            Navigator.pop(ctx);
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
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 2),
        ),
      ),
    );
  }
}
