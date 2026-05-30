import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sms_template.dart';
import 'api_service.dart';

/// Caches admin [SmsTemplate] rules for offline background parsing.
class SmsTemplateCache {
  SmsTemplateCache._();
  static final SmsTemplateCache instance = SmsTemplateCache._();

  static const _cacheKey = 'pcu_sms_templates_json_v2';
  static const _cacheAtKey = 'pcu_sms_templates_cached_at_v2';
  static const _revisionKey = 'pcu_sms_templates_revision_v1';

  List<SmsTemplate> _memory = [];
  DateTime? _cachedAt;

  List<SmsTemplate> get templates => List.unmodifiable(_memory);

  bool get hasTemplates => _memory.isNotEmpty;

  Map<String, SmsTemplate> get byCustomerPreview {
    final map = <String, SmsTemplate>{};
    for (final t in _memory) {
      map[t.customerPreview] = t;
    }
    return map;
  }

  /// Case-insensitive match (prefs may say "bKash Personal", DB "bkash personal").
  SmsTemplate? findByCustomerPreview(String preview) {
    final key = preview.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final t in _memory) {
      if (t.customerPreview.trim().toLowerCase() == key) return t;
    }
    return null;
  }

  /// Legacy grouping (multiple rows per tag collapsed — prefer [byCustomerPreview]).
  Map<String, List<SmsTemplate>> get byProviderTag {
    final map = <String, List<SmsTemplate>>{};
    for (final t in _memory) {
      map.putIfAbsent(t.customerPreview, () => []).add(t);
    }
    return map;
  }

  Future<void> refreshFromServer({bool force = false}) async {
    try {
      final result = await ApiService.instance.fetchSmsTemplatesWithRevision();
      final remoteRevision = result.revision;
      final sp = await SharedPreferences.getInstance();
      final localRevision = sp.getString(_revisionKey) ?? '';
      final revisionChanged =
          remoteRevision.isNotEmpty && remoteRevision != localRevision;

      if (!force && _memory.isNotEmpty && _isFresh() && !revisionChanged) {
        return;
      }

      _memory = result.templates;
      _cachedAt = DateTime.now();
      await _persist(result.templates);
      if (remoteRevision.isNotEmpty) {
        await sp.setString(_revisionKey, remoteRevision);
      }
    } catch (_) {
      if (_memory.isEmpty) await _loadFromDisk();
    }
  }

  bool _isFresh() {
    if (_cachedAt == null) return false;
    return DateTime.now().difference(_cachedAt!) < const Duration(hours: 12);
  }

  Future<void> _persist(List<SmsTemplate> list) async {
    final sp = await SharedPreferences.getInstance();
    final encoded = list
        .map(
          (t) => {
            'id': t.id,
            'customer_preview': t.customerPreview,
            'sender_id': t.senderId,
            'formats': t.formats,
            'is_active': t.isActive ? 1 : 0,
          },
        )
        .toList();
    await sp.setString(_cacheKey, jsonEncode(encoded));
    await sp.setString(_cacheAtKey, DateTime.now().toIso8601String());
  }

  Future<void> _loadFromDisk() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _memory = list
          .map((e) => SmsTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _cachedAt = DateTime.tryParse(sp.getString(_cacheAtKey) ?? '');
    } catch (_) {}
  }

  Future<void> ensureLoaded() async {
    if (_memory.isNotEmpty) return;
    await _loadFromDisk();
  }
}

/// @deprecated Use [SmsTemplateCache].
typedef SenderTemplateCache = SmsTemplateCache;
