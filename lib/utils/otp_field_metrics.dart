import 'package:flutter/material.dart';

import 'constants.dart';

/// Shared sizing and decoration for ৬-digit OTP rows app-wide.
class OtpFieldMetrics {
  const OtpFieldMetrics._();

  static const int length = 6;

  static const double preferredBoxWidth = 48;

  static const double preferredBoxHeight = 58;

  static const double maxBoxWidth = 50;

  /// Gap between boxes; kept modest so 6 boxes fit without overflow.
  static const double gap = 8;

  static const double borderRadius = 10;

  static const double digitFontSize = 22;

  /// Total row width for [length] boxes at [boxWidth] and [gap].
  static double rowWidth(double boxWidth) =>
      boxWidth * length + gap * (length - 1);

  /// Width per box so the full row never exceeds [maxWidth] (no overflow).
  static double boxWidthFor(double maxWidth) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return preferredBoxWidth;
    }
    final totalGaps = gap * (length - 1);
    final fit = (maxWidth - totalGaps) / length;
    if (fit >= preferredBoxWidth) {
      return preferredBoxWidth;
    }
    return fit.floorToDouble().clamp(36.0, maxBoxWidth);
  }

  static BoxDecoration boxDecoration({required bool focused, required bool enabled}) {
    return BoxDecoration(
      color: enabled ? Colors.white : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: focused ? AppColors.primary : Colors.grey.shade300,
        width: focused ? 2 : 1.2,
      ),
    );
  }
}
