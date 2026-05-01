import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:my_app/models/shift_entry.dart';
import 'package:my_app/models/staff_location_history.dart';

class ApiConfig {
/*
  static const connectionString =
      r"Server=192.168.1.251;Database=Franchise 1;User=sa;Password=SQL@19#$M@)@$;Encrypt=False;MultipleActiveResultSets=True;TrustServerCertificate=True";
}
*/

static const connectionString =
      r"Server=122-244-72-148\SQLEXPRESS;Database=dev_db_crm;User=sa;Password=H57kkWA!otx2&grn;Encrypt=False;MultipleActiveResultSets=True;TrustServerCertificate=True";
}

class ApiService {
  static const String _baseUrl = 'https://devgateway.apcabinets.com.au';
 // static const String _baseUrl = 'https://localhost:44371';

  // Add alongside your existing post() method inside ApiService

  static Future<Map<String, dynamic>> get(
      String endpoint,
      Map<String, String> queryParams,
      ) async {
    final uri = Uri.parse('$_baseUrl/$endpoint')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ConnectionString': ApiConfig.connectionString,
      },
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return {'statusCode': response.statusCode, ...decoded};
  }

  /// Fetch all shifts for a staff member, with an optional date filter.
  static Future<List<StaffShiftApiModel>> getStaffShifts({
    required String staffId,
    DateTime? targetDate,
  }) async {
    final params = <String, String>{'staffId': staffId};
    if (targetDate != null) {
      // ISO-8601 date string the .NET controller expects
      params['targetDate'] = targetDate.toIso8601String();
    }

    final result = await get('Franchise/api/StaffTimesheet/getallstaffshifts', params);

    if (result['statusCode'] != 200) return [];

    final data = result['data'];
    if (data == null || data is! List) return [];

    return (data as List)
        .map((e) => StaffShiftApiModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }


  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$_baseUrl/$endpoint');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ConnectionString': ApiConfig.connectionString,
      },
      body: jsonEncode(data),
    );

    final decoded = jsonDecode(response.body);
    return {'statusCode': response.statusCode, ...decoded};
  }
  /// Fetches location history for a staff member's shift.
  static Future<List<StaffLocationHistory>> getStaffLocationHistory({
    required String staffId,
    required String shiftId,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final params = <String, String>{
      'staffId': staffId,
      'shiftId': shiftId,
      'date': '${targetDate.year.toString().padLeft(4, '0')}-'
          '${targetDate.month.toString().padLeft(2, '0')}-'
          '${targetDate.day.toString().padLeft(2, '0')}',
    };

    final result = await get(
      'Franchise/api/StaffTimesheet/getstafflocationhistory',
      params,
    );

    if (result['statusCode'] != 200) return [];

    final data = result['data'];
    if (data == null || data is! List) return [];

    // Sort chronologically so the polyline draws in order
    final history = (data as List)
        //.map((e) => StaffLocationHistory.fromJson(e as Map<String, dynamic>))
        .map((e)=> StaffLocationHistory.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return history;
  }
}
