import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1A237E);
  static const Color bkash = Color(0xFFE2136E);
  static const Color nagad = Color(0xFFEF4123);
  static const Color rocket = Color(0xFF6A2C91);
  static const Color upay = Color(0xFF00B99B);
  static const Color background = Color(0xFFF5F7FA);
}

class AppStrings {
  static const String appName = 'Payment Checker';
  static const String historyFile = 'sms_history.json';
}

class OperatorConfig {
  final String name;
  final Color color;
  final String key;
  final IconData icon;

  const OperatorConfig({
    required this.name,
    required this.color,
    required this.key,
    required this.icon,
  });
}

const List<OperatorConfig> kOperators = [
  OperatorConfig(
    name: 'bKash',
    color: AppColors.bkash,
    key: 'bKash',
    icon: Icons.account_balance_wallet,
  ),
  OperatorConfig(
    name: 'Nagad',
    color: AppColors.nagad,
    key: 'Nagad',
    icon: Icons.payments,
  ),
  OperatorConfig(
    name: 'Rocket',
    color: AppColors.rocket,
    key: 'Rocket',
    icon: Icons.rocket_launch,
  ),
  OperatorConfig(
    name: 'Upay',
    color: AppColors.upay,
    key: 'Upay',
    icon: Icons.trending_up,
  ),
];
