// lib/pages/blacklist_management.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import 'error.dart';

/// Blacklist Management (wired to ApiService)
class BlacklistManagementPage extends StatefulWidget {
  final String role;

  const BlacklistManagementPage({super.key, required this.role});

  @override
  State<BlacklistManagementPage> createState() => _BlacklistManagementPageState();
}

class _BlacklistManagementPageState extends State<BlacklistManagementPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  final int _limit = 20;

  bool _loadingDL = false;
  bool _loadingRC = false;
  bool _loadingFace = false;
  String? _errorDL;
  String? _errorRC;
  String? _errorFace;

  List<Map<String, dynamic>> _dlList = [];
  List<Map<String, dynamic>> _rcList = [];
  Map<String, dynamic> _faceMap = {};
  int _dlTotal = 0;
  int _rcTotal = 0;
  int _faceTotal = 0;
  int _dlPage = 1;
  int _rcPage = 1;
  bool _isSearching = false;

  final TextEditingController _dlSearchCtrl = TextEditingController();
  final TextEditingController _rcSearchCtrl = TextEditingController();
  final TextEditingController _faceSearchCtrl = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _typeCtrl = TextEditingController(text: 'dl');
  final Map<String, TextEditingController> _formCtrls = {
    'number': TextEditingController(),
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'crime': TextEditingController(),
    'owner': TextEditingController(),
    'maker': TextEditingController(),
    'vehicle': TextEditingController(),
    'wheel': TextEditingController(),
  };

  final _faceAddFormKey = GlobalKey<FormState>();
  final TextEditingController _faceAddName = TextEditingController();
  XFile? _faceAddImage;

  late TabController _tabController;
  final ScrollController _dlScroll = ScrollController();
  final ScrollController _rcScroll = ScrollController();
  final ScrollController _faceScroll = ScrollController();

  Timer? _dlDebounce;
  Timer? _rcDebounce;
  Timer? _faceDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));

    _dlSearchCtrl.addListener(() {
      _dlDebounce?.cancel();
      _dlDebounce = Timer(const Duration(milliseconds: 400), () => _fetchDLs(page: 1));
    });
    _rcSearchCtrl.addListener(() {
      _rcDebounce?.cancel();
      _rcDebounce = Timer(const Duration(milliseconds: 400), () => _fetchRCs(page: 1));
    });
    _faceSearchCtrl.addListener(() {
      _faceDebounce?.cancel();
      _faceDebounce = Timer(const Duration(milliseconds: 400), () => _fetchFaces());
    });

    _fetchDLs();
    _fetchRCs();
    _fetchFaces();

    _dlScroll.addListener(() {
      if (_dlScroll.position.pixels > _dlScroll.position.maxScrollExtent - 200 &&
          (_dlPage * _limit) < _dlTotal &&
          !_loadingDL) {
        _fetchDLs(page: _dlPage + 1);
      }
    });

    _rcScroll.addListener(() {
      if (_rcScroll.position.pixels > _rcScroll.position.maxScrollExtent - 200 &&
          (_rcPage * _limit) < _rcTotal &&
          !_loadingRC) {
        _fetchRCs(page: _rcPage + 1);
      }
    });
  }

  @override
  void dispose() {
    _dlDebounce?.cancel();
    _rcDebounce?.cancel();
    _faceDebounce?.cancel();
    _dlSearchCtrl.dispose();
    _rcSearchCtrl.dispose();
    _faceSearchCtrl.dispose();
    _formCtrls.forEach((key, ctrl) => ctrl.dispose());
    _typeCtrl.dispose();
    _faceAddName.dispose();
    _tabController.dispose();
    _dlScroll.dispose();
    _rcScroll.dispose();
    _faceScroll.dispose();
    super.dispose();
  }

  /// -----------------------
  /// Fetching functions
  /// -----------------------
  Future<void> _fetchDLs({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _loadingDL = true;
      _errorDL = null;
    });

    final q = _dlSearchCtrl.text.trim();
    try {
      final resp = await _api.getBlacklistedDLs(page: page, limit: _limit, search: q);
      if (resp is Map && resp['ok'] == true) {
        final body = resp['data'];
        List<Map<String, dynamic>> dataList = [];
        int pageGot = page;
        int totalGot = 0;

        if (body is Map) {
          final rawList = body['data'] ?? body['items'] ?? body['results'] ?? body;
          if (rawList is List) {
            dataList = List<Map<String, dynamic>>.from(rawList.map((e) => Map<String, dynamic>.from(e as Map)));
          }
          pageGot = body['page'] ?? page;
          totalGot = body['total'] ?? dataList.length;
        } else if (body is List) {
          dataList = List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e as Map)));
          totalGot = dataList.length;
        }

        if (!mounted) return;
        setState(() {
          if (page == 1) _dlList = dataList;
          else _dlList.addAll(dataList);
          _dlTotal = totalGot;
          _dlPage = pageGot;
        });
      } else {
        if (!mounted) return;
        setState(() => _errorDL = (resp is Map) ? resp['message'] ?? 'Failed to load DL blacklist' : 'Failed to load DL blacklist');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorDL = 'Error loading DL blacklist: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingDL = false);
    }
  }

  Future<void> _fetchRCs({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _loadingRC = true;
      _errorRC = null;
    });

    final q = _rcSearchCtrl.text.trim();
    try {
      final resp = await _api.getBlacklistedRCs(page: page, limit: _limit, search: q);
      if (resp is Map && resp['ok'] == true) {
        final body = resp['data'];
        List<Map<String, dynamic>> dataList = [];
        int pageGot = page;
        int totalGot = 0;

        if (body is Map) {
          final rawList = body['data'] ?? body['items'] ?? body['results'] ?? body;
          if (rawList is List) {
            dataList = List<Map<String, dynamic>>.from(rawList.map((e) => Map<String, dynamic>.from(e as Map)));
          }
          pageGot = body['page'] ?? page;
          totalGot = body['total'] ?? dataList.length;
        } else if (body is List) {
          dataList = List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e as Map)));
          totalGot = dataList.length;
        }

        if (!mounted) return;
        setState(() {
          if (page == 1) _rcList = dataList;
          else _rcList.addAll(dataList);
          _rcTotal = totalGot;
          _rcPage = pageGot;
        });
      } else {
        if (!mounted) return;
        setState(() => _errorRC = (resp is Map) ? resp['message'] ?? 'Failed to load RC blacklist' : 'Failed to load RC blacklist');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorRC = 'Error loading RC blacklist: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingRC = false);
    }
  }

  Future<void> _fetchFaces() async {
    if (!mounted) return;
    setState(() {
      _loadingFace = true;
      _errorFace = null;
    });

    try {
      final resp = await _api.listSuspects();
      if (resp is Map && resp['ok'] == true) {
        final body = resp['data'];
        final Map<String, List<String>> faceMap = {};

        if (body is Map) {
          body.forEach((key, value) {
            if (value is List) {
              if (key == 'known_faces') {
                for (var url in value) {
                  if (url is String) {
                    final uri = Uri.parse(url);
                    final pathSegments = uri.pathSegments;
                    if (pathSegments.length >= 2) {
                      final personName = pathSegments[pathSegments.length - 2];
                      if (personName.isNotEmpty) {
                        if (!faceMap.containsKey(personName)) {
                          faceMap[personName] = [];
                        }
                        faceMap[personName]!.add(url);
                      }
                    }
                  }
                }
              } else {
                final personName = key;
                if (!faceMap.containsKey(personName)) {
                  faceMap[personName] = [];
                }
                faceMap[personName]!.addAll(List<String>.from(value));
              }
            }
          });
        }

        final q = _faceSearchCtrl.text.trim().toLowerCase();
        final Map<String, List<String>> filteredMap = q.isEmpty
            ? faceMap
            : {
          for (var entry in faceMap.entries)
            if (entry.key.toLowerCase().contains(q)) entry.key: entry.value
        };
        if (!mounted) return;
        setState(() {
          _faceMap = filteredMap;
          _faceTotal = _faceMap.length;
        });
      } else {
        if (!mounted) return;
        setState(() => _errorFace = (resp is Map) ? resp['message'] ?? 'Failed to load face suspects' : 'Failed to load face suspects');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorFace = 'Error loading face suspects: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingFace = false);
    }
  }

  /// -----------------------
  /// Add & Remove functions
  /// -----------------------
  Future<void> _addToBlacklist() async {
    if (!_formKey.currentState!.validate()) return;

    final type = _typeCtrl.text.trim();
    if (type == 'face') {
      _addFaceSuspect();
      return;
    }

    final payload = <String, dynamic>{
      'type': type,
      'number': _formCtrls['number']!.text.trim(),
      if (type == 'dl') ...{
        'name': _formCtrls['name']!.text.trim().isEmpty ? null : _formCtrls['name']!.text.trim(),
        'phone_number': _formCtrls['phone']!.text.trim().isEmpty ? null : _formCtrls['phone']!.text.trim(),
        'crime_involved': _formCtrls['crime']!.text.trim().isEmpty ? null : _formCtrls['crime']!.text.trim(),
      },
      if (type == 'rc') ...{
        'owner_name': _formCtrls['name']!.text.trim().isEmpty ? null : _formCtrls['name']!.text.trim(),
        'maker_class': _formCtrls['maker']!.text.trim().isEmpty ? null : _formCtrls['maker']!.text.trim(),
        'vehicle_class': _formCtrls['vehicle']!.text.trim().isEmpty ? null : _formCtrls['vehicle']!.text.trim(),
        'wheel_type': _formCtrls['wheel']!.text.trim().isEmpty ? null : _formCtrls['wheel']!.text.trim(),
        'crime_involved': _formCtrls['crime']!.text.trim().isEmpty ? null : _formCtrls['crime']!.text.trim(),
      },
    }..removeWhere((k, v) => v == null);

    if (!mounted) return;
    setState(() {
      if (type == 'dl') _loadingDL = true;
      else _loadingRC = true;
    });

    try {
      final resp = await _api.addToBlacklist(payload);
      if (!mounted) return;
      if (resp is Map && resp['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to blacklist successfully!'), backgroundColor: Colors.green));
        if (type == 'dl') await _fetchDLs(page: 1);
        else await _fetchRCs(page: 1);
        Navigator.of(context).pop();
      } else {
        final msg = (resp is Map) ? resp['message'] ?? 'Failed to add' : 'Failed to add';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingDL = false;
        _loadingRC = false;
      });
    }
  }

  /// -----------------------
  /// Response parsing helpers
  /// -----------------------

  // Recursively search maps/lists for any indicator of deletion:
  // - status contains 'deleted'
  // - any numeric 'deleted_count' or 'deleted' > 0
  bool _mapIndicatesDeleted(dynamic obj) {
    try {
      if (obj == null) return false;
      if (obj is Map) {
        for (final k in obj.keys) {
          final v = obj[k];
          if (v is String) {
            if (v.toLowerCase().contains('deleted')) return true;
          } else if (v is num) {
            if (k.toString().toLowerCase().contains('deleted') && v.toInt() > 0) return true;
            if (v.toInt() > 0 && k.toString().toLowerCase().contains('count')) return true;
          } else if (v is Map || v is List) {
            if (_mapIndicatesDeleted(v)) return true;
          }
        }
        // also check common keys directly
        final status = (obj['status'] ?? obj['result'] ?? '').toString().toLowerCase();
        if (status.contains('deleted')) return true;
        final dc = obj['deleted_count'] ?? obj['deleted'] ?? obj['deletedCount'];
        if (dc is num && dc.toInt() > 0) return true;
        if (obj['ok'] == true) return true;
        return false;
      } else if (obj is List) {
        for (final el in obj) {
          if (_mapIndicatesDeleted(el)) return true;
        }
        return false;
      } else if (obj is String) {
        return obj.toLowerCase().contains('deleted');
      } else {
        // other primitive
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Helper: Inspect a face-api list_suspects response body and return true if person exists
  bool _isPersonPresentInFaceListResponse(dynamic body, String personName) {
    try {
      if (body == null) return false;
      // If body is a map where keys are person names
      if (body is Map) {
        // Direct key
        if (body.containsKey(personName)) return true;
        // Known faces list: check gs:// or http urls for path containing personName
        for (final entryKey in body.keys) {
          final val = body[entryKey];
          if (val is List) {
            for (final item in val) {
              if (item is String) {
                // if url contains '/<personName>/' or path segment equals personName
                final lower = item.toLowerCase();
                if (lower.contains('/${personName.toLowerCase()}/') ||
                    lower.endsWith('/${personName.toLowerCase()}') ||
                    lower.contains(personName.toLowerCase())) {
                  // crude but effective check (we do more refined parsing below)
                  // try parse path segments if it's a valid URI
                  try {
                    final uri = Uri.parse(item);
                    if (uri.pathSegments.length >= 2) {
                      final candidate = uri.pathSegments[uri.pathSegments.length - 2];
                      if (candidate.toLowerCase() == personName.toLowerCase()) return true;
                    }
                  } catch (_) {
                    // ignore parse errors, fallback to substring check
                    return true;
                  }
                }
              }
            }
          } else if (entryKey.toString().toLowerCase() == personName.toLowerCase()) {
            return true;
          }
        }
      }
      // If body is a list (less likely) check each element
      if (body is List) {
        for (final el in body) {
          if (el is String && el.toLowerCase().contains(personName.toLowerCase())) return true;
          if (el is Map && _isPersonPresentInFaceListResponse(el, personName)) return true;
        }
      }
      // Fallback: string search
      final s = body.toString().toLowerCase();
      if (s.contains(personName.toLowerCase())) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Deterministic delete helper with timeout-handling + verification
  Future<bool> _deleteFaceSuspectApi(String personName) async {
    try {
      final dynamic raw = await _api.deleteSuspectFromFace(personName);
      debugPrint('deleteSuspectFromFace raw => $raw');

      if (raw == null) return false;

      // Preferred: ApiService returns Map with ok & deleted.
      if (raw is Map) {
        // If ApiService says ok:true
        if (raw['ok'] == true) {
          if (raw.containsKey('deleted')) {
            return raw['deleted'] == true;
          }
          // fallback: check nested data heuristics
          if (raw.containsKey('data') && _mapIndicatesDeleted(raw['data'])) return true;
          if (_mapIndicatesDeleted(raw)) return true;
          // server returned ok but no deleted indicator — assume success (server processed)
          return true;
        } else {
          // not ok -> could be timeout or network error (which sometimes still processed on server)
          final msg = (raw['message'] ?? '').toString().toLowerCase();

          // If it looks like a timeout/network failure, probe the face API to confirm whether person still exists.
          final bool isTimeoutLike = msg.contains('timeout') || msg.contains('timed out') || msg.contains('timeoutexception') || msg.contains('network error');
          if (isTimeoutLike) {
            // try verifying by polling listSuspects a few times (short backoff)
            for (int attempt = 0; attempt < 3; attempt++) {
              // small delay before verifying (first try immediate-ish)
              await Future.delayed(Duration(milliseconds: attempt == 0 ? 500 : 1000 * (attempt + 1)));
              try {
                final listResp = await _api.listSuspects();
                debugPrint('deleteSuspectFromFace -> verification attempt #$attempt listResp: $listResp');
                if (listResp is Map && listResp['ok'] == true) {
                  final body = listResp['data'];
                  final present = _isPersonPresentInFaceListResponse(body, personName);
                  if (!present) {
                    // person not present -> treat as success
                    return true;
                  }
                  // if present, continue attempts (maybe deletion completed a bit later)
                } else {
                  // if listResp not ok, keep trying
                }
              } catch (e) {
                debugPrint('Verification call failed: $e');
              }
            }
          }

          // fallback heuristics: maybe the response body indicates deletion
          if (raw.containsKey('data') && _mapIndicatesDeleted(raw['data'])) return true;
          if (_mapIndicatesDeleted(raw)) return true;
          // otherwise consider it failed
          return false;
        }
      }

      // If it's an http.Response (older code path) - inspect
      if (raw is http.Response) {
        try {
          final bodyDecoded = jsonDecode(raw.body);
          if (_mapIndicatesDeleted(bodyDecoded)) return true;
        } catch (_) {
          if (raw.body.toLowerCase().contains('deleted')) return true;
        }
        // If HTTP 200 but no 'deleted' text, still attempt verification (server may have processed)
        if (raw.statusCode == 200) {
          // verification probe
          final listResp = await _api.listSuspects();
          if (listResp is Map && listResp['ok'] == true) {
            final body = listResp['data'];
            final present = _isPersonPresentInFaceListResponse(body, personName);
            if (!present) return true;
          }
        }
        return false;
      }

      // If string: try to parse
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (_mapIndicatesDeleted(decoded)) return true;
        } catch (_) {
          if (raw.toLowerCase().contains('deleted')) return true;
        }
        // fallback: verify list
        final listResp = await _api.listSuspects();
        if (listResp is Map && listResp['ok'] == true) {
          final body = listResp['data'];
          final present = _isPersonPresentInFaceListResponse(body, personName);
          if (!present) return true;
        }
        return false;
      }

      // Other types: stringify and check
      final s = raw.toString();
      if (s.toLowerCase().contains('deleted')) return true;

      // As final fallback, probe list endpoint
      final listResp = await _api.listSuspects();
      if (listResp is Map && listResp['ok'] == true) {
        final body = listResp['data'];
        final present = _isPersonPresentInFaceListResponse(body, personName);
        if (!present) return true;
      }

      return false;
    } catch (e) {
      debugPrint('Exception in _deleteFaceSuspectApi: $e');
      // As last-resort, probe list endpoint to see if person disappeared despite exception
      try {
        final listResp = await _api.listSuspects();
        if (listResp is Map && listResp['ok'] == true) {
          final body = listResp['data'];
          final present = _isPersonPresentInFaceListResponse(body, personName);
          if (!present) return true;
        }
      } catch (_) {}
      return false;
    }
  }

  Future<void> _addFaceSuspect() async {
    if (!_faceAddFormKey.currentState!.validate()) return;
    if (_faceAddImage == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an image'), backgroundColor: Colors.red));
      return;
    }

    // Close the bottomsheet/modal that invoked this (if present)
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // show a blocking loading dialog (use rootNavigator to ensure we pop the right one)
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final resp = await _api.addSuspectFromFace(
        personName: _faceAddName.text.trim(),
        imagePath: _faceAddImage!.path,
      );

      // Dismiss loader (always attempt to pop the root navigator if possible)
      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      if (!mounted) return;
      if (resp is Map && resp['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suspect added successfully!'), backgroundColor: Colors.green));
        await _fetchFaces();
      } else {
        final msg = (resp is Map) ? resp['message'] ?? 'Failed to add face suspect' : 'Failed to add face suspect';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) {
      // Ensure loader removed
      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<bool> _markValid(String type, String id) async {
    try {
      final resp = await _api.markBlacklistValid(type: type, id: id);
      if (resp is Map && resp['ok'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry marked valid (removed)'), backgroundColor: Colors.green));
        if (type == 'dl') {
          await _fetchDLs(page: 1);
        } else {
          await _fetchRCs(page: 1);
        }
        return true;
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((resp is Map) ? resp['message'] ?? 'Failed to mark valid' : 'Failed to mark valid'), backgroundColor: Colors.red));
        return false;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: $e'), backgroundColor: Colors.red));
      return false;
    }
  }

  /// -----------------------
  /// UI pieces
  /// -----------------------
  Widget _buildListContent(List<Map<String, dynamic>> list, String type, String? error, bool loading, ScrollController scrollController) {
    if (loading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && list.isEmpty) {
      return Center(child: Text(error, style: const TextStyle(color: Colors.red)));
    }

    if (list.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(type == 'dl' ? Icons.no_accounts : Icons.directions_car, size: 60, color: Colors.black38),
            const SizedBox(height: 16),
            Text('No blacklisted ${type.toUpperCase()}s found.', style: const TextStyle(fontSize: 18, color: Colors.black54)),
          ]));
    }

    final isSuperAdmin = widget.role == 'superadmin';
    final dismissDirection = isSuperAdmin ? DismissDirection.endToStart : DismissDirection.none;

    return RefreshIndicator(
      onRefresh: () => type == 'dl' ? _fetchDLs(page: 1) : _fetchRCs(page: 1),
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: list.length + (loading && list.isNotEmpty ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == list.length) {
            return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
          }

          final entry = list[i];
          final id = (entry['_id'] is Map)
              ? (entry['_id']['\$oid'] ?? entry['_id'].toString())
              : entry['_id']?.toString() ?? '';
          final title = type == 'dl'
              ? (entry['dl_number'] ?? entry['dl'] ?? 'Unknown DL')
              : (entry['regn_number'] ?? entry['rc_number'] ?? entry['regnNo'] ?? 'Unknown RC');
          final subtitle = _buildSubtitle(entry, type);
          final status = (entry['verification'] ?? entry['Verification'] ?? entry['status'] ?? '').toString();

          return Dismissible(
            key: ValueKey(id),
            direction: dismissDirection,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            confirmDismiss: (direction) async {
              final confirmed = await _showConfirmDialog('Mark this ${type.toUpperCase()} as valid (remove from blacklist)?');
              if (confirmed != true) return false;

              // show blocking loading while API call happens
              showDialog(
                context: context,
                barrierDismissible: false,
                useRootNavigator: true,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              bool ok = false;
              try {
                ok = await _markValid(type, id.toString());
              } catch (e) {
                ok = false;
              } finally {
                // always attempt to close the loading dialog in root navigator
                try {
                  if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
                } catch (_) {}
              }

              return ok;
            },
            onDismissed: (direction) {
              // remove the entry from the local list immediately to keep tree consistent
              if (mounted) {
                setState(() {
                  list.removeWhere((e) {
                    final eid = (e['_id'] is Map) ? (e['_id']['\$oid'] ?? e['_id'].toString()) : e['_id']?.toString() ?? '';
                    return eid == id;
                  });
                  if (type == 'dl') {
                    _dlTotal = _dlList.length;
                  } else {
                    _rcTotal = _rcList.length;
                  }
                });
              }
            },
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: CircleAvatar(
                    backgroundColor: type == 'dl' ? Colors.blue.shade50 : Colors.teal.shade50,
                    child: Icon(type == 'dl' ? Icons.badge : Icons.directions_car, color: type == 'dl' ? Colors.blue : Colors.teal)),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: subtitle,
                trailing: Chip(
                  label: Text(status.isNotEmpty ? status : '-', style: TextStyle(color: status.toLowerCase().contains('black') ? Colors.red.shade700 : Colors.green.shade700)),
                  backgroundColor: status.toLowerCase().contains('black') ? Colors.red.shade50 : Colors.green.shade50,
                ),
                onTap: () => _showEntryDetails(context, entry, type: type),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFaceListContent(String? error, bool loading, ScrollController scrollController) {
    if (loading && _faceMap.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && _faceMap.isEmpty) {
      return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(error, style: const TextStyle(color: Colors.red, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchFaces,
                child: const Text('Retry'),
              ),
            ],
          ));
    }

    if (_faceMap.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.face_retouching_off, size: 60, color: Colors.black38),
            const SizedBox(height: 16),
            const Text('No face suspects found.', style: TextStyle(fontSize: 18, color: Colors.black54)),
          ]));
    }

    final isSuperAdmin = widget.role == 'superadmin';
    final dismissDirection = isSuperAdmin ? DismissDirection.endToStart : DismissDirection.none;
    final filteredKeys = _faceMap.keys.toList();

    return RefreshIndicator(
      onRefresh: _fetchFaces,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filteredKeys.length,
        itemBuilder: (ctx, i) {
          final personName = filteredKeys[i];
          final List<dynamic> images = _faceMap[personName]!;

          final imageUrl = _convertGsUrlToHttp(images.isNotEmpty ? images.first : null);

          return Dismissible(
            key: ValueKey(personName),
            direction: dismissDirection,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            confirmDismiss: (direction) async {
              final confirmed = await _showConfirmDialog('Are you sure you want to delete $personName from the suspect list?');
              if (confirmed != true) return false;

              // show spinner
              showDialog(
                context: context,
                barrierDismissible: false,
                useRootNavigator: true,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              bool success = false;
              try {
                success = await _deleteFaceSuspectApi(personName);
                if (success) {
                  // refresh so UI shows current server state
                  await _fetchFaces();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suspect deleted successfully!'), backgroundColor: Colors.green));
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete suspect'), backgroundColor: Colors.red));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
                success = false;
              } finally {
                // always attempt to close spinner (root navigator)
                try {
                  if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
                } catch (_) {}
              }

              return success;
            },
            onDismissed: (direction) {
              if (mounted) {
                setState(() {
                  _faceMap.remove(personName);
                  _faceTotal = _faceMap.length;
                });
              }
            },
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageUrl != null
                      ? Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, o, s) => const Icon(Icons.person, size: 50))
                      : const Icon(Icons.person, size: 50),
                ),
                title: Text(personName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${images.length} photo${images.length == 1 ? '' : 's'}'),
                onTap: () => _showSuspectDetails(context, personName, images),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _convertGsUrlToHttp(String? gsUrl) {
    if (gsUrl == null || !gsUrl.startsWith('gs://')) {
      return null;
    }
    final parts = gsUrl.substring(5).split('/');
    if (parts.length < 2) {
      return null;
    }
    final bucket = parts.first;
    final path = parts.sublist(1).join('/');
    return 'https://storage.googleapis.com/$bucket/$path';
  }

  Widget _buildSubtitle(Map<String, dynamic> entry, String type) {
    List<Widget> children = [];
    final reason = (entry['crime_involved'] ?? entry['reason'] ?? '').toString();

    if (type == 'dl') {
      final name = (entry['name'] ?? '').toString();
      final phone = (entry['phone_number'] ?? '').toString();
      if (name.isNotEmpty) children.add(Text(name));
      if (phone.isNotEmpty) children.add(Text('📞 $phone'));
    } else {
      final owner = (entry['owner_name'] ?? '').toString();
      final maker = (entry['maker_class'] ?? '').toString();
      final vclass = (entry['vehicle_class'] ?? '').toString();
      if (owner.isNotEmpty) children.add(Text('Owner: $owner'));
      if (maker.isNotEmpty) children.add(Text('Maker: $maker'));
      if (vclass.isNotEmpty) children.add(Text('Class: $vclass'));
    }
    if (reason.isNotEmpty) {
      children.add(Padding(padding: const EdgeInsets.only(top: 6), child: Text('Reason: $reason', style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Future<bool?> _showConfirmDialog(String text) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Action'),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
  }

  void _showAddBottomSheet() {
    _formCtrls.forEach((key, ctrl) => ctrl.clear());
    _faceAddName.clear();
    _faceAddImage = null;

    if (_tabController.index == 0) _typeCtrl.text = 'dl';
    else if (_tabController.index == 1) _typeCtrl.text = 'rc';
    else _typeCtrl.text = 'face';

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          final mediaQuery = MediaQuery.of(context);
          final isPortrait = mediaQuery.orientation == Orientation.portrait;
          return Padding(
            padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom, top: 20, left: isPortrait ? 20 : 40, right: isPortrait ? 20 : 40),
            child: SingleChildScrollView(
              child: Form(
                key: _typeCtrl.text == 'face' ? _faceAddFormKey : _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Add New Blacklist Entry', style: Theme.of(context).textTheme.titleLarge),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ]),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Entry Type', border: OutlineInputBorder()),
                    value: _typeCtrl.text,
                    items: const [
                      DropdownMenuItem(value: 'dl', child: Text('Driving License (DL)')),
                      DropdownMenuItem(value: 'rc', child: Text('Registration Certificate (RC)')),
                      DropdownMenuItem(value: 'face', child: Text('Face Suspect')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _typeCtrl.text = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_typeCtrl.text == 'face') ...[
                    TextFormField(
                      controller: _faceAddName,
                      decoration: const InputDecoration(labelText: 'Suspect Name', border: OutlineInputBorder()),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final ImagePicker picker = ImagePicker();
                                  final picked = await picker.pickImage(source: ImageSource.camera);
                                  if (picked != null) {
                                    setState(() => _faceAddImage = picked);
                                  }
                                },
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Take Photo'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final ImagePicker picker = ImagePicker();
                                  final picked = await picker.pickImage(source: ImageSource.gallery);
                                  if (picked != null) {
                                    setState(() => _faceAddImage = picked);
                                  }
                                },
                                icon: const Icon(Icons.photo_library),
                                label: const Text('From Gallery'),
                              ),
                            ),
                          ],
                        ),
                        if (_faceAddImage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text('Selected: ${_faceAddImage!.name}'),
                          ),
                      ],
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _formCtrls['number'],
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null,
                      decoration: InputDecoration(labelText: _typeCtrl.text == 'dl' ? 'DL Number' : 'RC Number', border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(controller: _formCtrls['crime'], decoration: const InputDecoration(labelText: 'Reason for Blacklisting (optional)', border: const OutlineInputBorder())),
                    const SizedBox(height: 16),
                    TextFormField(controller: _formCtrls['name'], decoration: InputDecoration(labelText: _typeCtrl.text == 'dl' ? 'Name (optional)' : 'Owner Name (optional)', border: const OutlineInputBorder())),
                    const SizedBox(height: 16),
                    if (_typeCtrl.text == 'dl') ...[
                      TextFormField(controller: _formCtrls['phone'], decoration: const InputDecoration(labelText: 'Phone Number (optional)', border: const OutlineInputBorder())),
                      const SizedBox(height: 16),
                    ],
                    if (_typeCtrl.text == 'rc') ...[
                      TextFormField(controller: _formCtrls['maker'], decoration: const InputDecoration(labelText: 'Maker Class (optional)', border: const OutlineInputBorder())),
                      const SizedBox(height: 16),
                      TextFormField(controller: _formCtrls['vehicle'], decoration: const InputDecoration(labelText: 'Vehicle Class (optional)', border: const OutlineInputBorder())),
                      const SizedBox(height: 16),
                      TextFormField(controller: _formCtrls['wheel'], decoration: const InputDecoration(labelText: 'Wheel Type (optional)', border: const OutlineInputBorder())),
                      const SizedBox(height: 16),
                    ],
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_typeCtrl.text == 'face') {
                          _addFaceSuspect();
                        } else {
                          _addToBlacklist();
                        }
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Add to Blacklist'),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEntryDetails(BuildContext parentContext, Map<String, dynamic> item, {required String type}) {
    String? _getImageUrl(Map<String, dynamic> it) {
      final keys = ['photo', 'image', 'photoUrl', 'image_url', 'photo_url'];
      for (final k in keys) {
        final v = it[k];
        if (v != null && v is String && v.trim().isNotEmpty) return v;
      }
      if (it['images'] is List && (it['images'] as List).isNotEmpty) {
        final first = (it['images'] as List).first;
        if (first is String && first.isNotEmpty) return first;
        if (first is Map && first['url'] is String) return first['url'];
      }
      return null;
    }

    Widget row(String label, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ]),
      );
    }

    final imageUrl = _getImageUrl(item);
    showDialog(
      context: parentContext,
      builder: (ctx) {
        bool _isRemoving = false;
        return StatefulBuilder(builder: (ctx2, setState2) {
          final List<Widget> content = [];
          final idVal = (item['_id'] is Map)
              ? (item['_id']['\$oid'] ?? item['_id'].toString())
              : item['_id']?.toString() ?? '';
          if (idVal.isNotEmpty) content.add(row('ID', idVal));

          if (type == 'dl') {
            content.add(row('DL Number', (item['dl_number'] ?? item['dl'] ?? '').toString()));
            content.add(row('Name', (item['name'] ?? '').toString()));
            content.add(row('DOB', (item['dob'] ?? '').toString()));
            content.add(row('Blood Group', (item['blood_group'] ?? '').toString()));
            content.add(row('Organ Donor', (item['organ_donor'] ?? '').toString()));
            content.add(row('Issue Date', (item['issue_date'] ?? '').toString()));
            content.add(row('Valid Upto', (item['validity'] ?? item['valid_upto'] ?? '').toString()));
            content.add(row('Father', (item['father_name'] ?? '').toString()));
            content.add(row('Phone', (item['phone_number'] ?? '').toString()));
            content.add(row('Address', (item['address'] ?? '').toString()));
            content.add(row('Crime', (item['crime_involved'] ?? item['reason'] ?? '').toString()));
            content.add(row('Verification', (item['verification'] ?? item['Verification'] ?? '').toString()));
          } else {
            content.add(row('RC / Regn', (item['regn_number'] ?? item['rc_number'] ?? item['regnNo'] ?? '').toString()));
            content.add(row('Owner', (item['owner_name'] ?? item['owner'] ?? '').toString()));
            content.add(row('Father', (item['father_name'] ?? '').toString()));
            content.add(row('Address', (item['address'] ?? '').toString()));
            content.add(row('Maker', (item['maker_class'] ?? '').toString()));
            content.add(row('Vehicle Class', (item['vehicle_class'] ?? '').toString()));
            content.add(row('Wheel Type', (item['wheel_type'] ?? item['wheel'] ?? '').toString()));
            content.add(row('Fuel', (item['fuel_used'] ?? '').toString()));
            content.add(row('Body Type', (item['type_of_body'] ?? '').toString()));
            content.add(row('Mfg', (item['mfg_month_year'] ?? '').toString()));
            content.add(row('Chassis', (item['chassis_number'] ?? '').toString()));
            content.add(row('Engine', (item['engine_number'] ?? '').toString()));
            content.add(row('Regn Date', (item['registration_date'] ?? '').toString()));
            content.add(row('Valid Upto', (item['valid_upto'] ?? '').toString()));
            content.add(row('Tax Paid', (item['tax_paid'] ?? '').toString()));
            content.add(row('Crime', (item['crime_involved'] ?? item['reason'] ?? '').toString()));
            content.add(row('Verification', (item['verification'] ?? item['Verification'] ?? '').toString()));
          }

          final filtered = content.where((w) => w is! SizedBox).toList();

          return AlertDialog(
            title: Text('${type.toUpperCase()} Details'),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.8,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.of(ctx2).push(MaterialPageRoute(builder: (_) {
                            return Scaffold(
                              appBar: AppBar(title: const Text('Photo')),
                              body: Center(child: InteractiveViewer(child: Image.network(imageUrl))),
                            );
                          }));
                        },
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(imageUrl, height: MediaQuery.of(ctx).size.height * 0.2, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 64)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...filtered,
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isRemoving ? null : () => Navigator.of(ctx2).pop(),
                child: const Text('Close'),
              ),
              if (widget.role == 'superadmin')
                OutlinedButton.icon(
                  icon: _isRemoving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                      : const Icon(Icons.check, color: Colors.red),
                  label: const Text('Remove from blacklist', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _isRemoving
                      ? null
                      : () async {
                    final confirm = await showDialog<bool>(
                      context: ctx2,
                      builder: (c) => AlertDialog(
                        title: const Text('Confirm Remove'),
                        content: Text('Mark this ${type.toUpperCase()} as valid (remove from blacklist)?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red, width: 1.5), foregroundColor: Colors.red),
                            onPressed: () => Navigator.of(c).pop(true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    setState(() => _isRemoving = true);

                    // show spinner while marking valid
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      useRootNavigator: true,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    final ok = await _markValid(type, idVal);

                    // always try to pop spinner
                    try {
                      if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
                    } catch (_) {}

                    setState(() => _isRemoving = false);
                    if (ok) {
                      Navigator.of(ctx2).pop();
                    }
                  },
                ),
            ],
          );
        });
      },
    );
  }

  void _showSuspectDetails(BuildContext parentContext, String name, List<dynamic> imageUrls) {
    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setState2) {
          return AlertDialog(
            title: Text('Suspect: $name'),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.8,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: imageUrls.isNotEmpty
                            ? Image.network(
                          _convertGsUrlToHttp(imageUrls.first)!,
                          height: MediaQuery.of(ctx).size.height * 0.25,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 100),
                        )
                            : const Icon(Icons.person, size: 100),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Name: $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    const Text('Photos in database:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...imageUrls.map((url) => Text('- ${url.split('/').last}')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: const Text('Close')),
              if (widget.role == 'superadmin')
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('Remove suspect', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final confirmed = await _showConfirmDialog('Are you sure you want to delete $name from the suspect list?');
                    if (confirmed != true) return;

                    // show loading while deleting
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      useRootNavigator: true,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    bool success = false;
                    try {
                      success = await _deleteFaceSuspectApi(name);

                      // always attempt to close loader
                      try {
                        if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
                      } catch (_) {}

                      if (success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suspect deleted successfully!'), backgroundColor: Colors.green));
                        if (mounted) {
                          setState(() {
                            _faceMap.remove(name);
                            _faceTotal = _faceMap.length;
                          });
                        }
                        Navigator.of(ctx2).pop(); // close details dialog
                      } else {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete suspect'), backgroundColor: Colors.red));
                      }
                    } catch (e) {
                      // ensure loader closed
                      try {
                        if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
                      } catch (_) {}
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
                    }
                  },
                ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController activeSearchController = _tabController.index == 0
        ? _dlSearchCtrl
        : _tabController.index == 1
        ? _rcSearchCtrl
        : _faceSearchCtrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blacklist Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = true;
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSearching ? 110.0 : 48.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TextField(
                    controller: activeSearchController,
                    decoration: InputDecoration(
                      hintText: _tabController.index == 0 ? 'Search DL number...' : _tabController.index == 1 ? 'Search RC number...' : 'Search suspect name...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _isSearching = false;
                            _dlSearchCtrl.clear();
                            _rcSearchCtrl.clear();
                            _faceSearchCtrl.clear();
                            _fetchDLs(page: 1);
                            _fetchRCs(page: 1);
                            _fetchFaces();
                          });
                        },
                        tooltip: 'Close search',
                      ),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(vertical: 0.0, horizontal: 16.0),
                    ),
                    onSubmitted: (_) {
                      if (_tabController.index == 0) _fetchDLs(page: 1);
                      else if (_tabController.index == 1) _fetchRCs(page: 1);
                      else _fetchFaces();
                    },
                  ),
                ),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'DL ($_dlTotal)'),
                  Tab(text: 'RC ($_rcTotal)'),
                  Tab(text: 'Face ($_faceTotal)'),
                ],
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                indicatorWeight: 3.0,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.role == 'superadmin'
          ? FloatingActionButton(
        onPressed: _showAddBottomSheet,
        child: const Icon(Icons.add),
      )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildListContent(_dlList, 'dl', _errorDL, _loadingDL, _dlScroll),
          _buildListContent(_rcList, 'rc', _errorRC, _loadingRC, _rcScroll),
          _buildFaceListContent(_errorFace, _loadingFace, _faceScroll),
        ],
      ),
    );
  }
}
