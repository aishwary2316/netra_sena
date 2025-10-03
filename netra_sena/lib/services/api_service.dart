// lib/services/api_service.dart
// Clean, minimal, face-only API service (fixed syntax issues)
// Designed to compile in Dart/Flutter.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform, SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException(statusCode: \${statusCode ?? "null"}, message: \${message})';
}

class ApiService {
  // Configuration
  static const String backendBaseUrl = 'https://netrasena.onrender.com';
  static const String faceApiBaseUrl = 'https://face-surveillance-api-777302308889.asia-south1.run.app';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final int timeoutSeconds;
  final bool debug;

  ApiService({this.timeoutSeconds = 60, this.debug = false});

  Duration get _timeout => Duration(seconds: timeoutSeconds);

  // Session storage keys
  static const String _kSessionId = 'session_id';
  static const String _kUserId = 'user_id';
  static const String _kUsername = 'username';
  static const String _kUserRole = 'user_role';

  Future<void> saveSession({required String sessionId, required String userId, required String username, required String role}) async {
    await _storage.write(key: _kSessionId, value: sessionId);
    await _storage.write(key: _kUserId, value: userId);
    await _storage.write(key: _kUsername, value: username);
    await _storage.write(key: _kUserRole, value: role);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _kSessionId);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kUserRole);
  }

  Future<String?> getSessionId() async => await _storage.read(key: _kSessionId);
  Future<String?> getUsername() async => await _storage.read(key: _kUsername);

  Map<String, String> _jsonHeaders() => {'Accept': 'application/json', 'Content-Type': 'application/json'};

  Future<Map<String, String>> _authHeaders() async {
    final session = await getSessionId();
    final username = await getUsername();
    final headers = <String, String>{'Accept': 'application/json'};
    if (session != null) headers['Authorization'] = 'Bearer \$session';
    if (username != null) headers['username'] = username;
    return headers;
  }

  void _log(String message) {
    if (debug) print('ApiService: \$message');
  }

  // Network helpers
  Future<http.Response> _postJson(Uri uri, Object body) async {
    _log('POST JSON -> \$uri');
    try {
      final resp = await http.post(uri, headers: _jsonHeaders(), body: jsonEncode(body)).timeout(_timeout);
      _log('RESPONSE <- \$uri (status=\${resp.statusCode})');
      return resp;
    } on TimeoutException catch (_) {
      throw ApiException('Request timed out after \${_timeout.inSeconds}s when calling \$uri');
    } on SocketException catch (e) {
      throw ApiException('Network error when calling \$uri: \$e');
    }
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) async {
    _log('GET -> \$uri');
    try {
      final resp = await http.get(uri, headers: headers).timeout(_timeout);
      _log('RESPONSE <- \$uri (status=\${resp.statusCode})');
      return resp;
    } on TimeoutException catch (_) {
      throw ApiException('Request timed out after \${_timeout.inSeconds}s when calling \$uri');
    } on SocketException catch (e) {
      throw ApiException('Network error when calling \$uri: \$e');
    }
  }

  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers}) async {
    _log('DELETE -> \$uri');
    try {
      final resp = await http.delete(uri, headers: headers).timeout(_timeout);
      _log('RESPONSE <- \$uri (status=\${resp.statusCode})');
      return resp;
    } on TimeoutException catch (_) {
      throw ApiException('Request timed out after \${_timeout.inSeconds}s when calling \$uri');
    } on SocketException catch (e) {
      throw ApiException('Network error when calling \$uri: \$e');
    }
  }

  Future<http.Response> _postForm(Uri uri, Map<String, String> form, {Map<String, String>? headers}) async {
    _log('POST FORM -> \$uri formKeys=\${form.keys.toList()}');
    try {
      final resp = await http.post(uri, headers: headers, body: form).timeout(_timeout);
      _log('RESPONSE <- \$uri (status=\${resp.statusCode})');
      return resp;
    } on TimeoutException catch (_) {
      throw ApiException('Request timed out after \${_timeout.inSeconds}s when calling \$uri');
    } on SocketException catch (e) {
      throw ApiException('Network error when calling \$uri: \$e');
    }
  }

  Future<http.Response> _sendMultipart(http.MultipartRequest request) async {
    _log('MULTIPART -> \${request.method} \${request.url} fields=\${request.fields.keys.toList()} files=\${request.files.map((f) => f.filename).toList()}');
    try {
      final streamed = await request.send().timeout(_timeout);
      final resp = await http.Response.fromStream(streamed);
      _log('RESPONSE <- \${request.url} (status=\${resp.statusCode})');
      return resp;
    } on TimeoutException catch (_) {
      throw ApiException('Upload timed out after \${_timeout.inSeconds}s when calling \${request.url}');
    } on SocketException catch (e) {
      throw ApiException('Network error during upload to \${request.url}: \$e');
    }
  }

  // -----------------------------
  // AUTH
  // -----------------------------
  Future<Map<String, dynamic>> login({required String username, required String password}) async {
    final uri = Uri.parse(backendBaseUrl + '/api/login');
    final body = {'username': username, 'password': password};
    final resp = await _postJson(uri, body);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] == true && data['user'] != null) {
        final user = data['user'] as Map<String, dynamic>;
        final sessionId = user['sessionId'] ?? user['session_id'];
        final userId = (user['id'] ?? user['_id'])?.toString();
        final uname = user['username']?.toString() ?? username;
        final role = user['role']?.toString() ?? 'operator';
        if (sessionId != null && userId != null) {
          await saveSession(sessionId: sessionId, userId: userId, username: uname, role: role);
        }
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ApiException('Login failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<void> logout() async {
    final userId = await _storage.read(key: _kUserId);
    if (userId != null) {
      try {
        final uri = Uri.parse(backendBaseUrl + '/api/logout/' + userId);
        await _postJson(uri, {});
      } catch (_) {
        // ignore
      }
    }
    await clearSession();
  }

  // -----------------------------
  // Backend endpoints
  // -----------------------------
  Future<Map<String, dynamic>> scanFace({File? imageFile, Uint8List? bytes, String? filename, Map<String, String>? extraFields}) async {
    if (imageFile == null && bytes == null) throw ArgumentError('Provide imageFile or bytes');
    final uri = Uri.parse(backendBaseUrl + '/api/face-scan');
    final request = http.MultipartRequest('POST', uri);
    final session = await getSessionId();
    final username = await getUsername();
    if (session != null) request.headers['Authorization'] = 'Bearer ' + session;
    if (username != null) request.headers['username'] = username;
    if (extraFields != null) request.fields.addAll(extraFields);

    if (bytes != null) {
      final name = filename ?? 'face.jpg';
      request.files.add(http.MultipartFile.fromBytes('faceImage', bytes, filename: name, contentType: MediaType('image', 'jpeg')));
    } else {
      final multipartFile = await http.MultipartFile.fromPath('faceImage', imageFile!.path, filename: filename ?? imageFile.path.split(Platform.pathSeparator).last);
      request.files.add(multipartFile);
    }

    final resp = await _sendMultipart(request);
    if (resp.statusCode == 200 || resp.statusCode == 201) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('scanFace failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> addSuspect({required String suspectName, String? description, File? imageFile, Uint8List? bytes, String? filename}) async {
    if (imageFile == null && bytes == null) throw ArgumentError('Provide suspect photo as imageFile or bytes');
    final uri = Uri.parse(backendBaseUrl + '/api/suspects');
    final request = http.MultipartRequest('POST', uri);
    final session = await getSessionId();
    final username = await getUsername();
    if (session != null) request.headers['Authorization'] = 'Bearer ' + session;
    if (username != null) request.headers['username'] = username;

    request.fields['suspectName'] = suspectName;
    request.fields['description'] = description ?? '';

    if (bytes != null) {
      final name = filename ?? 'suspect.jpg';
      request.files.add(http.MultipartFile.fromBytes('suspectPhoto', bytes, filename: name, contentType: MediaType('image', 'jpeg')));
    } else {
      final multipartFile = await http.MultipartFile.fromPath('suspectPhoto', imageFile!.path, filename: filename ?? imageFile.path.split(Platform.pathSeparator).last);
      request.files.add(multipartFile);
    }

    final resp = await _sendMultipart(request);
    if (resp.statusCode == 200 || resp.statusCode == 201) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('addSuspect failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> getSuspects() async {
    final uri = Uri.parse(backendBaseUrl + '/api/suspects');
    final resp = await _get(uri, headers: await _authHeaders());
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('getSuspects failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> deleteSuspectByName(String name) async {
    final uri = Uri.parse(backendBaseUrl + '/api/suspects/' + Uri.encodeComponent(name));
    final resp = await _delete(uri, headers: await _authHeaders());
    if (resp.statusCode == 200 || resp.statusCode == 204) return resp.body.isEmpty ? {'success': true} : jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('deleteSuspectByName failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<List<dynamic>> getFaceAlerts() async {
    final uri = Uri.parse(backendBaseUrl + '/api/face-alerts');
    final resp = await _get(uri, headers: await _authHeaders());
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['alerts'] != null && data['alerts'] is List) return data['alerts'] as List<dynamic>;
      return data.values.toList();
    }
    throw ApiException('getFaceAlerts failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> getUsers() async {
    final uri = Uri.parse(backendBaseUrl + '/api/users');
    final resp = await _get(uri, headers: await _authHeaders());
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('getUsers failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> createUser({required String username, required String password, required String role}) async {
    final uri = Uri.parse(backendBaseUrl + '/api/users');
    final resp = await _postJson(uri, {'username': username, 'password': password, 'role': role});
    if (resp.statusCode == 200 || resp.statusCode == 201) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('createUser failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> deleteUserById(String id) async {
    final uri = Uri.parse(backendBaseUrl + '/api/users/' + Uri.encodeComponent(id));
    final resp = await _delete(uri, headers: await _authHeaders());
    if (resp.statusCode == 200 || resp.statusCode == 204) return resp.body.isEmpty ? {'success': true} : jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('deleteUserById failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> getStatus() async {
    final uri = Uri.parse(backendBaseUrl + '/api/status');
    final resp = await _get(uri);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('getStatus failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  // Direct Face API
  Future<Map<String, dynamic>> listSuspectsFaceApi() async {
    final uri = Uri.parse(faceApiBaseUrl + '/list_suspects');
    final resp = await _get(uri, headers: {'accept': 'application/json'});
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('listSuspectsFaceApi failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> recognizeFaceDirect({File? imageFile, Uint8List? bytes, String? filename}) async {
    if (imageFile == null && bytes == null) throw ArgumentError('Provide imageFile or bytes');
    final uri = Uri.parse(faceApiBaseUrl + '/recognize');
    final request = http.MultipartRequest('POST', uri);
    request.headers['accept'] = 'application/json';
    if (bytes != null) {
      final name = filename ?? 'file.jpg';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name, contentType: MediaType('image', 'jpeg')));
    } else {
      final multipartFile = await http.MultipartFile.fromPath('file', imageFile!.path, filename: filename ?? imageFile.path.split(Platform.pathSeparator).last);
      request.files.add(multipartFile);
    }
    final resp = await _sendMultipart(request);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('recognizeFaceDirect failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> addSuspectToFaceApi({required String personName, File? imageFile, Uint8List? bytes, String? filename}) async {
    if (imageFile == null && bytes == null) throw ArgumentError('Provide imageFile or bytes');
    final uri = Uri.parse(faceApiBaseUrl + '/add_suspect');
    final request = http.MultipartRequest('POST', uri);
    request.headers['accept'] = 'application/json';
    request.fields['person_name'] = personName;
    if (bytes != null) {
      final name = filename ?? 'file.jpg';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name, contentType: MediaType('image', 'jpeg')));
    } else {
      final multipartFile = await http.MultipartFile.fromPath('file', imageFile!.path, filename: filename ?? imageFile.path.split(Platform.pathSeparator).last);
      request.files.add(multipartFile);
    }
    final resp = await _sendMultipart(request);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('addSuspectToFaceApi failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  Future<Map<String, dynamic>> deleteSuspectFromFaceApi(String personName) async {
    final uri = Uri.parse(faceApiBaseUrl + '/delete_suspect');
    final headers = {'Content-Type': 'application/x-www-form-urlencoded', 'accept': 'application/json'};
    final resp = await _postForm(uri, {'person_name': personName}, headers: headers);
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException('deleteSuspectFromFaceApi failed: \${resp.statusCode} - \${resp.body}', resp.statusCode);
  }

  String _shortError(Object e) => e.toString();
}
