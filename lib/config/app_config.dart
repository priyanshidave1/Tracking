// lib/config/app_config.dart

class AppConfig {
  // ─── Change only this IP to your machine's IP ───
  static const String _machineIp =
      "192.168.1.193"; // run ipconfig to find yours

  // ─── Franchise MVC ports from launchSettings ───
  static const String _httpPort = "5089";
  static const String _httpsPort = "7155";

  // Always use HTTPS because program.cs has UseHttpsRedirection
  static const String hubUrl =
      "https://$_machineIp:$_httpsPort/userTrackingHub";
}
