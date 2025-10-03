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
      String? dlNumber,
      String? rcNumber,
      File? driverImageFile,
      String location = 'Toll-Plaza-1',
      String tollgate = 'Gate-A',
    }) async {
  final api = ApiService();
  await showVerificationDialog(
    context,
    api: api,
    dlNumber: dlNumber,
    rcNumber: rcNumber,
    driverImage: driverImageFile,
    location: location,
    tollgate: tollgate,
  );
}

/// Performs the verification call via ApiService.verifyDriver and shows the rich dialog.
Future<void> showVerificationDialog(
    BuildContext context, {
      required ApiService api,
      String? dlNumber,
      String? rcNumber,
      File? driverImage,
      String location = 'Toll-Plaza-1',
      String tollgate = 'Gate-A',
    }) async {
  // Validate at least one input provided
  if ((dlNumber == null || dlNumber.trim().isEmpty) &&
      (rcNumber == null || rcNumber.trim().isEmpty) &&
      driverImage == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please provide DL, RC, or Driver image to verify.')),
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
                  'Verifying...',
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
    // Call the main OnRender backend for DL and RC verification
    final result = await api.verifyDriver(
      dlNumber: dlNumber != null && dlNumber.trim().isNotEmpty ? dlNumber.trim() : null,
      rcNumber: rcNumber != null && rcNumber.trim().isNotEmpty ? rcNumber.trim() : null,
      location: location,
      tollgate: tollgate,
      driverImage: null, // Do not send image to this backend
    );

    if (result['ok'] == true) {
      final d = result['data'];
      if (d is Map) {
        bodyMap = Map<String, dynamic>.from(d);
      } else {
        bodyMap = {'raw': d};
      }
    } else {
      // server returned ok=false -> build a helpful message
      if (result['message'] != null) {
        errorMessage = result['message'].toString();
      } else if (result['body'] != null) {
        try {
          errorMessage = JsonEncoder.withIndent('  ').convert(result['body']);
        } catch (_) {
          errorMessage = result['body'].toString();
        }
      } else {
        errorMessage = 'Verification failed (status unknown)';
      }
    }
  } catch (e) {
    errorMessage = 'An error occurred during verification: $e';
  }

  // Perform face recognition separately if a driver image is provided
  if (driverImage != null) {
    try {
      final faceResult = await api.recognizeFace(driverImage.path);
      if (faceResult['ok'] == true) {
        // Merge face recognition data into the main bodyMap
        bodyMap['driverData'] = {
          'status': faceResult['data']['status'],
          'message': faceResult['data']['message'],
          'name': faceResult['data']['name'] ?? 'N/A',
        };
      } else {
        // Set an error status for face recognition
        bodyMap['driverData'] = {
          'status': 'SERVICE_UNAVAILABLE',
          'message': faceResult['message'] ?? 'Face recognition failed.',
        };
      }
    } catch (e) {
      // Set an error status if the face recognition call fails
      bodyMap['driverData'] = {
        'status': 'SERVICE_UNAVAILABLE',
        'message': 'Face recognition network error: $e',
      };
    }
  }

  // Dismiss loading dialog (explicitly target the root navigator that showDialog used).
  // Use try/catch to avoid throwing if the dialog was already dismissed.
  try {
    Navigator.of(context, rootNavigator: true).pop();
  } catch (_) {
    // Fallback: if that didn't work, pop the nearest navigator if possible.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  if (errorMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    return;
  }

  // Ensure bodyMap is non-empty; if empty, create a minimal body so dashboard shows something useful
  if (bodyMap.isEmpty) {
    bodyMap = {
      'dlData': dlNumber != null && dlNumber.trim().isNotEmpty ? {'licenseNumber': dlNumber.trim(), 'status': 'N/A'} : null,
      'rcData': rcNumber != null && rcNumber.trim().isNotEmpty ? {'regn_number': rcNumber.trim(), 'status': 'N/A'} : null,
      'driverData': driverImage != null ? {'status': 'N/A', 'provided': true} : null,
      'suspicious': false,
      'note': 'Empty server body — showing local preview.',
    };
  }

  // Navigate to the new dashboard page and pass the optional driver image file too
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
  bool _fetchingUsage = false;
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

  // Responsive scale helper (based on screen width)
  double _scale() {
    final w = MediaQuery.of(context).size.width;
    // base width 390 (approx iPhone 12). clamp to [0.85, 1.15]
    final raw = w / 390.0;
    return math.max(0.85, math.min(1.15, raw));
  }

  Map<String, dynamic>? get dlData => widget.body['dlData'] is Map ? Map<String, dynamic>.from(widget.body['dlData']) : null;
  Map<String, dynamic>? get rcData => widget.body['rcData'] is Map ? Map<String, dynamic>.from(widget.body['rcData']) : null;
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
    // If no data provided -> mark missing
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
    if (status == 'service_unavailable' || status == 'serviceunavailable' || status == 'unavailable') {
      return FieldState.serviceUnavailable;
    }

    // If backend provides arrays of matches, non-empty => suspicious
    for (final k in ['matches', 'dl_matches', 'detected_plates', 'matches_list', 'results']) {
      if (data.containsKey(k) && data[k] is List && (data[k] as List).isNotEmpty) return FieldState.suspicious;
    }

    // Treat explicit numeric counts > 0 as suspicious
    for (final k in ['count', 'matches_count', 'total']) {
      if (data.containsKey(k) && (data[k] is num) && (data[k] as num) > 0) return FieldState.suspicious;
    }

    // IMPORTANT: treat 'not_found' as NORMAL (your DB contains only suspicious entries)
    // Treat other empty/NA-like values as normal
    final lowered = status.trim();
    if (lowered.isEmpty || lowered == 'not_found' || lowered == 'n/a' || lowered == 'na' || lowered == 'none') {
      return FieldState.normal;
    }

    // Default to normal if nothing positive found
    return FieldState.normal;
  }

  /// Build a list of suspicious reasons (only positive matches).
  List<String> _suspiciousReasons() {
    final List<String> reasons = [];
    final dlSt = _stateFromData(dlData);
    final rcSt = _stateFromData(rcData);
    final faceSt = _stateFromData(driverData);

    if (dlSt == FieldState.suspicious) {
      final r = _extractReason(dlData) ?? 'Driving License matched a suspicious entry';
      reasons.add('DL: $r');
    }
    if (rcSt == FieldState.suspicious) {
      final r = _extractReason(rcData) ?? 'Vehicle/Plate matched a suspicious entry';
      reasons.add('RC: $r');
    }
    if (faceSt == FieldState.suspicious) {
      final r = _extractReason(driverData) ?? 'Driver face matched a suspicious entry';
      reasons.add('Face: $r');
    }

    // honor global suspicious flag if set by backend
    if (suspiciousFlag && reasons.isEmpty) {
      reasons.add('Backend flagged this entry as suspicious (see raw JSON for details).');
    }

    return reasons;
  }

  // Shorthand helpers for top-level checks
  FieldState get _dlState => _stateFromData(dlData, kind: 'dl');
  FieldState get _rcState => _stateFromData(rcData, kind: 'rc');
  FieldState get _faceState => _stateFromData(driverData, kind: 'face');

  bool get _anySuspicious => _dlState == FieldState.suspicious || _rcState == FieldState.suspicious || _faceState == FieldState.suspicious;
  bool get _anyMissingOrError =>
      _dlState == FieldState.missing ||
          _rcState == FieldState.missing ||
          _faceState == FieldState.missing ||
          _dlState == FieldState.serviceUnavailable ||
          _rcState == FieldState.serviceUnavailable ||
          _faceState == FieldState.serviceUnavailable;

  /// Provide the overall banner color (RED only when any suspicious; otherwise GREEN)
  Color get _overallColor {
    if (_anySuspicious) return const Color(0xFFE53E3E);
    return const Color(0xFF38A169);
  }

  /// Provide main banner text
  String get _overallText {
    if (_anySuspicious) return 'SUSPICIOUS';
    return 'AUTHORIZED';
  }

  /// Provide main banner icon
  IconData get _overallIcon {
    if (_anySuspicious) return Icons.dangerous;
    return Icons.verified;
  }

  Future<void> _fetchDLUsage(String dlNum) async {
    setState(() => _fetchingUsage = true);
    try {
      final usage = await widget.api.getDLUsage(dlNum);
      if (usage['ok'] == true) {
        final data = usage['data'] ?? [];
        _showDLUsageDialog(dlNum, data);
      } else {
        final msg = usage['message'] ?? 'Failed to fetch DL usage';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching usage: $e')));
    } finally {
      setState(() => _fetchingUsage = false);
    }
  }

  void _showDLUsageDialog(String dlNumber, dynamic logs) {
    final List logsList = (logs is List) ? logs : [];
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(14 * _scale()),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, color: Colors.blue.shade700, size: 20 * _scale()),
                    SizedBox(width: 10 * _scale()),
                    Expanded(
                      child: Text(
                        'DL Usage History',
                        style: TextStyle(fontSize: 16 * _scale(), fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                      ),
                    ),
                    IconButton(icon: Icon(Icons.close, size: 20 * _scale()), onPressed: () => Navigator.of(ctx).pop(), splashRadius: 20),
                  ],
                ),
              ),
              Expanded(
                child: logsList.isEmpty
                    ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(20 * _scale()),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 44 * _scale(), color: Colors.grey),
                        SizedBox(height: 12 * _scale()),
                        Text('No Recent Usage', style: TextStyle(fontSize: 16 * _scale(), fontWeight: FontWeight.w600, color: Colors.grey)),
                        SizedBox(height: 8 * _scale()),
                        Text('No usage logs found for this DL in the last 2 days.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
                    : ListView.separated(
                  padding: EdgeInsets.all(12 * _scale()),
                  itemCount: logsList.length,
                  separatorBuilder: (_, __) => Divider(height: 18 * _scale()),
                  itemBuilder: (c, i) {
                    final item = logsList[i] is Map ? Map<String, dynamic>.from(logsList[i]) : {'raw': logsList[i]};
                    final ts = item['timestamp'] ?? item['time'] ?? '';
                    final vehicleNumber = item['vehicle_number'] ?? item['vehicle'] ?? 'N/A';

                    return Container(
                      padding: EdgeInsets.all(12 * _scale()),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.directions_car, color: Colors.blue.shade600, size: 18 * _scale()),
                              SizedBox(width: 8 * _scale()),
                              Expanded(
                                child: Text('Vehicle: $vehicleNumber', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14 * _scale())),
                              ),
                            ],
                          ),
                          if (item['dl_number'] != null) ...[
                            SizedBox(height: 8 * _scale()),
                            _buildDetailRow(Icons.credit_card, 'DL Number', item['dl_number'].toString(), color: Colors.grey.shade700),
                          ],
                          if (item['alert_type'] != null) ...[
                            SizedBox(height: 8 * _scale()),
                            _buildDetailRow(Icons.warning, 'Alert Type', item['alert_type'].toString(), color: Colors.orange.shade700),
                          ],
                          if (item['description'] != null) ...[
                            SizedBox(height: 8 * _scale()),
                            _buildDetailRow(Icons.description, 'Description', item['description'].toString(), color: Colors.grey.shade700),
                          ],
                          if (ts.isNotEmpty) ...[
                            SizedBox(height: 8 * _scale()),
                            _buildDetailRow(Icons.access_time, 'Time', ts.toString(), color: Colors.grey.shade700),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    final s = _scale();
    return Row(
      children: [
        Icon(icon, size: 14 * s, color: color ?? Colors.grey.shade600),
        SizedBox(width: 8 * s),
        Text('$label: ', style: TextStyle(fontSize: 13 * s, color: color ?? Colors.grey.shade700, fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13 * s, color: color ?? Colors.grey.shade800))),
      ],
    );
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
          return Icons.cancel; // red cross
        case FieldState.missing:
        case FieldState.serviceUnavailable:
          return Icons.info_outline; // orange info
        case FieldState.normal:
        default:
          return Icons.check_circle; // green tick
      }
    }

    final c = getColor();
    final icon = getIcon();

    String subtitle;
    if (state == FieldState.normal) {
      subtitle = 'Clear — not listed as suspicious';
    } else if (state == FieldState.suspicious) {
      subtitle = reason ?? 'Matched in suspicious DB';
    } else if (state == FieldState.serviceUnavailable) {
      subtitle = reason ?? 'Service unavailable for this check';
    } else {
      subtitle = reason ?? 'No data provided';
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
    // small horizontal padding for narrow devices
    final horizontalPadding = screenW > 600 ? 20.0 : 12.0;

    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), color: Colors.white),
      ),
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text('Verification Dashboard', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 18 * s)),
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
                // ---------- NEW: Top Status + Verification Summary ----------
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
                      // subtitle tuned based on presence of suspicious/missing
                      _anySuspicious
                          ? 'One or more checks returned suspicious matches'
                          : (_anyMissingOrError ? 'Available checks are clear. Some fields are incomplete or services unavailable.' : 'All verifications completed successfully'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _overallColor.withOpacity(0.85), fontSize: 12 * s, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 10 * s),
                    // Show a small yellow badge for incomplete / service-unavailable *only when not suspicious*
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
                            Text('Incomplete fields or services unavailable', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w600, fontSize: 12 * s)),
                          ]),
                        ),
                      ),
                  ]),
                ),

                SizedBox(height: 16 * s),

                // Verification Summary (replaces Alert Details)
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

                    // DL row
                    _buildSummaryRow(
                      title: 'Driving License',
                      state: _dlState,
                      reason: _extractReason(dlData),
                    ),

                    // RC row
                    _buildSummaryRow(
                      title: 'Number Plate / RC',
                      state: _rcState,
                      reason: _extractReason(rcData),
                    ),

                    // Face row
                    _buildSummaryRow(
                      title: 'Driver Face',
                      state: _faceState,
                      reason: _extractReason(driverData),
                    ),

                    // If there are suspicious reasons, show a compact red footer hint
                    if (_suspiciousReasons().isNotEmpty) ...[
                      SizedBox(height: 10 * s),
                      Container(
                        padding: EdgeInsets.all(10 * s),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade100)),
                        child: Row(children: [
                          Icon(Icons.warning, color: Colors.red.shade700, size: 16 * s),
                          SizedBox(width: 8 * s),
                          Expanded(child: Text('Suspicious matches found.', style: TextStyle(color: Colors.red.shade700, fontSize: 12 * s))),
                        ]),
                      ),
                    ],
                  ]),
                ),

                SizedBox(height: 16 * s),

                // Information Cards
                _buildInfoCard(
                  title: 'Driving License',
                  icon: Icons.credit_card,
                  data: dlData,
                  primaryKeys: ['name', 'licenseNumber', 'dl_number'],
                  detailsKeys: ['status', 'validity', 'phone_number'],
                  color: Colors.blue,
                ),

                SizedBox(height: 12 * s),

                _buildInfoCard(
                  title: 'Vehicle Registration',
                  icon: Icons.directions_car,
                  data: rcData,
                  primaryKeys: ['owner_name', 'regn_number'],
                  detailsKeys: ['status', 'verification', 'maker_class', 'vehicle_class', 'engine_number', 'chassis_number', 'crime_involved'],
                  color: Colors.green,
                ),

                SizedBox(height: 12 * s),

                _buildInfoCard(
                  title: 'Driver Information',
                  icon: Icons.person,
                  data: driverData,
                  primaryKeys: ['name', 'status'],
                  detailsKeys: ['message'],
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

                // Action Buttons
                Row(children: [
                  if (dlData != null && (dlData!['licenseNumber'] ?? dlData!['dl_number']) != null)
                    Expanded(
                      child: Container(
                        height: math.max(44 * s, 48),
                        margin: EdgeInsets.only(right: 8 * s),
                        child: ElevatedButton.icon(
                          icon: _fetchingUsage
                              ? SizedBox(width: 18 * s, height: 18 * s, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                              : Icon(Icons.history, size: 18 * s),
                          label: Text(_fetchingUsage ? 'Loading...' : 'DL Usage', style: TextStyle(fontSize: 14 * s)),
                          onPressed: _fetchingUsage
                              ? null
                              : () {
                            final dlNum = (dlData!['licenseNumber'] ?? dlData!['dl_number']).toString();
                            _fetchDLUsage(dlNum);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Container(
                      height: math.max(44 * s, 48),
                      margin: EdgeInsets.only(left: 8 * s),
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

    if (data == null) {
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
            if (title == 'Driver Information' && widget.driverImage != null) ...[
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
