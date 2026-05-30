import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checkout_layout.dart';
import '../models/sim_filter_preferences.dart';
import '../services/sms_automation_prefs.dart';
import '../utils/device_setup_validator.dart';
import '../utils/sender_display_utils.dart';

/// Persists SIM 1 / SIM 2 filters in SharedPreferences with **separate keys**
/// so the two lists never overwrite each other.
class SimFilterLocalRepository {
  SimFilterLocalRepository._();
  static final SimFilterLocalRepository instance = SimFilterLocalRepository._();

  static const String kSim1Active = 'pcu_sim_1_active';
  static const String kSim1AllowedSenders = 'pcu_sim_1_allowed_senders';
  static const String kSim1Number = 'pcu_sim_1_number';
  static const String kSim1ProviderTags = 'pcu_sim_1_provider_tags';
  static const String kSim1CustomSenders = 'pcu_sim_1_custom_senders';
  static const String kSim2Active = 'pcu_sim_2_active';
  static const String kBankAccounts = 'pcu_device_bank_accounts_v1';
  static const String kSim2AllowedSenders = 'pcu_sim_2_allowed_senders';
  static const String kSim2Number = 'pcu_sim_2_number';
  static const String kSim2ProviderTags = 'pcu_sim_2_provider_tags';
  static const String kSim2CustomSenders = 'pcu_sim_2_custom_senders';

  /// Legacy alias keys (read-only fallback).
  static const String kLegacySim1List = 'pcu_sim1_list';
  static const String kLegacySim2List = 'pcu_sim2_list';

  /// Set after first default seed or user taps Save.
  static const String kSeeded = 'pcu_sim_filter_seeded_v2';
  static const String kSchemaVersion = 'pcu_sim_filter_schema_version';
  static const int kCurrentSchemaVersion = 3;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _sp() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<bool> isUserSeeded() async {
    final sp = await _sp();
    return sp.getBool(kSeeded) == true;
  }

  /// One-time: refill empty per-SIM lists after server sync bug (schema v2).
  Future<void> _migrateSchemaV2() async {
    final sp = await _sp();
    if ((sp.getInt(kSchemaVersion) ?? 0) >= kCurrentSchemaVersion) return;

    final p = await load();
    final sim1 = p.sim1AllowedSenders.isEmpty
        ? List<String>.from(SimFilterPreferences.defaultSenders)
        : p.sim1AllowedSenders;
    final sim2 = p.sim2AllowedSenders.isEmpty
        ? List<String>.from(SimFilterPreferences.defaultSenders)
        : p.sim2AllowedSenders;

    if (sim1.length != p.sim1AllowedSenders.length ||
        sim2.length != p.sim2AllowedSenders.length) {
      await save(
        p.copyWith(sim1AllowedSenders: sim1, sim2AllowedSenders: sim2),
      );
    }
    await sp.setInt(kSchemaVersion, kCurrentSchemaVersion);
  }

  /// v3: replace legacy `Rocket` with short code `16216` for matching.
  Future<void> _migrateSchemaV3() async {
    final sp = await _sp();
    if ((sp.getInt(kSchemaVersion) ?? 0) >= 3) return;

    final p = await load();
    final sim1 = canonicalizeAllowedSenderList(p.sim1AllowedSenders);
    final sim2 = canonicalizeAllowedSenderList(p.sim2AllowedSenders);
    if (!_listEq(sim1, p.sim1AllowedSenders) ||
        !_listEq(sim2, p.sim2AllowedSenders)) {
      await save(
        p.copyWith(sim1AllowedSenders: sim1, sim2AllowedSenders: sim2),
      );
    }
    await sp.setInt(kSchemaVersion, 3);
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Runs migrations only (safe on every app start).
  Future<void> runMigrations() async {
    await _migrateSchemaV2();
    await _migrateSchemaV3();
  }

  /// First install: seed defaults once, then always read disk.
  Future<SimFilterPreferences> ensureDefaults() async {
    final sp = await _sp();
    await runMigrations();

    if (sp.getBool(kSeeded) != true) {
      final defaults = SimFilterPreferences.defaults();
      await save(defaults);
      await sp.setBool(kSeeded, true);
      await sp.setInt(kSchemaVersion, kCurrentSchemaVersion);
      return defaults;
    }
    return loadSettings();
  }

  /// Hydrate UI / services from disk (never overwrites with empty RAM state).
  Future<SimFilterPreferences> loadSettings() async {
    await runMigrations();
    final sp = await _sp();
    await sp.reload();
    return load();
  }

  Future<SimFilterPreferences> load() async {
    final sp = await _sp();
    final sim1List =
        sp.getStringList(kSim1AllowedSenders) ??
        sp.getStringList(kLegacySim1List) ??
        const <String>[];
    final sim2List =
        sp.getStringList(kSim2AllowedSenders) ??
        sp.getStringList(kLegacySim2List) ??
        const <String>[];
    final bankAccountsRaw = sp.getString(kBankAccounts) ?? '[]';
    List<CheckoutNumberSlot> bankAccounts = const [];
    try {
      final decoded = jsonDecode(bankAccountsRaw) as List<dynamic>;
      bankAccounts = decoded
          .map(
            (e) => CheckoutNumberSlot.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {}

    return SimFilterPreferences(
      sim1Active: sp.getBool(kSim1Active) ?? false,
      sim1AllowedSenders: canonicalizeAllowedSenderList(sim1List),
      sim1Number: sp.getString(kSim1Number) ?? '',
      sim1ProviderTags: sp.getStringList(kSim1ProviderTags) ?? const [],
      sim1CustomSenders: sp.getStringList(kSim1CustomSenders) ?? const [],
      sim2Active: sp.getBool(kSim2Active) ?? false,
      sim2AllowedSenders: canonicalizeAllowedSenderList(sim2List),
      sim2Number: sp.getString(kSim2Number) ?? '',
      sim2ProviderTags: sp.getStringList(kSim2ProviderTags) ?? const [],
      sim2CustomSenders: sp.getStringList(kSim2CustomSenders) ?? const [],
      bankAccounts: bankAccounts,
    );
  }

  /// Writes all SIM keys to disk with await on every field.
  Future<void> save(SimFilterPreferences prefs) async {
    final sp = await _sp();
    final bankAccountsJson = jsonEncode(
      prefs.bankAccounts.map((e) => e.toJson()).toList(),
    );
    final ok = <bool>[
      await sp.setBool(kSim1Active, prefs.sim1Active),
      await sp.setStringList(kSim1AllowedSenders, prefs.sim1AllowedSenders),
      await sp.setString(kSim1Number, prefs.sim1Number),
      await sp.setStringList(kSim1ProviderTags, prefs.sim1ProviderTags),
      await sp.setStringList(kSim1CustomSenders, prefs.sim1CustomSenders),
      await sp.setBool(kSim2Active, prefs.sim2Active),
      await sp.setStringList(kSim2AllowedSenders, prefs.sim2AllowedSenders),
      await sp.setString(kSim2Number, prefs.sim2Number),
      await sp.setStringList(kSim2ProviderTags, prefs.sim2ProviderTags),
      await sp.setStringList(kSim2CustomSenders, prefs.sim2CustomSenders),
      await sp.setString(kBankAccounts, bankAccountsJson),
    ];
    if (kDebugMode && ok.contains(false)) {
      debugPrint('[SimFilterLocalRepository] some prefs writes returned false');
    }
  }

  /// Saves then re-reads to confirm persistence (throws if verify fails).
  Future<void> saveVerified(SimFilterPreferences prefs) async {
    await save(prefs);
    final sp = await _sp();
    await sp.setBool(kSeeded, true);
    final read = await load();
    if (!prefs.matches(read)) {
      throw StateError('SIM filter settings could not be verified after save');
    }
  }

  /// Merge server row into local prefs without wiping handset SIM setup.
  Future<void> mergeFromSimSettings({
    required bool sim1Active,
    required List<String> sim1Filters,
    required bool sim2Active,
    required List<String> sim2Filters,
  }) async {
    final local = await loadSettings();
    final configuredOnDevice =
        await SmsAutomationPrefs.isConfigured() &&
        DeviceSetupValidator.isDeviceConfigured(local);

    // User already saved SIM numbers + senders on this phone — never wipe from VPS.
    if (configuredOnDevice) {
      if (kDebugMode) {
        debugPrint(
          '[SimFilterLocalRepository] skip server merge — local SIM config is authoritative',
        );
      }
      return;
    }

    final seeded = await isUserSeeded();

    List<String> pick(List<String> server, List<String> localList) {
      if (server.isNotEmpty) return List<String>.from(server);
      if (localList.isNotEmpty) return localList;
      if (!seeded)
        return List<String>.from(SimFilterPreferences.defaultSenders);
      return localList;
    }

    await save(
      local.copyWith(
        sim1Active: sim1Active,
        sim1AllowedSenders: pick(sim1Filters, local.sim1AllowedSenders),
        sim2Active: sim2Active,
        sim2AllowedSenders: pick(sim2Filters, local.sim2AllowedSenders),
      ),
    );
  }
}
