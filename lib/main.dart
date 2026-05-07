// Default Flutter entry — User App ([bootUserApp]).
// Debug from VS Code: pick launch profile **Debug User App** (not Debug Admin App).
// Equivalent alias entry point: [lib/main_user.dart].
import 'dart:convert';
import 'dart:io';

import 'app.dart';

// #region agent log
void _agentDebugLog(
  String location,
  String message, {
  String? hypothesisId,
  Map<String, dynamic>? data,
}) {
  try {
    final payload = <String, dynamic>{
      'sessionId': '47c5a3',
      'location': location,
      'message': message,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (hypothesisId != null) 'hypothesisId': hypothesisId,
      if (data != null) 'data': data,
    };
    final path =
        '${Directory.current.path}${Platform.pathSeparator}debug-47c5a3.log';
    File(path).writeAsStringSync(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}
// #endregion

void main() {
  // #region agent log
  _agentDebugLog(
    'main.dart:main',
    'main() entered',
    hypothesisId: 'H_run',
    data: {'cwd': Directory.current.path},
  );
  // #endregion
  bootUserApp();
}
