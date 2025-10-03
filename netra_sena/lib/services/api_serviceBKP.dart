// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
// === Set this correctly for your environment ===
// Android emulator: http://10.0.2.2:3000

// iOS simulator: http://localhost:3000

// Real device: http://<PC_LAN_IP>:3000
//static const String backendBaseUrl = 'http://10.0.2.2:3000';
  static const String backendBaseUrl = 'https://ai-tollgate-surveillance-1.onrender.com';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

// Token helpers (do NOT change these — other parts of app rely on them)
  Future<void> saveToken(String token) => _secureStorage.write(key: 'jwt', value: token);
  Future<String?> getToken() => _secureStorage.read(key: 'jwt');
  Future<void> deleteToken() => _secureStorage.delete(key: 'jwt');

  Map<String, String> _jsonHeaders({String? token}) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

// -----------------------------
// LOGIN (keep as-is, robust)
// -----------------------------
  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = Uri.parse('$backendBaseUrl/login');
    try {
      print('ApiService.login -> POST $uri with email=$email');
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email, 'password': password}))
          .timeout(const Duration(seconds: 15));

      print('ApiService.login -> statusCode: ${resp.statusCode}');
      print('ApiService.login -> raw body: ${resp.body}');

      dynamic bodyParsed;
      try {
        bodyParsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      } catch (jsonErr) {
        print('ApiService.login -> JSON decode failed: $jsonErr');
        return {
          'ok': false,
          'message': 'Server returned non-JSON response (status ${resp.statusCode}). Response body: ${resp.body}'
        };
      }

      if (resp.statusCode == 200) {
        if (bodyParsed is Map && bodyParsed['token'] != null) await saveToken(bodyParsed['token']);
        return {'ok': true, 'data': bodyParsed};
      } else {
        final msg = (bodyParsed is Map && bodyParsed['message'] != null) ? bodyParsed['message'] : 'Login failed (${resp.statusCode})';
        return {'ok': false, 'message': msg, 'status': resp.statusCode, 'raw': resp.body};
      }
    } catch (e) {
      print('ApiService.login -> exception: $e');
      return {'ok': false, 'message': 'Network error: $e'};
    }


  }

// -----------------------------
// Protected GET example
// -----------------------------
  Future<Map<String, dynamic>> getLogs() async {
    final token = await getToken();
    final uri = Uri.parse('$backendBaseUrl/api/logs');
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': jsonDecode(resp.body)};
      } else if (resp.statusCode == 401) {
        return {'ok': false, 'message': 'Unauthorized', 'status': 401};
      } else {
        return {'ok': false, 'message': 'Failed to fetch logs (${resp.statusCode})'};
      }
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

// -----------------------------
// VERIFY (multipart) - improved
// Note: driverImage is optional now. We add only non-null text fields.
// -----------------------------
  Future<Map<String, dynamic>> verifyDriver({
    String? dlNumber,
    String? rcNumber,
    String? location,
    String? tollgate,
    File? driverImage,

  }) async {
    final token = await getToken();
    final uri = Uri.parse('$backendBaseUrl/api/verify');
    final request = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';

// Add only non-null/non-empty fields
    if (dlNumber != null && dlNumber.trim().isNotEmpty) request.fields['dl_number'] = dlNumber.trim();
    if (rcNumber != null && rcNumber.trim().isNotEmpty) request.fields['rc_number'] = rcNumber.trim();
    if (location != null && location.trim().isNotEmpty) request.fields['location'] = location.trim();
    if (tollgate != null && tollgate.trim().isNotEmpty) request.fields['tollgate'] = tollgate.trim();

    if (driverImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'driverImage',
          driverImage.path,
          filename: driverImage.path.split(Platform.pathSeparator).last,
        ),
      );
    }

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed);

      dynamic body;
      try {
        body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      } catch (_) {
        body = {'raw': resp.body};
      }

      if (resp.statusCode == 200) return {'ok': true, 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Verify failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network/upload error: $e'};
    }


  }

// -----------------------------
// OCR endpoints (multipart)
// - POST /api/ocr/dl (field: dlImage)
// - POST /api/ocr/rc (field: rcImage)
// -----------------------------
  Future<Map<String, dynamic>> ocrDL(File dlImage) async {
    final uri = Uri.parse('$backendBaseUrl/api/ocr/dl');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';

    request.files.add(await http.MultipartFile.fromPath('dlImage', dlImage.path,
        filename: dlImage.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 200) {
        return {'ok': true, 'extracted_text': body['extracted_text']};
      }
      return {'ok': false, 'message': body['message'] ?? 'OCR DL failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }


  }

  Future<Map<String, dynamic>> ocrRC(File rcImage) async {
    final uri = Uri.parse('$backendBaseUrl/api/ocr/rc');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';

    request.files.add(await http.MultipartFile.fromPath('rcImage', rcImage.path,
        filename: rcImage.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 200) {
        return {'ok': true, 'extracted_text': body['extracted_text']};
      }
      return {'ok': false, 'message': body['message'] ?? 'OCR RC failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }


  }

// -----------------------------
// Blacklist suspect upload (multipart: name + photo -> field 'photo')
// -----------------------------
  Future<Map<String, dynamic>> addSuspect({required String name, required File photo}) async {
    final uri = Uri.parse('$backendBaseUrl/api/blacklist/suspect');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';

    request.fields['name'] = name;
    request.files.add(await http.MultipartFile.fromPath('photo', photo.path,
        filename: photo.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 201) {
        return {'ok': true, 'message': body['message'] ?? 'Suspect added'};
      }
      return {'ok': false, 'message': body['message'] ?? 'Add suspect failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network/upload error: $e'};
    }


  }

// -----------------------------
// Add to blacklist (JSON body) -> POST /api/blacklist
// payload must include at least: { 'type': 'dl'|'rc', 'number': '...' }
// -----------------------------
  Future<Map<String, dynamic>> addToBlacklist(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$backendBaseUrl/api/blacklist');
    final token = await getToken();
    try {
      final resp = await http
          .post(uri, headers: _jsonHeaders(token: token), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 200) {
        return {'ok': true, 'message': body['message'] ?? 'Added to blacklist'};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

// -----------------------------
// Mark blacklist entry as valid -> PUT /api/blacklist/:type/:id
// -----------------------------
  Future<Map<String, dynamic>> markBlacklistValid({required String type, required String id}) async {
    final uri = Uri.parse('$backendBaseUrl/api/blacklist/$type/$id');
    final token = await getToken();
    try {
      final resp = await http.put(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 200) return {'ok': true, 'message': body['message'] ?? 'Marked valid'};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

// -----------------------------
// Get blacklisted DLs / RCs with pagination & optional search
// - GET /api/blacklist/dl
// - GET /api/blacklist/rc
// Response shape: { data: [...], total, page, pages }
// -----------------------------
  Future<Map<String, dynamic>> getBlacklistedDLs({int page = 1, int limit = 50, String search = ''}) async {
    final uri = Uri.parse(
        '$backendBaseUrl/api/blacklist/dl?page=$page&limit=$limit${search.isNotEmpty ? '&search=${Uri.encodeQueryComponent(search)}' : ''}');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        return {'ok': true, 'data': body};
      }
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> getBlacklistedRCs({int page = 1, int limit = 50, String search = ''}) async {
    final uri = Uri.parse(
        '$backendBaseUrl/api/blacklist/rc?page=$page&limit=$limit${search.isNotEmpty ? '&search=${Uri.encodeQueryComponent(search)}' : ''}');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        return {'ok': true, 'data': body};
      }
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

// -----------------------------
// User management
// - GET /api/users
// - POST /api/users
// - DELETE /api/users/:userId
// -----------------------------
  Future<Map<String, dynamic>> getUsers() async {
    final uri = Uri.parse('$backendBaseUrl/api/users');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': jsonDecode(resp.body)};
      }
      return {'ok': false, 'message': 'Failed to fetch users (${resp.statusCode})'};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> addUser({required String name, required String email, required String password, required String role}) async {
    final uri = Uri.parse('$backendBaseUrl/api/users');
    final token = await getToken();
    try {
      final resp = await http
          .post(uri, headers: _jsonHeaders(token: token), body: jsonEncode({'name': name, 'email': email, 'password': password, 'role': role}))
          .timeout(const Duration(seconds: 12));
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 201) return {'ok': true, 'userId': body['userId'], 'message': body['message']};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    final uri = Uri.parse('$backendBaseUrl/api/users/$userId');
    final token = await getToken();
    try {
      final resp = await http.delete(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 200) return {'ok': true, 'message': body['message'] ?? 'Deleted'};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

// -----------------------------
// Server logout (update isActive flag) -> POST /api/logout/:userId
// Note: this also deletes local token on success.
// -----------------------------
  Future<Map<String, dynamic>> logoutServer(String userId) async {
    final uri = Uri.parse('$backendBaseUrl/api/logout/$userId');
    final token = await getToken();
    try {
      final resp = await http.post(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 200) {
        await deleteToken();
        return {'ok': true, 'message': body['message'] ?? 'Logged out'};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed to logout (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

// -----------------------------
// Local logout only (keeps server untouched)
// -----------------------------
  Future<void> localLogout() => deleteToken();

// -----------------------------
// DL usage -> GET /api/dl-usage/:dl_number
// -----------------------------
  Future<Map<String, dynamic>> getDLUsage(String dlNumber) async {
    final encoded = Uri.encodeComponent(dlNumber);
    final uri = Uri.parse('$backendBaseUrl/api/dl-usage/$encoded');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 0) {
// defensive: though http package doesn't return 0, keep consistent structure
        return {'ok': false, 'message': 'Network error'};
      }
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': jsonDecode(resp.body)};
      }
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }
}