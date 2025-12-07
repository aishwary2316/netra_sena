// lib/pages/verification.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Enum for per-field states (top-level; must not be declared inside a class)
enum FieldState { normal, suspicious, missing, serviceUnavailable }

/// High-level wrapper: creates ApiService and calls showVerificationDialog.
Future<void> verifyDriverAndShowDialog(
    BuildContext context, {
      File? driverImageFile,
      String location = 'N/A',
      String tollgate = 'NA',
    }) async {
  final api = ApiService();
  await showVerificationDialog(
    context,
    api: api,
    driverImage: driverImageFile,
    location: location,
    tollgate: tollgate,
  );
}

/// Performs the verification call via ApiService.scanFace and shows the rich dialog.
Future<void> showVerificationDialog(
    BuildContext context, {
      required ApiService api,
      File? driverImage,
      String location = 'N/A',
      String tollgate = 'NA',
    }) async {
  if (driverImage == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please provide a person\'s image to verify.')),
    );
    return;
  }

  // Show loading while contacting server
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Container(
      color: Colors.black54,
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text(
                  'Scanning Face...', // UPDATED TEXT
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Map<String, dynamic> bodyMap = {};
  String? errorMessage;

  try {
    final result = await api.scanFace(
      imageFile: driverImage,
      extraFields: {
        'location': location,
        'tollgate': tollgate,
      },
    );

    debugPrint('scanFace raw response: $result');

    // Ensure result is a Map
    if (result is Map<String, dynamic>) {
      // Helper to try to extract the best candidate map that contains meaningful keys (status/name/score/message/etc.)
      Map<String, dynamic>? _extractDriverData(Map<String, dynamic> m) {
        // Common wrappers
        for (final k in ['driverData', 'data', 'result', 'recognition', 'payload']) {
          if (m.containsKey(k) && m[k] is Map) {
            return Map<String, dynamic>.from(m[k] as Map);
          }
        }

        // If current map itself looks like the recognition response (contains 'status' or 'score' or 'saved' etc.), return it
        final topKeys = m.keys.map((k) => k.toString().toLowerCase()).toList();
        final sentinelKeys = ['status', 'score', 'saved', 'local_backup', 'name', 'message', 'match_name', 'person_name'];
        if (topKeys.any((tk) => sentinelKeys.contains(tk))) {
          return Map<String, dynamic>.from(m);
        }

        // Otherwise scan nested maps and return the first nested map that looks like a recognition object
        for (final v in m.values) {
          if (v is Map) {
            final nestedKeys = v.keys.map((k) => k.toString().toLowerCase()).toList();
            if (nestedKeys.any((nk) => sentinelKeys.contains(nk))) {
              return Map<String, dynamic>.from(v);
            }
          }
        }

        return null;
      }

      final Map<String, dynamic>? driverData = _extractDriverData(result);

      if (driverData != null) {
        // Use the driverData and set suspicious flag based on status
        bodyMap['driverData'] = driverData;
        final status = (driverData['status'] ?? '').toString().toLowerCase();
        bodyMap['suspicious'] = (status == 'alert' || status == 'blacklisted' || status == 'match' || status == 'suspicious');
      } else {
        // No candidate map found — check for explicit success/ok wrappers that might still contain nested maps
        if (result['success'] == true || result['ok'] == true) {
          // Try again to find nested map entries inside the wrapper
          bool merged = false;
          final Map<String, dynamic> mergedMap = {};
          result.forEach((k, v) {
            if (v is Map) {
              v.forEach((nk, nv) {
                // take first plausible nested mapping entries
                mergedMap[nk.toString()] = nv;
              });
            }
          });

          if (mergedMap.isNotEmpty) {
            final maybe = _extractDriverData(mergedMap);
            if (maybe != null) {
              bodyMap['driverData'] = maybe;
              final status = (maybe['status'] ?? '').toString().toLowerCase();
              bodyMap['suspicious'] = (status == 'alert' || status == 'blacklisted' || status == 'match' || status == 'suspicious');
              merged = true;
            }
          }

          if (!merged) {
            // Could not locate meaningful data despite success flag
            errorMessage = result['message']?.toString() ?? 'Unexpected success response shape from server';
          }
        } else {
          // Server returned some other shape — try to fetch message or error
          final serverMessage = result['message'] ?? result['error'];
          if (serverMessage != null) {
            errorMessage = serverMessage.toString();
          } else {
            errorMessage = 'Face scan failed: unexpected response structure';
          }
        }
      }
    } else {
      errorMessage = 'Unexpected server response (not a JSON object)';
    }
  } on ApiException catch (e) {
    debugPrint('ApiException in scanFace: ${e.message}');
    errorMessage = 'API Error: ${e.message}';
  } catch (e) {
    debugPrint('Exception in scanFace: $e');
    errorMessage = 'An error occurred during verification: $e';
  }

  // Dismiss loading dialog
  try {
    Navigator.of(context, rootNavigator: true).pop();
  } catch (_) {}

  // If there was an error, populate a fallback driverData so the dashboard shows an INCOMPLETE / service-unavailable view (yellow)
  if (errorMessage != null) {
    bodyMap = {
      'driverData': {
        'status': 'service_unavailable',
        'message': errorMessage,
        'provided': true,
      },
      'suspicious': false,
      'note': 'Error from server or unexpected response. See message for details.',
    };
  } else {
    // Defensive fallback if parsing produced nothing
    if (bodyMap.isEmpty || !bodyMap.containsKey('driverData')) {
      bodyMap = {
        'driverData': driverImage != null ? {'status': 'N/A', 'provided': true, 'message': 'Empty or unexpected response from backend.'} : null,
        'suspicious': false,
        'note': 'Empty server body — showing local preview.',
      };
    }
  }

  // Navigate to the new dashboard page (always show dashboard so errors are visible in the UI)
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => VerificationDashboard(api: api, body: bodyMap, driverImage: driverImage),
    ),
  );
}

/// New widget that displays the verification result on a full-page dashboard.
class VerificationDashboard extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> body;
  final File? driverImage; // optional image to show a thumbnail

  const VerificationDashboard({super.key, required this.api, required this.body, this.driverImage});

  @override
  State<VerificationDashboard> createState() => _VerificationDashboardState();
}

class _VerificationDashboardState extends State<VerificationDashboard> with TickerProviderStateMixin {
  bool _showRawJson = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Responsive scale helper (unchanged)
  double _scale() {
    final w = MediaQuery.of(context).size.width;
    final raw = w / 390.0;
    return math.max(0.85, math.min(1.15, raw));
  }

  Map<String, dynamic>? get driverData => widget.body['driverData'] is Map ? Map<String, dynamic>.from(widget.body['driverData']) : null;
  bool get suspiciousFlag => widget.body['suspicious'] == true;

  /// Return concise user-facing reason when a field is suspicious or unavailable.
  String? _extractReason(Map<String, dynamic>? data) {
    if (data == null) return null;
    if (data['reason'] != null) return data['reason'].toString();
    if (data['message'] != null) return data['message'].toString();
    if (data['note'] != null) return data['note'].toString();
    if (data['description'] != null) return data['description'].toString();

    // status-based reasons
    final status = (data['status'] ?? data['verification'] ?? '').toString();
    if (status.isNotEmpty) return status;

    return null;
  }

  /// Determine per-field state from API data
  FieldState _stateFromData(Map<String, dynamic>? data, {String kind = 'generic'}) {
    if (data == null) return FieldState.missing;

    final status = (data['status'] ?? data['verification'] ?? '').toString().toLowerCase();

    // Positive suspicious indicators
    if (status == 'blacklisted' || status == 'suspicious' || status == 'suspended' || status == 'blocked') {
      return FieldState.suspicious;
    }
    if (status == 'alert' || status == 'match') {
      return FieldState.suspicious;
    }

    // Service unavailable / error
    if (status == 'service_unavailable' || status == 'serviceunavailable' || status == 'unavailable' || status == 'error') {
      return FieldState.serviceUnavailable;
    }

    // Check for match/result arrays
    for (final k in ['matches', 'results']) {
      if (data.containsKey(k) && data[k] is List && (data[k] as List).isNotEmpty) return FieldState.suspicious;
    }

    // Treat explicit numeric counts > 0 as suspicious
    for (final k in ['count', 'matches_count', 'total']) {
      if (data.containsKey(k) && (data[k] is num) && (data[k] as num) > 0) return FieldState.suspicious;
    }

    // Treat other empty/NA-like values as normal
    final lowered = status.trim();
    if (lowered.isEmpty || lowered == 'not_found' || lowered == 'n/a' || lowered == 'na' || lowered == 'none') {
      return FieldState.normal;
    }

    return FieldState.normal;
  }

  /// Build a list of suspicious reasons (only positive matches).
  List<String> _suspiciousReasons() {
    final List<String> reasons = [];
    final faceSt = _stateFromData(driverData);

    if (faceSt == FieldState.suspicious) {
      final r = _extractReason(driverData) ?? 'Person\'s face matched a suspicious entry';
      reasons.add('Face: $r');
    }

    // honor global suspicious flag if set by backend
    if (suspiciousFlag && reasons.isEmpty) {
      reasons.add('Backend flagged this entry as suspicious (see raw JSON for details).');
    }

    return reasons;
  }

  // Shorthand helpers for top-level checks (ONLY FACE)
  FieldState get _faceState => _stateFromData(driverData, kind: 'face');

  bool get _anySuspicious => _faceState == FieldState.suspicious || suspiciousFlag;
  bool get _anyMissingOrError => _faceState == FieldState.missing || _faceState == FieldState.serviceUnavailable;

  /// Provide the overall banner color
  Color get _overallColor {
    if (_anySuspicious) return const Color(0xFFE53E3E);
    if (_anyMissingOrError) return Colors.orange.shade700;
    return const Color(0xFF38A169);
  }

  /// Provide main banner text
  String get _overallText {
    if (_anySuspicious) return 'SUSPICIOUS';
    if (_anyMissingOrError) return 'INCOMPLETE';
    return 'AUTHORIZED';
  }

  /// Provide main banner icon
  IconData get _overallIcon {
    if (_anySuspicious) return Icons.dangerous;
    if (_anyMissingOrError) return Icons.warning_amber;
    return Icons.verified;
  }

  // ---------------- Summary Row builder for verification summary -----------
  Widget _buildSummaryRow({required String title, required FieldState state, String? reason}) {
    final s = _scale();
    Color getColor() {
      switch (state) {
        case FieldState.suspicious:
          return const Color(0xFFE53E3E);
        case FieldState.missing:
        case FieldState.serviceUnavailable:
          return Colors.orange.shade700;
        case FieldState.normal:
        default:
          return const Color(0xFF38A169);
      }
    }

    IconData getIcon() {
      switch (state) {
        case FieldState.suspicious:
          return Icons.cancel;
        case FieldState.missing:
        case FieldState.serviceUnavailable:
          return Icons.info_outline;
        case FieldState.normal:
        default:
          return Icons.check_circle;
      }
    }

    final c = getColor();
    final icon = getIcon();

    String subtitle;
    if (state == FieldState.normal) {
      subtitle = 'Clear — not listed as suspicious';
    } else if (state == FieldState.suspicious) {
      subtitle = reason ?? 'Matched in suspect DB';
    } else if (state == FieldState.serviceUnavailable) {
      subtitle = reason ?? 'Service unavailable for this check';
    } else {
      subtitle = reason ?? 'No face image provided';
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8 * s),
            decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18 * s, color: c),
          ),
          SizedBox(width: 10 * s),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14 * s)),
              SizedBox(height: 4 * s),
              Text(subtitle, style: TextStyle(color: c, fontSize: 12 * s)),
            ]),
          ),
          // When suspicious show a compact details hint
          if (state == FieldState.suspicious)
            IconButton(
              icon: Icon(Icons.chevron_right, color: Colors.red.shade400, size: 20 * s),
              onPressed: () {
                setState(() {
                  _showRawJson = true;
                });
              },
              splashRadius: 20,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _scale();
    final screenW = MediaQuery.of(context).size.width;
    final horizontalPadding = screenW > 600 ? 20.0 : 12.0;

    final displayData = driverData ?? {};
    // Keys tailored for typical face recognition response
    final primaryKeys = ['name', 'status', 'match_name', 'person_name'];
    final detailsKeys = ['message', 'face_matched', 'confidence', 'score', 'raw_result', 'detection_time'];

    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), color: Colors.white),
      ),
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text('Face Verification Dashboard', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 18 * s)),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E40AF),
          elevation: 0,
          leading: IconButton(icon: Icon(Icons.arrow_back, color: Colors.white, size: 20 * s), onPressed: () => Navigator.of(context).pop()),
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 14 * s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ---------- Top Status Card ----------
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16 * s),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [_overallColor.withOpacity(0.12), _overallColor.withOpacity(0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _overallColor.withOpacity(0.24), width: 1.0),
                    boxShadow: [BoxShadow(color: _overallColor.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  child: Column(children: [
                    Icon(_overallIcon, color: _overallColor, size: 40 * s),
                    SizedBox(height: 8 * s),
                    Text(_overallText, style: TextStyle(color: _overallColor, fontWeight: FontWeight.bold, fontSize: 22 * s, letterSpacing: 0.8)),
                    SizedBox(height: 6 * s),
                    Text(
                      _anySuspicious
                          ? 'Suspect match found against the database'
                          : (_anyMissingOrError ? 'Verification incomplete. Check logs for service errors.' : 'Face scan completed successfully'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _overallColor.withOpacity(0.85), fontSize: 12 * s, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 10 * s),
                    if (!_anySuspicious && _anyMissingOrError)
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            border: Border.all(color: Colors.orange.shade200),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.info_outline, size: 14 * s, color: Colors.orange.shade700),
                            SizedBox(width: 8 * s),
                            Text('Incomplete verification or service unavailable', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w600, fontSize: 12 * s)),
                          ]),
                        ),
                      ),
                  ]),
                ),

                SizedBox(height: 16 * s),

                // Verification Summary (ONLY FACE)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12 * s),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.assignment_turned_in, color: Colors.blue.shade700, size: 18 * s),
                      SizedBox(width: 10 * s),
                      Expanded(child: Text('Verification Summary', style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.bold))),
                    ]),
                    SizedBox(height: 10 * s),

                    // Face row ONLY
                    _buildSummaryRow(
                      title: 'Person\'s Face',
                      state: _faceState,
                      reason: _extractReason(displayData),
                    ),

                    // Suspicious footer hint
                    if (_anySuspicious) ...[
                      SizedBox(height: 10 * s),
                      Container(
                        padding: EdgeInsets.all(10 * s),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade100)),
                        child: Row(children: [
                          Icon(Icons.warning, color: Colors.red.shade700, size: 16 * s),
                          SizedBox(width: 8 * s),
                          Expanded(child: Text('Suspect match found.', style: TextStyle(color: Colors.red.shade700, fontSize: 12 * s))),
                        ]),
                      ),
                    ],
                  ]),
                ),

                SizedBox(height: 16 * s),

                // Information Cards (ONLY DRIVER REMAINS)
                _buildInfoCard(
                  title: 'Suspect Information',
                  icon: Icons.person,
                  data: displayData,
                  primaryKeys: primaryKeys.where((key) => displayData.containsKey(key)).toList(),
                  detailsKeys: detailsKeys.where((key) => displayData.containsKey(key)).toList(),
                  color: Colors.purple,
                ),

                SizedBox(height: 18 * s),

                // JSON Toggle
                Center(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showRawJson = !_showRawJson;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_showRawJson ? Icons.visibility_off : Icons.code, size: 18 * s, color: Colors.grey.shade700),
                        SizedBox(width: 8 * s),
                        Text(_showRawJson ? 'Hide Raw JSON' : 'View Raw JSON', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500, fontSize: 13 * s)),
                      ]),
                    ),
                  ),
                ),

                if (_showRawJson) ...[
                  SizedBox(height: 12 * s),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12 * s),
                    decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade700)),
                    child: SelectableText(
                      JsonEncoder.withIndent('  ').convert(widget.body),
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12 * s, color: Colors.green, height: 1.4),
                    ),
                  ),
                ],

                SizedBox(height: 16 * s),

                // Action Buttons (Only Close remains)
                Row(children: [
                  Expanded(
                    child: Container(
                      height: math.max(44 * s, 48),
                      margin: EdgeInsets.symmetric(horizontal: 8 * s),
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.close, size: 18 * s),
                        label: Text('Close', style: TextStyle(fontSize: 14 * s)),
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.grey.shade700, side: BorderSide(color: Colors.grey.shade400), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      ),
                    ),
                  ),
                ]),

                SizedBox(height: 12 * s),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Map<String, dynamic>? data,
    required List<String> primaryKeys,
    required List<String> detailsKeys,
    required Color color,
  }) {
    final s = _scale();

    if (data == null || data.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12 * s),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: EdgeInsets.all(8 * s), decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 20 * s)),
            SizedBox(width: 10 * s),
            Text(title, style: TextStyle(fontSize: 16 * s, fontWeight: FontWeight.bold)),
          ]),
          SizedBox(height: 10 * s),
          Container(padding: EdgeInsets.all(12 * s), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(Icons.info_outline, color: Colors.grey.shade600, size: 18 * s), SizedBox(width: 10 * s), Text('No data available for this section', style: TextStyle(color: Colors.grey, fontSize: 13 * s))])),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: EdgeInsets.all(12 * s),
          decoration: BoxDecoration(color: color.withOpacity(0.04), borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
          child: Row(children: [
            Container(padding: EdgeInsets.all(8 * s), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20 * s)),
            SizedBox(width: 12 * s),
            Expanded(child: Text(title, style: TextStyle(fontSize: 16 * s, fontWeight: FontWeight.bold, color: Colors.black87))),
          ]),
        ),

        // Primary Information
        Padding(
          padding: EdgeInsets.all(12 * s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // If this is driver info and a file was passed, show thumbnail
            if (title == 'Suspect Information' && widget.driverImage != null) ...[
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    widget.driverImage!,
                    width: math.min(140 * s, MediaQuery.of(context).size.width * 0.45),
                    height: math.min(140 * s, MediaQuery.of(context).size.width * 0.45),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(height: 10 * s),
            ],

            ...primaryKeys.where((key) => data.containsKey(key)).map((key) {
              final value = data[key].toString();
              return Padding(
                padding: EdgeInsets.only(bottom: 10 * s),
                child: Container(
                  padding: EdgeInsets.all(12 * s),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 4 * s, height: 18 * s, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    SizedBox(width: 10 * s),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_formatLabel(key), style: TextStyle(fontSize: 12 * s, fontWeight: FontWeight.w600, color: Colors.grey.shade600, letterSpacing: 0.2)),
                        SizedBox(height: 6 * s),
                        Text(value, style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w600, color: Colors.black87)),
                      ]),
                    ),
                  ]),
                ),
              );
            }).toList(),

            // Additional Details Section
            if (detailsKeys.any((key) => data.containsKey(key)))
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.only(top: 6 * s),
                leading: Container(padding: EdgeInsets.all(6 * s), decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.expand_more, color: color, size: 16 * s)),
                title: Text('Additional Details', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black, fontSize: 14 * s)),
                children: [
                  Container(
                    padding: EdgeInsets.all(10 * s),
                    decoration: BoxDecoration(color: color.withOpacity(0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.08))),
                    child: Column(
                      children: detailsKeys.where((key) => data.containsKey(key)).map((key) {
                        final value = data[key].toString();
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 6 * s),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: math.min(110 * s, MediaQuery.of(context).size.width * 0.35), child: Text(_formatLabel(key), style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
                            Expanded(child: Text(value, style: TextStyle(fontSize: 13 * s, color: Colors.grey.shade800, height: 1.3))),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
          ]),
        ),
      ]),
    );
  }

  String _formatLabel(String key) {
    return key.replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase()).join(' ');
  }
}
