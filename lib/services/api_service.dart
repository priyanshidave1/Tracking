import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiConfig {
  static const _connectionString =
      r"Server=192.168.1.251;Database=Franchise 1;User=sa;Password=SQL@19#$M@)@$;Encrypt=False;MultipleActiveResultSets=True;TrustServerCertificate=True";
}

class ApiService {
  static const String _baseUrl = 'https://localhost:44371';

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$_baseUrl/$endpoint');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ConnectionString': ApiConfig._connectionString,
      },
      body: jsonEncode(data),
    );

    final decoded = jsonDecode(response.body);
    return {'statusCode': response.statusCode, ...decoded};
  }
}
