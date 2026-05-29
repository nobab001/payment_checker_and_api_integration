import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Persists uncaught errors to app documents (readable via adb on release builds).
class AppCrashLogger {
  AppCrashLogger._();

  static File? _logFile;

  static Future<void> install() async {
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      log(
        'FlutterError',
        details.exceptionAsString(),
        details.stack,
      );
      if (prevFlutter != null) {
        prevFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      log('PlatformDispatcher', error, stack);
      return true;
    };
  }

  static void log(String tag, Object message, [StackTrace? stack]) {
    final line =
        '[${DateTime.now().toIso8601String()}][$tag] $message${stack != null ? '\n$stack' : ''}\n';
    developer.log(message.toString(), name: tag, error: message, stackTrace: stack);
    if (kDebugMode) {
      debugPrint(line);
    }
    unawaited(_append(line));
  }

  static Future<void> _append(String line) async {
    try {
      _logFile ??= File(
        '${(await getApplicationDocumentsDirectory()).path}/app_crash.log',
      );
      await _logFile!.writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }
}

/// Catches build-time errors in the widget subtree.
class AppErrorBoundary extends StatefulWidget {
  const AppErrorBoundary({super.key, required this.child});

  final Widget child;

  @override
  State<AppErrorBoundary> createState() => _AppErrorBoundaryState();
}

class _AppErrorBoundaryState extends State<AppErrorBoundary> {
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(
                'Something went wrong.\n\n$_error\n\n'
                'If this persists, sign out and sign in again, or use Profile → Restore parent role.',
              ),
            ),
          ),
        ),
      );
    }
    return widget.child;
  }

  @override
  void reassemble() {
    super.reassemble();
    _error = null;
  }
}
