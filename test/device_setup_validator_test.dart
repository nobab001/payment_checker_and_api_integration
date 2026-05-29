import 'package:flutter_test/flutter_test.dart';
import 'package:payment_checker/models/sim_filter_preferences.dart';
import 'package:payment_checker/utils/device_setup_validator.dart';

void main() {
  test('rejects save when no SIM is active', () {
    const prefs = SimFilterPreferences(
      sim1Active: false,
      sim1AllowedSenders: [],
      sim2Active: false,
      sim2AllowedSenders: [],
    );
    expect(DeviceSetupValidator.validatePreferences(prefs), isNotNull);
  });

  test('accepts active SIM with phone and provider tag', () {
    const prefs = SimFilterPreferences(
      sim1Active: true,
      sim1AllowedSenders: [],
      sim1Number: '01712345678',
      sim1ProviderTags: ['bKash Personal'],
      sim2Active: false,
      sim2AllowedSenders: [],
    );
    expect(DeviceSetupValidator.validatePreferences(prefs), isNull);
    expect(DeviceSetupValidator.isDeviceConfigured(prefs), isTrue);
  });

  test('rejects active SIM without admin template', () {
    const prefs = SimFilterPreferences(
      sim1Active: true,
      sim1AllowedSenders: [],
      sim1Number: '01712345678',
      sim2Active: false,
      sim2AllowedSenders: [],
    );
    expect(DeviceSetupValidator.validatePreferences(prefs), isNotNull);
  });

  test('rejects custom sender only without admin template', () {
    const prefs = SimFilterPreferences(
      sim1Active: true,
      sim1AllowedSenders: [],
      sim1Number: '01712345678',
      sim1CustomSenders: ['bKash'],
      sim2Active: false,
      sim2AllowedSenders: [],
    );
    expect(DeviceSetupValidator.validatePreferences(prefs), isNotNull);
  });
}
