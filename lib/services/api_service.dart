import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:git_leave/utils/global_variables.dart';

class ApiService {
  
  // ─── AUTH ───────────────────────────────────────────

  // Login
  static Future<Map<String, dynamic>> login(
      String idcardno, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$ipAddress/api/LoginData'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idcardno': idcardno, 'password': password}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Register
  static Future<Map<String, dynamic>> register(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$ipAddress/api/Registerinsert'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─── DEVICE ─────────────────────────────────────────

  // Register FCM Token
  static Future<Map<String, dynamic>> registerDevice(
      String idcardno, String fcmToken) async {
    try {
      final response = await http.post(
        Uri.parse('$ipAddress/api/userdevice'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idcardno': idcardno, 'fcmToken': fcmToken}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}

  // ─── LOCATION ───────────────────────────────────────

//   // Send Single Location
//   static Future<Map<String, dynamic>> sendLocation(
//       String idcardno, double lat, double lng) async {
//     try {
//       final response = await http.post(
//         Uri.parse('$ipAddress/api/sendNewLocation'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'idcardno': idcardno,
//           'lat': lat,
//           'lng': lng,
//           'timestamp': DateTime.now().toIso8601String(),
//         }),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       return {'error': e.toString()};
//     }
//   }

//   // Sync Batch Locations
//   static Future<Map<String, dynamic>> syncLocationsBatch(
//       String idcardno, List<Map<String, dynamic>> locations) async {
//     try {
//       final response = await http.post(
//         Uri.parse('$ipAddress/api/syncLocationsBatch'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'idcardno': idcardno, 'locations': locations}),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       return {'error': e.toString()};
//     }
//   }

//   // ─── EMPLOYEE DATA ───────────────────────────────────

//   // Get Employee Details
//   static Future<Map<String, dynamic>> getEmployee(String idcardno) async {
//     try {
//       final response = await http.get(
//         Uri.parse('$ipAddress/api/employee/$idcardno'),
//         headers: {'Content-Type': 'application/json'},
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       return {'error': e.toString()};
//     }
//   }

//   // Get Employee Sessions
//   static Future<Map<String, dynamic>> getEmployeeSessions(
//       String idcardno) async {
//     try {
//       final response = await http.get(
//         Uri.parse('$ipAddress/api/employee/$idcardno/sessions'),
//         headers: {'Content-Type': 'application/json'},
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       return {'error': e.toString()};
//     }
//   }

//   // Get Employee Stats
//   static Future<Map<String, dynamic>> getEmployeeStats(
//       String idcardno) async {
//     try {
//       final response = await http.get(
//         Uri.parse('$ipAddress/api/employee/$idcardno/stats'),
//         headers: {'Content-Type': 'application/json'},
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       return {'error': e.toString()};
//     }
//   }
// }