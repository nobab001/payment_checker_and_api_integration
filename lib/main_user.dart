// ── User App entry point ──────────────────────────────────────────────────────
//
// Same entry as [lib/main.dart]; either target works.
//
// Run from VS Code: launch "Debug User App" (uses lib/main.dart + `--flavor user` on Android).
// Terminal (Android): `flutter run` / `-t lib/main.dart` — pubspec `default-flavor: user` applies.
// Terminal (Admin): always `flutter run -t lib/main_admin.dart --flavor admin` (overrides default).
// Web: `flutter run -t lib/main.dart -d chrome` (no `--flavor`).
//
// Android applicationId: com.yourdomain.userapp  (root `user` flavor)
// User auth: VPS API at AppConfig.apiBaseUrl ([utils/constants.dart]).
// ─────────────────────────────────────────────────────────────────────────────
import 'app.dart';
void main() => bootUserApp();


