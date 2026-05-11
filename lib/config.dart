import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static String apiIp = '192.168.1.116';
  static String apiPort = '3005';
  static String dbServer = '192.168.1.250';
  static String dbName = 'eazysoftdb';
  static String dbPort = '1433';

  static String get baseUrl => 'http://$apiIp:$apiPort';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    apiIp = prefs.getString('API_IP') ?? '192.168.1.116';
    apiPort = prefs.getString('API_PORT') ?? '3005';
    dbServer = prefs.getString('DB_SERVER') ?? '192.168.1.250';
    dbName = prefs.getString('DB_NAME') ?? 'eazysoftdb';
    dbPort = prefs.getString('DB_PORT') ?? '1433';
  }

  static Future<void> save({
    required String ip,
    required String port,
    required String server,
    required String name,
    required String dPort,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('API_IP', ip);
    await prefs.setString('API_PORT', port);
    await prefs.setString('DB_SERVER', server);
    await prefs.setString('DB_NAME', name);
    await prefs.setString('DB_PORT', dPort);

    apiIp = ip;
    apiPort = port;
    dbServer = server;
    dbName = name;
    dbPort = dPort;
  }
}
