// lib/pages/vehicle_logs.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class VehicleLogsPage extends StatefulWidget {
  const VehicleLogsPage({super.key});

  @override
  State<VehicleLogsPage> createState() => _VehicleLogsPageState();
}

class _VehicleLogsPageState extends State<VehicleLogsPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  // UI state
  String _searchQuery = '';
  String _filter = 'all';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Enhanced theme colors with gradient support
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _headerBlue = Color(0xFF1E40AF);
  static const Color _lightGray = Color(0xFFF8FAFC);
  static const Color _textGray = Color(0xFF64748B);
  static const Color _accentColor = Color(0xFF3B82F6);
  static const Color _suspiciousRed = Color(0xFFDC2626);
  static const Color _suspiciousRedBackground = Color(0xFFFEF2F2);
  static const Color _successGreen = Color(0xFF059669);
  static const Color _warningOrange = Color(0xFFD97706);
  static const Color _cardShadow = Color(0x0D000000);

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
    _searchFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.getLogs();
      if (res['ok'] == true || res['data'] != null) {
        final data = res['data'] ?? res;
        final normalized = _normalizeDataToList(data);
        setState(() {
          _logs = normalized;
        });
        _animationController.forward();
      } else {
        setState(() {
          _error = res['message'] ?? 'Failed to fetch logs';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error fetching logs: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _normalizeDataToList(dynamic data) {
    List<Map<String, dynamic>> logsList = [];
    if (data is List) {
      logsList = data.map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map && data['logs'] is List) {
      logsList = (data['logs'] as List).map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map) {
      logsList = [Map<String, dynamic>.from(data)];
    } else {
      logsList = [{'data': data}];
    }
    return logsList;
  }

  Widget _buildImageWidget(dynamic img, double size, {VoidCallback? onTap}) {
    if (img == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_accentColor.withOpacity(0.1), _primaryBlue.withOpacity(0.1)],
          ),
          border: Border.all(color: _accentColor.withOpacity(0.2)),
        ),
        child: Icon(
          Icons.directions_car_rounded,
          size: size * 0.4,
          color: _accentColor,
        ),
      );
    }

    try {
      final s = img.toString();
      Widget imageWidget;

      if (s.startsWith('http') || s.startsWith('https')) {
        imageWidget = Image.network(
          s,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildImageWidget(null, size),
        );
      } else if (s.startsWith('data:')) {
        final base64Str = s.split(',').last;
        final bytes = base64Decode(base64Str);
        imageWidget = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } else if (s.length > 100 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s)) {
        final bytes = base64Decode(s.replaceAll('\n', ''));
        imageWidget = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } else {
        final label = img.toString();
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [_accentColor, _primaryBlue],
            ),
          ),
          child: Center(
            child: Text(
              label.isNotEmpty ? label[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.3,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }

      return GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _cardShadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageWidget,
          ),
        ),
      );
    } catch (e) {
      return _buildImageWidget(null, size, onTap: onTap);
    }
  }

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
    } catch (e) {
      // ignore
    }
    return t.toString();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  List<Map<String, dynamic>> get _filteredLogs {
    final q = _searchQuery.trim().toLowerCase();
    return _logs.where((item) {
      final vehicleNumber = (item['vehicle_number'] ??
          item['veh_no'] ??
          item['vehicleNo'] ??
          item['vehicle'] ??
          item['vehicle_no'] ??
          '')
          .toString()
          .toLowerCase();
      final driverName =
      (item['driver_name'] ?? item['driver'] ?? item['name'] ?? '')
          .toString()
          .toLowerCase();
      final dlNumber = (item['dl_number'] ?? item['dl'] ?? '')
          .toString()
          .toLowerCase();
      final rcNumber = (item['rc_number'] ?? item['rc'] ?? '')
          .toString()
          .toLowerCase();
      final status = (item['status'] ??
          item['result'] ??
          item['verification'] ??
          '')
          .toString()
          .toLowerCase();

      final matchesQuery = q.isEmpty ||
          vehicleNumber.contains(q) ||
          driverName.contains(q) ||
          dlNumber.contains(q) ||
          rcNumber.contains(q) ||
          status.contains(q);

      if (!matchesQuery) return false;

      if (_filter == 'all') return true;
      if (_filter == 'suspicious') {
        if (item['suspicious'] == true) return true;
        if (item['alert_type'] != null) return true;
        if (status.contains('blacklist') ||
            status.contains('blacklisted') ||
            status.contains('suspicious') ||
            status.contains('alert')) return true;
        return false;
      }
      if (_filter == 'blacklisted') {
        if ((item['dl_status'] ?? item['rc_status'] ?? item['status'] ?? '')
            .toString()
            .toLowerCase()
            .contains('blacklist')) return true;
        if ((item['verification'] ?? '')
            .toString()
            .toLowerCase()
            .contains('blacklist')) return true;
        return false;
      }
      if (_filter == 'verified') {
        final s = (item['status'] ??
            item['result'] ??
            item['verification'] ??
            item['dl_status'] ??
            '')
            .toString()
            .toLowerCase();
        return s.contains('ok') ||
            s.contains('verified') ||
            s.contains('valid') ||
            s.contains('success');
      }
      return true;
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> logs) {
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (var item in logs) {
      final tsRaw = item['timestamp'] ??
          item['time'] ??
          item['created_at'] ??
          item['date'] ??
          '';
      DateTime? dt;
      if (tsRaw is int) {
        dt = (tsRaw.toString().length > 10)
            ? DateTime.fromMillisecondsSinceEpoch(tsRaw)
            : DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000);
      } else if (tsRaw is String) {
        dt = DateTime.tryParse(tsRaw);
      } else if (tsRaw is DateTime) {
        dt = tsRaw;
      }
      final key = dt != null
          ? '${dt.year}-${_two(dt.month)}-${_two(dt.day)}'
          : 'Unknown';
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  Color _statusColor(String s) {
    final st = s.toLowerCase();
    if (st.contains('black')) return _suspiciousRed;
    if (st.contains('susp') ||
        st.contains('alert') ||
        st.contains('suspect')) return _suspiciousRed;
    if (st.contains('ok') ||
        st.contains('verified') ||
        st.contains('valid') ||
        st.contains('success')) return _successGreen;
    return _warningOrange;
  }

  Future<void> _showImageFullscreen(dynamic img) async {
    if (img == null) return;
    Widget content;
    try {
      final s = img.toString();
      if (s.startsWith('http') || s.startsWith('https')) {
        content = InteractiveViewer(
            child: Image.network(s, fit: BoxFit.contain));
      } else if (s.startsWith('data:')) {
        final base64Str = s.split(',').last;
        final bytes = base64Decode(base64Str);
        content = InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain));
      } else if (s.length > 100 &&
          RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s)) {
        final bytes = base64Decode(s.replaceAll('\n', ''));
        content = InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain));
      } else {
        content = Center(child: Text(s));
      }
    } catch (e) {
      content = Center(child: Text('Unable to preview image: $e'));
    }

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            maxWidth: MediaQuery.of(context).size.width * 0.95,
          ),
          child: Column(
            children: [
              Expanded(child: content),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  void _showRawJson(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log JSON'),
        content: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            minWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(item),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              final jsonStr = const JsonEncoder.withIndent('  ').convert(item);
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('JSON copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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

  // --- REDESIGNED UI METHODS ---
  Widget _buildSearchHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
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
            focusNode: _searchFocus,
            decoration: InputDecoration(
              hintText: 'Search vehicle, driver, DL, RC...',
              hintStyle: TextStyle(
                color: _textGray,
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: _textGray,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: Icon(
                  Icons.clear_rounded,
                  color: _textGray,
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
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
            onChanged: (v) => setState(() => _searchQuery = v),
            textInputAction: TextInputAction.search,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsAndFilter() {
    final total = _logs.length;
    final suspiciousCount = _logs.where((i) {
      if (i['suspicious'] == true) return true;
      if (i['alert_type'] != null) return true;
      final s = ((i['status'] ?? i['result'] ?? i['verification']) ?? '')
          .toString()
          .toLowerCase();
      return s.contains('blacklist') || s.contains('susp');
    }).length;

    return Padding(
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
              _buildFilterOption('All Records', 'all', Icons.format_list_bulleted_rounded),
              _buildFilterOption('Suspicious', 'suspicious', Icons.warning_amber_rounded),
              _buildFilterOption('Blacklisted', 'blacklisted', Icons.block_rounded),
              _buildFilterOption('Verified', 'verified', Icons.verified_rounded),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterOption(String label, String value, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: _filter == value ? _accentColor : _textGray),
      title: Text(
        label,
        style: TextStyle(
          color: _filter == value ? _primaryBlue : _textGray,
          fontWeight: _filter == value ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: _filter == value ? Icon(Icons.check, color: _successGreen) : null,
      onTap: () {
        setState(() {
          _filter = value;
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

  Widget _buildDateHeader(String dateKey) {
    final now = DateTime.now();
    final todayKey = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year}-${_two(yesterday.month)}-${_two(yesterday.day)}';

    String label;
    IconData icon;
    if (dateKey == todayKey) {
      label = 'Today';
      icon = Icons.today_rounded;
    } else if (dateKey == yesterdayKey) {
      label = 'Yesterday';
      icon = Icons.calendar_today_outlined;
    } else {
      label = dateKey;
      icon = Icons.calendar_today_rounded;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accentColor.withOpacity(0.1), _primaryBlue.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _accentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> item) {
    final vehicleNumber = item['vehicle_number'] ??
        item['veh_no'] ??
        item['vehicleNo'] ??
        item['vehicle'] ??
        item['vehicle_no'] ??
        '';
    final dlNumber = item['dl_number'] ?? item['dl'] ?? '';
    final rcNumber = item['rc_number'] ?? item['rc'] ?? '';
    final status = item['status'] ??
        item['result'] ??
        item['verification'] ??
        item['dl_status'] ??
        '';
    final ts = item['timestamp'] ??
        item['time'] ??
        item['created_at'] ??
        item['date'] ??
        '';

    Color cardColor;
    if (status.toString().toLowerCase().contains('blacklist')) {
      cardColor = _suspiciousRed;
    } else if (status.toString().toLowerCase().contains('susp')) {
      cardColor = _warningOrange;
    } else if (status.toString().toLowerCase().contains('valid')) {
      cardColor = _successGreen;
    } else {
      cardColor = Colors.white;
    }

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
                      vehicleNumber.toString().isNotEmpty
                          ? vehicleNumber.toString()
                          : 'Unknown Vehicle',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _primaryBlue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatTimestamp(ts)}',
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
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dlNumber.toString().isNotEmpty ? 'DL: ${dlNumber.toString()}' : 'No DL',
                    style: TextStyle(
                      fontSize: 12,
                      color: _textGray,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rcNumber.toString().isNotEmpty ? 'RC: ${rcNumber.toString()}' : 'No RC',
                    style: TextStyle(
                      fontSize: 12,
                      color: _textGray,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A complete mess, but I have fixed it and moved it to the correct spot.
  Widget _buildInfoRow(String label, String value, IconData icon) {
    return InkWell(
      onTap: () => _copyToClipboard(label, value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _accentColor, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _textGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: _primaryBlue.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.copy_rounded, color: _textGray.withOpacity(0.5), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentRow(String label, String value, IconData icon) {
    return InkWell(
      onTap: () => _copyToClipboard(label, value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: _textGray, size: 16),
            const SizedBox(width: 8),
            Text(
              '$label: ',
              style: TextStyle(
                  color: _textGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                    color: _primaryBlue.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_rounded, color: _textGray.withOpacity(0.5), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: _primaryBlue),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: _primaryBlue,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
              _searchQuery.isNotEmpty || _filter != 'all'
                  ? 'No matching records found'
                  : 'No logs available',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _primaryBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _filter != 'all'
                  ? 'Try adjusting your search or filter criteria'
                  : 'Pull down to refresh and check for new logs',
              style: TextStyle(
                fontSize: 14,
                color: _textGray,
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isNotEmpty || _filter != 'all') ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _filter = 'all';
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
                color: _suspiciousRedBackground,
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
                color: _suspiciousRedBackground,
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
            'Loading vehicle logs...',
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
    final groupedLogs = _groupByDate(_filteredLogs);
    final sortedDates = groupedLogs.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: _lightGray,
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(
            child: _loading
                ? _buildLoadingState()
                : _error != null
                ? _buildErrorState()
                : RefreshIndicator(
              onRefresh: _fetchLogs,
              color: _accentColor,
              backgroundColor: Colors.white,
              child: _logs.isEmpty
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
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                        child: _buildStatsAndFilter()),
                    if (_filteredLogs.isEmpty)
                      SliverToBoxAdapter(
                          child: _buildEmptyState())
                    else
                      ...groupedLogs.entries.map((entry) {
                        final dateKey = entry.key;
                        final logsForDate = entry.value;
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              if (index == 0) {
                                return Column(
                                  children: [
                                    _buildDateHeader(dateKey),
                                    _buildLogCard(logsForDate[index]),
                                  ],
                                );
                              }
                              return _buildLogCard(logsForDate[index]);
                            },
                            childCount: logsForDate.length,
                          ),
                        );
                      }).toList(),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 32)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}