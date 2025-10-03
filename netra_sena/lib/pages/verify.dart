// lib/pages/verification.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

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
/// Note: we DO NOT require caller to provide a base URL — ApiService has backendBaseUrl.
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
      const SnackBar(
          content: Text('Please provide DL, RC, or Driver image to verify.')),
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
            padding: EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
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
    final result = await api.verifyDriver(
      dlNumber:
      dlNumber != null && dlNumber.trim().isNotEmpty ? dlNumber.trim() : null,
      rcNumber:
      rcNumber != null && rcNumber.trim().isNotEmpty ? rcNumber.trim() : null,
      location: location,
      tollgate: tollgate,
      driverImage: driverImage,
    );

    if (result['ok'] == true) {
      final d = result['data'];
      if (d is Map) {
        bodyMap = Map<String, dynamic>.from(d);
      } else {
        bodyMap = {'raw': d};
      }
    } else {
      // server returned ok=false
      errorMessage = result['message'] ??
          (result['body'] != null
              ? const JsonEncoder.withIndent(' ')
              .convert(result['body'])
              : 'Verification failed');
    }
  } catch (e) {
    errorMessage = 'An error occurred during verification: $e';
  } finally {
    // Dismiss loading
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  if (errorMessage != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errorMessage)));
    return;
  }

  // Ensure bodyMap is non-empty; if empty, create a minimal body so dashboard shows something useful
  if (bodyMap.isEmpty) {
    bodyMap = {
      'dlData': dlNumber != null && dlNumber.trim().isNotEmpty
          ? {'licenseNumber': dlNumber.trim(), 'status': 'N/A'}
          : null,
      'rcData': rcNumber != null && rcNumber.trim().isNotEmpty
          ? {'regn_number': rcNumber.trim(), 'status': 'N/A'}
          : null,
      'driverData':
      driverImage != null ? {'status': 'N/A', 'provided': true} : null,
      'suspicious': false,
      'note': 'Empty server body — showing local preview.',
    };
  }

  // Navigate to the new dashboard page
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => VerificationDashboard(api: api, body: bodyMap),
    ),
  );
}

/// New widget that displays the verification result on a full-page dashboard.
class VerificationDashboard extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> body;

  const VerificationDashboard({super.key, required this.api, required this.body});

  @override
  State<VerificationDashboard> createState() => _VerificationDashboardState();
}

class _VerificationDashboardState extends State<VerificationDashboard>
    with TickerProviderStateMixin {
  bool _fetchingUsage = false;
  bool _showRawJson = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get dlData => widget.body['dlData'] is Map
      ? Map<String, dynamic>.from(widget.body['dlData'])
      : null;
  Map<String, dynamic>? get rcData => widget.body['rcData'] is Map
      ? Map<String, dynamic>.from(widget.body['rcData'])
      : null;
  Map<String, dynamic>? get driverData => widget.body['driverData'] is Map
      ? Map<String, dynamic>.from(widget.body['driverData'])
      : null;
  bool get suspiciousFlag => widget.body['suspicious'] == true;

  List<String> _suspiciousReasons() {
    final List<String> reasons = [];
    if (dlData != null) {
      final dlStatus = (dlData!['status'] ?? '').toString().toLowerCase();
      if (dlStatus == 'blacklisted') reasons.add('Driving License is BLACKLISTED');
      if (dlStatus == 'not_found') reasons.add('DL not found in DB');
    }
    if (rcData != null) {
      final rcStatus = (rcData!['status'] ?? rcData!['verification'] ?? '').toString().toLowerCase();
      if (rcStatus == 'blacklisted') reasons.add('Vehicle / RC is BLACKLISTED');
      if (rcStatus == 'not_found') reasons.add('RC / Vehicle not found in DB');
    }
    if (driverData != null) {
      final drvStatus = (driverData!['status'] ?? '').toString().toUpperCase();
      if (drvStatus == 'ALERT') reasons.add('Driver matched a SUSPECT (face recognition ALERT)');
      if (drvStatus == 'SERVICE_UNAVAILABLE') reasons.add('Face recognition service unavailable');
    }
    if (suspiciousFlag && reasons.isEmpty) reasons.add('System raised a suspicious flag (details in raw JSON)');
    return reasons;
  }

  Color get _statusColor {
    final reasons = _suspiciousReasons();
    if (suspiciousFlag || reasons.isNotEmpty) {
      return const Color(0xFFE53E3E);
    }
    final dlStatus = (dlData?['status'] ?? '').toString().toLowerCase();
    final rcStatus = (rcData?['status'] ?? rcData?['verification'] ?? '').toString().toLowerCase();
    final driverStatus = (driverData?['status'] ?? '').toString().toLowerCase();

    if (dlStatus == 'blacklisted' ||
        rcStatus == 'blacklisted' ||
        driverStatus == 'alert') {
      return const Color(0xFFE53E3E);
    }
    if (dlStatus == 'not_found' ||
        rcStatus == 'not_found' ||
        driverStatus == 'service_unavailable' ||
        dlData == null ||
        rcData == null) {
      return const Color(0xFFFF8C00);
    }

    return const Color(0xFF38A169);
  }

  String get _statusText {
    final reasons = _suspiciousReasons();
    if (suspiciousFlag || reasons.isNotEmpty) return 'SUSPICIOUS';
    final dlStatus = (dlData?['status'] ?? '').toString().toLowerCase();
    final rcStatus = (rcData?['status'] ?? rcData?['verification'] ?? '').toString().toLowerCase();
    final driverStatus = (driverData?['status'] ?? '').toString().toLowerCase();

    if (dlStatus == 'blacklisted' ||
        rcStatus == 'blacklisted' ||
        driverStatus == 'alert') {
      return 'UNAUTHORIZED';
    }
    if (dlStatus == 'not_found' ||
        rcStatus == 'not_found' ||
        driverStatus == 'service_unavailable' ||
        dlData == null ||
        rcData == null) {
      return 'INCOMPLETE';
    }

    return 'AUTHORIZED';
  }

  IconData get _statusIcon {
    final reasons = _suspiciousReasons();
    if (suspiciousFlag || reasons.isNotEmpty) return Icons.dangerous;

    final dlStatus = (dlData?['status'] ?? '').toString().toLowerCase();
    final rcStatus = (rcData?['status'] ?? rcData?['verification'] ?? '').toString().toLowerCase();
    final driverStatus = (driverData?['status'] ?? '').toString().toLowerCase();

    if (dlStatus == 'blacklisted' ||
        rcStatus == 'blacklisted' ||
        driverStatus == 'alert') {
      return Icons.block;
    }
    if (dlStatus == 'not_found' ||
        rcStatus == 'not_found' ||
        driverStatus == 'service_unavailable' ||
        dlData == null ||
        rcData == null) {
      return Icons.warning_amber;
    }

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching usage: $e')));
    } finally {
      setState(() => _fetchingUsage = false);
    }
  }

  void _showDLUsageDialog(String dlNumber, dynamic logs) {
    final List logsList = (logs is List) ? logs : [];
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'DL Usage History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: logsList.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No Recent Usage',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'No usage logs found for this DL in the last 2 days.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
                    : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: logsList.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (c, i) {
                    final item = logsList[i] is Map
                        ? Map<String, dynamic>.from(logsList[i])
                        : {'raw': logsList[i]};
                    final ts = item['timestamp'] ?? item['time'] ?? '';
                    final vehicleNumber = item['vehicle_number'] ?? item['vehicle'] ?? 'N/A';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.directions_car,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Vehicle: $vehicleNumber',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item['dl_number'] != null) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.credit_card, 'DL Number', item['dl_number']),
                          ],
                          if (item['alert_type'] != null) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.warning, 'Alert Type', item['alert_type'],
                                color: Colors.orange.shade700),
                          ],
                          if (item['description'] != null) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.description, 'Description', item['description']),
                          ],
                          if (ts.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow(Icons.access_time, 'Time', ts),
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
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: color ?? Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color ?? Colors.grey.shade800,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text(
            'Verification Dashboard',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E40AF),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _statusColor.withOpacity(0.1),
                        _statusColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor.withOpacity(0.3), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: _statusColor.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _statusIcon,
                        color: _statusColor,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusText.toUpperCase(),
                        style: TextStyle(
                          color: _statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 28,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getStatusSubtitle(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _statusColor.withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Alert Details
                if (_suspiciousReasons().isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.red.shade700, size: 24),
                            const SizedBox(width: 12),
                            const Text(
                              'Alert Details',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._suspiciousReasons().map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 8, right: 12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  r,
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ],
                    ),
                  ),

                // Information Cards
                _buildInfoCard(
                  title: 'Driving License',
                  icon: Icons.credit_card,
                  data: dlData,
                  primaryKeys: ['name', 'licenseNumber', 'dl_number'],
                  detailsKeys: ['status', 'validity', 'phone_number'],
                  color: Colors.blue,
                ),

                const SizedBox(height: 16),

                _buildInfoCard(
                  title: 'Vehicle Registration',
                  icon: Icons.directions_car,
                  data: rcData,
                  primaryKeys: ['owner_name', 'regn_number'],
                  detailsKeys: ['status', 'verification', 'maker_class', 'vehicle_class', 'engine_number', 'chassis_number', 'crime_involved'],
                  color: Colors.green,
                ),

                const SizedBox(height: 16),

                _buildInfoCard(
                  title: 'Driver Information',
                  icon: Icons.person,
                  data: driverData,
                  primaryKeys: ['name', 'status'],
                  detailsKeys: ['message'],
                  color: Colors.purple,
                ),

                const SizedBox(height: 24),

                // JSON Toggle
                Center(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showRawJson = !_showRawJson;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showRawJson ? Icons.visibility_off : Icons.code,
                            size: 20,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _showRawJson ? 'Hide Raw JSON' : 'View Raw JSON',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_showRawJson) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade700),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(widget.body),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.green,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    if (dlData != null && (dlData!['licenseNumber'] ?? dlData!['dl_number']) != null)
                      Expanded(
                        child: Container(
                          height: 56,
                          margin: const EdgeInsets.only(right: 8),
                          child: ElevatedButton.icon(
                            icon: _fetchingUsage
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                                : const Icon(Icons.history, size: 20),
                            label: Text(_fetchingUsage ? 'Loading...' : 'DL Usage'),
                            onPressed: _fetchingUsage
                                ? null
                                : () {
                              final dlNum = (dlData!['licenseNumber'] ?? dlData!['dl_number']).toString();
                              _fetchDLUsage(dlNum);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Container(
                        height: 56,
                        margin: const EdgeInsets.only(left: 8),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close, size: 20),
                          label: const Text('Close'),
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            side: BorderSide(color: Colors.grey.shade400),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusSubtitle() {
    switch (_statusText) {
      case 'AUTHORIZED':
        return 'All verifications completed successfully';
      case 'UNAUTHORIZED':
        return 'Access denied due to security concerns';
      case 'INCOMPLETE':
        return 'Some information could not be verified';
      case 'SUSPICIOUS':
        return 'Multiple security flags detected';
      default:
        return 'Verification status unknown';
    }
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Map<String, dynamic>? data,
    required List<String> primaryKeys,
    required List<String> detailsKeys,
    required Color color,
  }) {
    if (data == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'No data available for this section',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Primary Information
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...primaryKeys.where((key) => data.containsKey(key)).map((key) {
                  final value = data[key].toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatLabel(key),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  value,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),

                // Additional Details Section
                if (detailsKeys.any((key) => data.containsKey(key)))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.expand_more,
                        color: color,
                        size: 16,
                      ),
                    ),
                    title: Text(
                      'Additional Details',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.1)),
                        ),
                        child: Column(
                          children: detailsKeys.where((key) => data.containsKey(key)).map((key) {
                            final value = data[key].toString();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      _formatLabel(key),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      value,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade800,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLabel(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}
