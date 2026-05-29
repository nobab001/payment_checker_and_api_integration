import 'dart:ui';

import 'package:flutter/material.dart';

/// Full-screen lock while a child device waits for parent approval (VPS polling).
class ApprovalOverlay extends StatelessWidget {
  final String title;
  final String message;
  final Widget? footer;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final String? maintenanceMessage;

  const ApprovalOverlay({
    super.key,
    this.title = 'Waiting for Parent Approval...',
    this.message =
        'The parent device must approve this sign-in from the Devices tab before you can use the app.',
    this.footer,
    this.onRefresh,
    this.refreshing = false,
    this.maintenanceMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          Center(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (refreshing)
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    else
                      Icon(Icons.phonelink_lock_rounded,
                          size: 48, color: Colors.orange.shade800),
                    const SizedBox(height: 22),
                    Text(
                      maintenanceMessage ?? title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: maintenanceMessage != null
                                ? Colors.red.shade800
                                : null,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      maintenanceMessage != null
                          ? 'Check that START-SERVER.bat is running on your PC and the API URL is correct.'
                          : message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                    ),
                    if (onRefresh != null) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: refreshing ? null : onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Status'),
                      ),
                    ],
                    if (footer != null) ...[
                      const SizedBox(height: 12),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
