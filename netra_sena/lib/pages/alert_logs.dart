// lib/pages/alert_logs.dart (MODIFIED)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'error.dart'; // Retained for error handling

// MODIFIED: Removed _ActiveFilter.multipleDL
enum _Severity { red, orange, none }
enum _ActiveFilter { all, suspicious, systemAlerts }

class AlertLogsPage extends StatefulWidget {
  const AlertLogsPage({super.key});

  @override
  State<AlertLogsPage> createState() => _AlertLogsPageState();
}

class _AlertLogsPageState extends State<AlertLogsPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  _ActiveFilter _activeFilter = _ActiveFilter.all;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Color palette remains unchanged
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _lightGray = Color(0xFFF8FAFC);
  static const Color _textGray = Color(0xFF64748B);
  static const Color _accentColor = Color(0xFF3B82F6);
  static const Color _suspiciousRed = Color(0xFFDC2626);
  static const Color _warningOrange = Color(0xFFD97706);
  static const Color _successGreen = Color(0xFF059669);
  static const Color _cardShadow = Color(0x0D000000);
  static const Color _yellowAlert = Color(0xFFF5E063);


  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _fetchLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// MODIFIED: Uses _api.getFaceAlerts() which returns List<dynamic> on success or throws ApiException.
  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final logsList = await _api.getFaceAlerts(); // New API call

      // Normalize List<dynamic> result into List<Map<String, dynamic>>
      final normalized = logsList.map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();

      setState(() {
        _logs = normalized;
      });
      _animationController.forward();
    } on ApiException catch (e) {
      // Handle API exception from the new service
      setState(() {
        _error = 'API Error fetching alerts: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _error = 'Error fetching alerts: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _normalizeDataToList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map && data['logs'] is List) {
      return (data['logs'] as List).map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map) {
      return [Map<String, dynamic>.from(data)];
    } else {
      return [
        {'data': data}
      ];
    }
  }

  // Removed _buildImageWidget helper

  String _formatTimestamp(dynamic t) {
    if (t == null) return '';
    try {
      if (t is int) {
        DateTime dt = (t.toString().length > 10)
            ? DateTime.fromMillisecondsSinceEpoch(t)
            : DateTime.fromMillisecondsSinceEpoch(t * 1000);
        return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
      } else if (t is String) {
        final parsed = DateTime.tryParse(t);
        if (parsed != null) {
          return '${parsed.year}-${_two(parsed.month)}-${_two(parsed.day)} ${_two(parsed.hour)}:${_two(parsed.minute)}';
        } else {
          return t;
        }
      } else if (t is DateTime) {
        final dt = t;
        return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
      }
    } catch (_) {}
    return t.toString();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  /// MODIFIED: Removed checks for DL/RC multiple usage.
  _Severity _cardSeverity(Map<String, dynamic> item) {
    final alertType = (item['alert_type'] ?? '').toString().toLowerCase();
    final scannedBy = (item['scanned_by'] ?? '').toString().toLowerCase();
    final driverStatus = (item['driver_status'] ?? item['driverStatus'] ?? '').toString().toLowerCase();

    // Explicit suspicious/suspect
    if (alertType.contains('suspicious') || alertType.contains('suspect')) {
      return _Severity.red;
    }

    // driver status explicit alert
    if (driverStatus == 'alert' || driverStatus == 'blacklisted') {
      return _Severity.red;
    }

    // suspicious boolean from server
    final suspiciousFlag = item['suspicious'];
    if (suspiciousFlag == true) {
      return _Severity.red;
    }

    // scanned_by System Alert -> ORANGE
    if (scannedBy == 'system alert' || scannedBy == 'system_alert' || scannedBy == 'systemalert') {
      return _Severity.orange;
    }

    return _Severity.none;
  }

  /// MODIFIED: Search and filter logic only uses generic and face fields.
  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    bySearch(Map<String, dynamic> item) {
      if (q.isEmpty) return true;
      // Removed DL and RC search fields
      final reason = (item['description'] ?? item['reason'] ?? item['crime_involved'] ?? '').toString().toLowerCase();
      final location = (item['location'] ?? '').toString().toLowerCase();
      final scannedBy = (item['scanned_by'] ?? '').toString().toLowerCase();
      final driverName = (item['driver_name'] ?? item['driver'] ?? item['name'] ?? item['person_name'] ?? '').toString().toLowerCase();
      return reason.contains(q) || location.contains(q) || scannedBy.contains(q) || driverName.contains(q);
    }

    final list = _logs.where((item) => bySearch(item)).toList();

    if (_activeFilter == _ActiveFilter.all) return list;
    if (_activeFilter == _ActiveFilter.suspicious) return list.where((i) => _cardSeverity(i) == _Severity.red).toList();
    if (_activeFilter == _ActiveFilter.systemAlerts) return list.where((i) => _cardSeverity(i) == _Severity.orange && _isSystemAlert(i)).toList();

    return list;
  }

  bool _isSystemAlert(Map<String, dynamic> item) {
    final scannedBy = (item['scanned_by'] ?? '').toString().toLowerCase();
    return scannedBy == 'system alert' || scannedBy == 'system_alert' || scannedBy == 'systemalert';
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showRawJson(BuildContext context, Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Alert JSON'),
        content: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            minWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(item),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              final jsonStr = const JsonEncoder.withIndent('  ').convert(item);
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('JSON copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  Color _reasonColor(_Severity sev) {
    if (sev == _Severity.red) return _suspiciousRed;
    if (sev == _Severity.orange) return _warningOrange;
    return _textGray;
  }

  Widget _buildSearchAndStats() {
    final total = _logs.length;
    final suspiciousCount = _logs.where((i) => _cardSeverity(i) == _Severity.red).length;

    return Container(
      color: _lightGray,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search Driver / Reason / Location...',
                    hintStyle: TextStyle(
                      color: _textGray,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(Icons.search_rounded, color: _textGray),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: _textGray),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        })
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _accentColor, width: 2),
                    ),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                  textInputAction: TextInputAction.search,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _buildStatChip('Total', total, _accentColor),
                      const SizedBox(width: 8),
                      _buildStatChip('Suspicious', suspiciousCount, _suspiciousRed),
                    ],
                  ),
                  InkWell(
                    onTap: () => _showFilterOptions(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _primaryBlue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, color: _primaryBlue, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Filter',
                            style: TextStyle(
                              color: _primaryBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filter Records',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _primaryBlue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _buildFilterOption('All Alerts', _ActiveFilter.all, Icons.format_list_bulleted_rounded),
              _buildFilterOption('Suspicious (Red)', _ActiveFilter.suspicious, Icons.warning_amber_rounded),
              _buildFilterOption('System Alerts (Orange)', _ActiveFilter.systemAlerts, Icons.notifications_rounded),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterOption(String label, _ActiveFilter value, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: _activeFilter == value ? _accentColor : _textGray),
      title: Text(
        label,
        style: TextStyle(
          color: _activeFilter == value ? _primaryBlue : _textGray,
          fontWeight: _activeFilter == value ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: _activeFilter == value ? Icon(Icons.check, color: _successGreen) : null,
      onTap: () {
        setState(() {
          _activeFilter = value;
        });
        Navigator.pop(context);
      },
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: $count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildLogCard(Map<String, dynamic> item) {
    final ts = item['timestamp'] ?? item['time'] ?? item['created_at'] ?? item['date'] ?? '';
    final driverName = (item['driver_name'] ?? item['driver'] ?? item['name'] ?? item['person_name'] ?? '').toString();
    final reason = (item['description'] ?? item['reason'] ?? item['crime_involved'] ?? '').toString();

    final sev = _cardSeverity(item);
    Color cardColor;
    if (sev == _Severity.red) {
      cardColor = _suspiciousRed;
    } else if (sev == _Severity.orange) {
      cardColor = _warningOrange;
    } else {
      cardColor = Colors.white;
    }

    final reasonColor = _reasonColor(sev);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cardColor,
          width: 2,
        ),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      reason.isNotEmpty ? reason : 'No reason provided',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: reasonColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    // MODIFIED: Added Driver Name prominently
                    Text(
                      'Driver: ${driverName.isNotEmpty ? driverName : 'N/A'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(ts),
                      style: TextStyle(
                        fontSize: 12,
                        color: _textGray,
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(
                width: 24,
                thickness: 1,
                indent: 8,
                endIndent: 8,
                color: _lightGray,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.code_rounded, color: _primaryBlue),
                    tooltip: 'View Raw JSON',
                    onPressed: () => _showRawJson(context, item),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _lightGray,
                borderRadius: BorderRadius.circular(60),
                border: Border.all(color: _textGray.withOpacity(0.2)),
              ),
              child: Icon(
                Icons.history_rounded,
                size: 60,
                color: _textGray,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _search.isNotEmpty || _activeFilter != _ActiveFilter.all
                  ? 'No matching alerts found'
                  : 'No alerts available',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _primaryBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _search.isNotEmpty || _activeFilter != _ActiveFilter.all
                  ? 'Try adjusting your search or filter criteria'
                  : 'Pull down to refresh and check for new alerts',
              style: TextStyle(
                fontSize: 14,
                color: _textGray,
              ),
              textAlign: TextAlign.center,
            ),
            if (_search.isNotEmpty || _activeFilter != _ActiveFilter.all) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _search = '';
                    _activeFilter = _ActiveFilter.all;
                  });
                },
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear Filters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ADDED: Implementation for the missing error state widget
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _suspiciousRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(60),
                border: Border.all(color: _suspiciousRed.withOpacity(0.2)),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 60,
                color: _suspiciousRed,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _suspiciousRed,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _suspiciousRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _suspiciousRed.withOpacity(0.2)),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 14,
                  color: _suspiciousRed,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchLogs,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ADDED: Implementation for the missing loading state widget
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accentColor.withOpacity(0.1), _primaryBlue.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Loading alerts...',
            style: TextStyle(
              fontSize: 16,
              color: _textGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: _lightGray,
      body: Column(
        children: [
          _buildSearchAndStats(),
          Expanded(
            child: _loading
                ? _buildLoadingState()
                : _error != null
                ? _buildErrorState()
                : RefreshIndicator(
              onRefresh: _fetchLogs,
              color: _accentColor,
              backgroundColor: Colors.white,
              child: list.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                      height: MediaQuery.of(context).size.height * 0.3),
                  _buildEmptyState(),
                ],
              )
                  : FadeTransition(
                opacity: _fadeAnimation,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    return _buildLogCard(item);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}