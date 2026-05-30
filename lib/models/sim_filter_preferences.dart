import 'checkout_layout.dart';

/// Local per-handset SIM filter state (SIM 1 and SIM 2 are fully independent).
class SimFilterPreferences {
  /// Stored values for SMS matching (`16216` = DBBL Rocket short code).
  static const defaultSenders = ['bKash', 'NAGAD', '16216', 'Upay'];

  final bool sim1Active;
  final List<String> sim1AllowedSenders;
  final String sim1Number;
  final List<String> sim1ProviderTags;
  final List<String> sim1CustomSenders;
  final bool sim2Active;
  final List<String> sim2AllowedSenders;
  final String sim2Number;
  final List<String> sim2ProviderTags;
  final List<String> sim2CustomSenders;
  final List<CheckoutNumberSlot> bankAccounts;

  const SimFilterPreferences({
    required this.sim1Active,
    required this.sim1AllowedSenders,
    this.sim1Number = '',
    this.sim1ProviderTags = const [],
    this.sim1CustomSenders = const [],
    required this.sim2Active,
    required this.sim2AllowedSenders,
    this.sim2Number = '',
    this.sim2ProviderTags = const [],
    this.sim2CustomSenders = const [],
    this.bankAccounts = const [],
  });

  factory SimFilterPreferences.defaults() => SimFilterPreferences(
        sim1Active: false,
        sim1AllowedSenders: List<String>.from(defaultSenders),
        sim2Active: false,
        sim2AllowedSenders: List<String>.from(defaultSenders),
        bankAccounts: const [],
      );

  SimFilterPreferences copyWith({
    bool? sim1Active,
    List<String>? sim1AllowedSenders,
    String? sim1Number,
    List<String>? sim1ProviderTags,
    List<String>? sim1CustomSenders,
    bool? sim2Active,
    List<String>? sim2AllowedSenders,
    String? sim2Number,
    List<String>? sim2ProviderTags,
    List<String>? sim2CustomSenders,
    List<CheckoutNumberSlot>? bankAccounts,
  }) =>
      SimFilterPreferences(
        sim1Active: sim1Active ?? this.sim1Active,
        sim1AllowedSenders: sim1AllowedSenders ?? this.sim1AllowedSenders,
        sim1Number: sim1Number ?? this.sim1Number,
        sim1ProviderTags: sim1ProviderTags ?? this.sim1ProviderTags,
        sim1CustomSenders: sim1CustomSenders ?? this.sim1CustomSenders,
        sim2Active: sim2Active ?? this.sim2Active,
        sim2AllowedSenders: sim2AllowedSenders ?? this.sim2AllowedSenders,
        sim2Number: sim2Number ?? this.sim2Number,
        sim2ProviderTags: sim2ProviderTags ?? this.sim2ProviderTags,
        sim2CustomSenders: sim2CustomSenders ?? this.sim2CustomSenders,
        bankAccounts: bankAccounts ?? this.bankAccounts,
      );

  bool matches(SimFilterPreferences other) =>
      sim1Active == other.sim1Active &&
      sim2Active == other.sim2Active &&
      sim1Number == other.sim1Number &&
      sim2Number == other.sim2Number &&
      _listEq(sim1AllowedSenders, other.sim1AllowedSenders) &&
      _listEq(sim2AllowedSenders, other.sim2AllowedSenders) &&
      _listEq(sim1ProviderTags, other.sim1ProviderTags) &&
      _listEq(sim2ProviderTags, other.sim2ProviderTags) &&
      _listEq(sim1CustomSenders, other.sim1CustomSenders) &&
      _listEq(sim2CustomSenders, other.sim2CustomSenders) &&
      _bankAccountsEq(bankAccounts, other.bankAccounts);

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _bankAccountsEq(List<CheckoutNumberSlot> a, List<CheckoutNumberSlot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.bankName != y.bankName ||
          x.accountName != y.accountName ||
          x.branch != y.branch ||
          x.phone != y.phone ||
          x.enabled != y.enabled ||
          x.position != y.position) {
        return false;
      }
    }
    return true;
  }
}
