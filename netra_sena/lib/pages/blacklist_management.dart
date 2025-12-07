// lib/pages/blacklist_management.dart (UPDATED - handle externalSuspects + nested maps)
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import 'error.dart'; // Retained for error handling

/// Face Suspect Management Only
class BlacklistManagementPage extends StatefulWidget {
  final String role;

  const BlacklistManagementPage({super.key, required this.role});

  @override
  State<BlacklistManagementPage> createState() => _BlacklistManagementPageState();
}

class _BlacklistManagementPageState extends State<BlacklistManagementPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  // ONLY FACE-related state remains
  bool _loadingFace = false;
  String? _errorFace;

  Map<String, List<String>> _faceMap = {}; // PersonName -> List<URL>
  int _faceTotal = 0;
  bool _isSearching = false;

  final TextEditingController _faceSearchCtrl = TextEditingController();

  final _faceAddFormKey = GlobalKey<FormState>();
  final TextEditingController _faceAddName = TextEditingController();
  XFile? _faceAddImage;

  // TabController length is 1 now, but no tabs are rendered.
  late TabController _tabController;
  final ScrollController _faceScroll = ScrollController();

  Timer? _faceDebounce;

  @override
  void initState() {
    super.initState();
    // Only one tab now
    _tabController = TabController(length: 1, vsync: this);

    _faceSearchCtrl.addListener(() {
      _faceDebounce?.cancel();
      // Search logic for face suspects is local filtering in _fetchFaces
      _faceDebounce = Timer(const Duration(milliseconds: 400), () => _fetchFaces(fromSearch: true));
    });

    _fetchFaces();
  }

  @override
  void dispose() {
    _faceDebounce?.cancel();
    _faceSearchCtrl.dispose();
    _faceAddName.dispose();
    _tabController.dispose();
    _faceScroll.dispose();
    super.dispose();
  }

  /// -----------------------
  /// Fetching function: Uses _api.getSuspects()
  /// Robustly handles:
  ///  - top-level map of "Name": [urls...]
  ///  - wrapper { "suspects": { ... } }
  ///  - wrapper { "externalSuspects": { ... } }
  ///  - mixed wrapper: { "success": true, "externalSuspects": {...}, "localSuspects": {...} }
  /// -----------------------
  Future<void> _fetchFaces({bool fromSearch = false}) async {
    if (!mounted) return;
    setState(() {
      _loadingFace = true;
      _errorFace = null;
    });

    try {
      final resp = await _api.getSuspects();

      // Debug: log what we received
      debugPrint('getSuspects response runtimeType=${resp.runtimeType} body=$resp');

      final Map<String, List<String>> faceMap = {};

      if (resp is Map) {
        // 1) If backend explicitly returns a 'suspects' map, use it.
        if (resp.containsKey('suspects') && resp['suspects'] is Map) {
          final dynamic raw = resp['suspects'];
          raw.forEach((k, v) {
            if (v is List) faceMap[k.toString()] = List<String>.from(v.map((x) => x.toString()));
          });
        }
        // 2) Else if backend uses 'externalSuspects' (your logs), use that
        else if (resp.containsKey('externalSuspects') && resp['externalSuspects'] is Map) {
          final dynamic raw = resp['externalSuspects'];
          raw.forEach((k, v) {
            if (v is List) faceMap[k.toString()] = List<String>.from(v.map((x) => x.toString()));
          });
        }
        // 3) Else attempt to scan the top-level map and merge any nested maps that look like suspect maps.
        else {
          // If resp itself is already a mapping of name -> list, collect those entries.
          // But often resp contains wrapper keys like 'success' which are non-List values.
          resp.forEach((key, value) {
            // Case A: direct personName -> List
            if (value is List) {
              faceMap[key.toString()] = List<String>.from(value.map((x) => x.toString()));
            }
            // Case B: nested Map that contains personName -> List (e.g. externalSuspects: {...})
            else if (value is Map) {
              value.forEach((nk, nv) {
                if (nv is List) {
                  faceMap[nk.toString()] = List<String>.from(nv.map((x) => x.toString()));
                }
              });
            }
            // ignore other types (booleans, strings, numbers)
          });
        }
      } else {
        // Not a Map at all
        if (!mounted) return;
        setState(() => _errorFace = 'Invalid server response: expected JSON object');
        return;
      }

      // If still empty, show debugging message
      if (faceMap.isEmpty) {
        debugPrint('Parsed faceMap is empty after scanning response. Full resp: $resp');
      } else {
        debugPrint('Parsed faceMap keys: ${faceMap.keys.toList()} (total ${faceMap.length})');
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
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorFace = 'API Error loading face suspects: ${e.message}');
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

  // MODIFIED to use _api.addSuspect()
  Future<void> _addFaceSuspect() async {
    if (!_faceAddFormKey.currentState!.validate()) return;
    if (_faceAddImage == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an image'), backgroundColor: Colors.red));
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final resp = await _api.addSuspect(
        suspectName: _faceAddName.text.trim(),
        imageFile: File(_faceAddImage!.path),
      );

      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      // Debug log
      debugPrint('addSuspect response: $resp');

      if (!mounted) return;

      if (resp is Map) {
        final status = resp['status']?.toString().toLowerCase();
        final success = resp['success'] == true || resp['ok'] == true || status == 'queued_rebuild';
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suspect added successfully!'), backgroundColor: Colors.green));
          await _fetchFaces();
        } else {
          final msg = resp['message'] ?? resp['detail'] ?? 'Failed to add face suspect';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unexpected server response while adding suspect'), backgroundColor: Colors.red));
      }
    } on ApiException catch (e) {
      // Ensure loader removed
      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: ${e.message}'), backgroundColor: Colors.red));
    } catch (e) {
      // Ensure loader removed
      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $e'), backgroundColor: Colors.red));
    }
  }

  // MODIFIED to use _api.deleteSuspectByName()
  Future<bool> _deleteFaceSuspectApi(String personName) async {
    try {
      final resp = await _api.deleteSuspectByName(personName);
      debugPrint('deleteSuspectByName response: $resp');
      if (resp is Map) {
        // Accept several server signals as success:
        // - explicit success flag
        // - deleted count > 0
        // - status == 'queued_rebuild' (per your FastAPI doc)
        final status = resp['status']?.toString().toLowerCase();
        if (resp['success'] == true) return true;
        if (resp['deleted'] is num && resp['deleted'] > 0) return true;
        if (status == 'queued_rebuild' || (resp['detail'] is String && resp['detail'].toString().toLowerCase().contains('deleted'))) return true;
      }
      return false;
    } on ApiException catch (e) {
      debugPrint('Delete failed due to API exception: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Delete failed due to network/error: $e');
      return false;
    }
  }

  /// -----------------------
  /// UI pieces
  /// -----------------------

  // Consolidated list builder for Face suspects
  Widget _buildListContent(String? error, bool loading, ScrollController scrollController) {
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
          final List<String> images = _faceMap[personName]!;

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
                  await _fetchFaces();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suspect deleted successfully!'), backgroundColor: Colors.green));
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete suspect'), backgroundColor: Colors.red));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
                success = false;
              } finally {
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

  // Kept as helper for face images (URL-encode path)
  String? _convertGsUrlToHttp(String? gsUrl) {
    if (gsUrl == null || !gsUrl.startsWith('gs://')) return gsUrl;
    final parts = gsUrl.substring(5).split('/');
    if (parts.length < 2) return null;
    final bucket = parts.first;
    final objectPath = parts.sublist(1).join('/');
    final encodedPath = Uri.encodeFull(objectPath); // important for spaces/special chars
    return 'https://storage.googleapis.com/$bucket/$encodedPath';
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
    _faceAddName.clear();
    _faceAddImage = null;

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
                key: _faceAddFormKey,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Add New Suspect', style: Theme.of(context).textTheme.titleLarge),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ]),
                  const SizedBox(height: 20),

                  // Face-specific input fields
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
                                final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
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
                                final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _addFaceSuspect,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Add Suspect'),
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

  // Simplified show details for face only
  void _showSuspectDetails(BuildContext parentContext, String name, List<dynamic> imageUrls) {
    final List<String> urls = imageUrls.map((e) => e.toString()).toList();
    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(builder: (localStateCtx, setState2) {
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
                        child: urls.isNotEmpty
                            ? Image.network(
                          _convertGsUrlToHttp(urls.first)!,
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
                    ...urls.map((url) => Text('- ${url.split('/').last}')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(localStateCtx).pop(), child: const Text('Close')),
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

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      useRootNavigator: true,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    bool success = false;
                    try {
                      success = await _deleteFaceSuspectApi(name);

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
                        Navigator.of(localStateCtx).pop();
                      } else {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete suspect'), backgroundColor: Colors.red));
                      }
                    } catch (e) {
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
    final TextEditingController activeSearchController = _faceSearchCtrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suspect Management'),
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
          // Adjusted height since TabBar is removed
          preferredSize: Size.fromHeight(_isSearching ? 64.0 : 0.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TextField(
                    controller: activeSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search suspect name...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _isSearching = false;
                            _faceSearchCtrl.clear();
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
                      _fetchFaces(fromSearch: true);
                    },
                  ),
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
      body: _buildListContent(_errorFace, _loadingFace, _faceScroll),
    );
  }
}
