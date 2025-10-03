// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // === Set this correctly for your environment ===
  // Updated to the new backend as requested.
  static const String backendBaseUrl = 'https://netrasena.onrender.com';
  static const String faceApiUrl = 'https://face-surveillance-api-777302308889.asia-south1.run.app';

  // Optional override (useful for tests / dev)
  final String baseUrlOverride;

  ApiService({this.baseUrlOverride = ''});

  String get _baseUrl => baseUrlOverride.isNotEmpty ? baseUrlOverride : backendBaseUrl;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Token helpers (do NOT change these — other parts of app rely on them)
  Future<void> saveToken(String token) => _secureStorage.write(key: 'jwt', value: token);
  Future<String?> getToken() => _secureStorage.read(key: 'jwt');
  Future<void> deleteToken() => _secureStorage.delete(key: 'jwt');

  Map<String, String> _jsonHeaders({String? token}) {
    final headers = {'Content-Type': 'application/json', 'accept': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  // -----------------------------
  // LOGIN (robust)
  // -----------------------------
  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/login');
    try {
      print('ApiService.login -> POST $uri with email=$email');
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json', 'accept': 'application/json'}, body: jsonEncode({'email': email, 'password': password}))
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
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/logs');
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': _safeJson(resp.body)};
      } else if (resp.statusCode == 401) {
        return {'ok': false, 'message': 'Unauthorized', 'status': 401};
      } else {
        return {'ok': false, 'message': 'Failed to fetch logs (${resp.statusCode})', 'body': _safeJson(resp.body)};
      }
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  // Helper to parse JSON safely
  dynamic _safeJson(String? body) {
    if (body == null || body.isEmpty) return {};
    try {
      return jsonDecode(body);
    } catch (_) {
      return {'raw': body};
    }
  }

  // -----------------------------
  // VERIFY (multipart) - improved
  // -----------------------------
  Future<Map<String, dynamic>> verifyDriver({
    String? dlNumber,
    String? rcNumber,
    String? location,
    String? tollgate,
    File? driverImage,
  }) async {
    final token = await getToken();
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/verify');
    final request = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.headers['accept'] = 'application/json';

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
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) return {'ok': true, 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Verify failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network/upload error: $e'};
    }
  }

  // -----------------------------
  // OCR endpoints (multipart)
  // -----------------------------
  Future<Map<String, dynamic>> ocrDL(File dlImage) async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/ocr/dl');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.headers['accept'] = 'application/json';

    request.files.add(await http.MultipartFile.fromPath('dlImage', dlImage.path,
        filename: dlImage.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'extracted_text': body['extracted_text'], 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'OCR DL failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> ocrRC(File rcImage) async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/ocr/rc');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.headers['accept'] = 'application/json';

    request.files.add(await http.MultipartFile.fromPath('rcImage', rcImage.path,
        filename: rcImage.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'extracted_text': body['extracted_text'], 'data': body};
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
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/blacklist/suspect');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.headers['accept'] = 'application/json';

    request.fields['name'] = name;
    request.files.add(await http.MultipartFile.fromPath('photo', photo.path,
        filename: photo.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);
      if (resp.statusCode == 201) {
        return {'ok': true, 'message': body['message'] ?? 'Suspect added', 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Add suspect failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network/upload error: $e'};
    }
  }

  // -----------------------------
  // Add to blacklist (JSON body) -> POST /api/blacklist
  // -----------------------------
  Future<Map<String, dynamic>> addToBlacklist(Map<String, dynamic> payload) async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/blacklist');
    final token = await getToken();
    try {
      final resp = await http
          .post(uri, headers: _jsonHeaders(token: token), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'message': body['message'] ?? 'Added to blacklist', 'data': body};
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
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/blacklist/$type/$id');
    final token = await getToken();
    try {
      final resp = await http.put(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) return {'ok': true, 'message': body['message'] ?? 'Marked valid', 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  // -----------------------------
  // Get blacklisted DLs / RCs with pagination & optional search
  // -----------------------------
  Future<Map<String, dynamic>> getBlacklistedDLs({int page = 1, int limit = 50, String search = ''}) async {
    final uri = Uri.parse(
        '${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/blacklist/dl?page=$page&limit=$limit${search.isNotEmpty ? '&search=${Uri.encodeQueryComponent(search)}' : ''}');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> getBlacklistedRCs({int page = 1, int limit = 50, String search = ''}) async {
    final uri = Uri.parse(
        '${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/blacklist/rc?page=$page&limit=$limit${search.isNotEmpty ? '&search=${Uri.encodeQueryComponent(search)}' : ''}');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  // -----------------------------
  // User management
  // -----------------------------
  Future<Map<String, dynamic>> getUsers() async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/users');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed to fetch users (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> addUser({required String name, required String email, required String password, required String role}) async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/users');
    final token = await getToken();
    try {
      final resp = await http
          .post(uri, headers: _jsonHeaders(token: token), body: jsonEncode({'name': name, 'email': email, 'password': password, 'role': role}))
          .timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 201) return {'ok': true, 'userId': body['userId'], 'message': body['message'], 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/users/$userId');
    final token = await getToken();
    try {
      final resp = await http.delete(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) return {'ok': true, 'message': body['message'] ?? 'Deleted', 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  // -----------------------------
  // Server logout (update isActive flag) -> POST /api/logout/:userId
  // -----------------------------
  Future<Map<String, dynamic>> logoutServer(String userId) async {
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/logout/$userId');
    final token = await getToken();
    try {
      final resp = await http.post(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        await deleteToken();
        return {'ok': true, 'message': body['message'] ?? 'Logged out', 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed to logout (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  Future<void> localLogout() => deleteToken();

  // -----------------------------
  // DL usage -> GET /api/dl-usage/:dl_number
  // -----------------------------
  Future<Map<String, dynamic>> getDLUsage(String dlNumber) async {
    final encoded = Uri.encodeComponent(dlNumber);
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/$'), '')}/api/dl-usage/$encoded');
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  // -----------------------------
  // NEW FACE SURVEILLANCE API FUNCTIONS
  // -----------------------------

  // Method to get a list of all suspects from the face API
  Future<Map<String, dynamic>> listSuspects({Map<String, String>? faceAuthHeader}) async {
    final uri = Uri.parse('$faceApiUrl/list_suspects');
    try {
      final headers = <String, String>{'accept': 'application/json'};
      if (faceAuthHeader != null) headers.addAll(faceAuthHeader);
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      } else {
        return {'ok': false, 'message': 'Failed to fetch suspect list (${resp.statusCode})', 'body': body};
      }
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  // Method to verify a face against the suspect list
  Future<Map<String, dynamic>> recognizeFace(String imagePath, {Map<String, String>? faceAuthHeader}) async {
    final uri = Uri.parse('$faceApiUrl/recognize');
    final request = http.MultipartRequest('POST', uri);
    request.headers['accept'] = 'application/json';
    if (faceAuthHeader != null) request.headers.addAll(faceAuthHeader);

    request.files.add(await http.MultipartFile.fromPath('file', imagePath,
        filename: imagePath.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Recognition failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network/upload error: $e'};
    }
  }

  // Method to add a new person to the suspect list
  Future<Map<String, dynamic>> addSuspectFromFace({required String personName, required String imagePath, Map<String, String>? faceAuthHeader}) async {
    final uri = Uri.parse('$faceApiUrl/add_suspect');
    final request = http.MultipartRequest('POST', uri);
    request.headers['accept'] = 'application/json';
    if (faceAuthHeader != null) request.headers.addAll(faceAuthHeader);

    request.fields['person_name'] = personName;
    request.files.add(await http.MultipartFile.fromPath('file', imagePath,
        filename: imagePath.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['detail'] ?? body['message'] ?? 'Add suspect failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network/upload error: $e'};
    }
  }

  // Method to delete a person from the suspect list (use form-urlencoded as docs show)
  Future<Map<String, dynamic>> deleteSuspectFromFace(String personName, {Map<String, String>? faceAuthHeader}) async {
    final uri = Uri.parse('$faceApiUrl/delete_suspect');
    try {
      final headers = <String, String>{'Content-Type': 'application/x-www-form-urlencoded', 'accept': 'application/json'};
      if (faceAuthHeader != null) headers.addAll(faceAuthHeader);

      print('ApiService.deleteSuspectFromFace -> POST $uri person_name=$personName');
      final resp = await http.post(uri, headers: headers, body: {'person_name': personName}).timeout(const Duration(seconds: 20));

      // parse body safely
      final body = _safeJson(resp.body);
      print('ApiService.deleteSuspectFromFace -> status ${resp.statusCode} bodyParsed=$body');

      // determine "deleted" deterministically
      bool deleted = false;
      try {
        if (body is Map) {
          final statusStr = (body['status'] ?? body['detail'] ?? body['result'] ?? '').toString().toLowerCase();
          if (statusStr.contains('deleted')) deleted = true;
          final dc = body['deleted_count'] ?? body['deleted'];
          if (dc is num && dc.toInt() > 0) deleted = true;
        } else if (body is String) {
          if (body.toLowerCase().contains('deleted')) deleted = true;
        } else if (body is Map && body.containsKey('raw')) {
          final raw = body['raw'].toString().toLowerCase();
          if (raw.contains('deleted')) deleted = true;
        }
      } catch (e) {
        // ignore parsing exceptions, keep deleted=false
        print('ApiService.deleteSuspectFromFace -> parsing error: $e');
      }

      if (resp.statusCode == 200) {
        // Return ok:true and explicit deleted flag + useful debug info
        return {
          'ok': true,
          'deleted': deleted,
          'status': resp.statusCode,
          'data': body,
          'raw': resp.body,
        };
      }

      // non-200
      return {
        'ok': false,
        'deleted': false,
        'message': body is Map ? (body['detail'] ?? body['message'] ?? 'Delete suspect failed (${resp.statusCode})') : 'Delete suspect failed (${resp.statusCode})',
        'status': resp.statusCode,
        'body': body,
        'raw': resp.body,
      };
    } catch (e) {
      print('ApiService.deleteSuspectFromFace -> exception: $e');
      return {'ok': false, 'deleted': false, 'message': 'Network error: $e'};
    }
  }
}
