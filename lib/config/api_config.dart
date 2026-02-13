class ApiConfig {
  const ApiConfig._();

  /// Pass with: --dart-define=SERVER_URL=https://your-api-domain.com
  static const String serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'https://api.honorfirstsecurity.com',
  );
}
