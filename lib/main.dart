// Default Flutter entry — User App ([bootUserApp]).
// Debug from VS Code: pick launch profile **Debug User App** (not Debug Admin App).
// Equivalent alias entry point: [lib/main_user.dart].
//
// Global providers (including `Provider<ApiService>` for [DeviceManagerPage] and
// the rest of the tree) are registered in [bootUserApp] → `lib/app.dart` [MultiProvider].
// Always use that entry so `context.read<ApiService>()` resolves correctly.
import 'app.dart';

void main() => bootUserApp();