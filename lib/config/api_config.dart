/// Single default base URL for the Node API (change here between builds).
///
/// Runtime override: SharedPreferences via [ApiBaseUrlPrefs] (Profile → SMS filter & forward).
/// All HTTP traffic should go through [ApiService], which merges this default with overrides.
const String kDefaultApiBaseUrl = 'http://127.0.0.1:3000';

/// Strip trailing slashes for consistent URI joining.
String normalizeApiBaseUrl(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');
