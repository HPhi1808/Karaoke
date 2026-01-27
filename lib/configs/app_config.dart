import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get(String key) {

    String value = '';

    switch (key) {
      case 'BASE_URL':
        value = const String.fromEnvironment('BASE_URL');
        break;
      case 'SUPABASE_URL':
        value = const String.fromEnvironment('SUPABASE_URL');
        break;
      case 'SUPABASE_ANON_KEY':
        value = const String.fromEnvironment('SUPABASE_ANON_KEY');
        break;
      case 'REDIRECT_URL':
        value = const String.fromEnvironment('REDIRECT_URL');
        break;
      case 'ONE_SIGNAL_APP_ID':
        value = const String.fromEnvironment('ONE_SIGNAL_APP_ID');
        break;
      case 'WEB_CLIENT_ID':
        value = const String.fromEnvironment('WEB_CLIENT_ID');
        break;
    }

    if (value.isEmpty) {
      return dotenv.env[key] ?? '';
    }
    return value;
  }
  static String get baseUrl => get('BASE_URL');
  static String get supabaseUrl => get('SUPABASE_URL');
  static String get supabaseAnonKey => get('SUPABASE_ANON_KEY');
  static String get redirectUrl => get('REDIRECT_URL');
  static String get oneSignalAppId => get('ONE_SIGNAL_APP_ID');
  static String get webClientId => get('WEB_CLIENT_ID');
}