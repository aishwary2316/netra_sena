// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_service.dart';
import 'auth.dart';
import 'drawer.dart';
import 'user_management.dart';
import 'alert_logs.dart';
import 'blacklist_management.dart';
import 'settings.dart';
import 'profile.dart';

import 'home.dart';

class HomePage extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String role;
  final bool isActive;
  final DateTime loginTime;

  const HomePage({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.role,
    required this.isActive,
    required this.loginTime,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _headerBlue = Color(0xFF1E40AF);
  late bool _isActive;
  int _selectedIndex = 0;
  final ApiService _api = ApiService();


  @override
  void initState() {
    super.initState();
    _isActive = widget.isActive;
  }

  // MODIFIED: Simplified to use the new api.logout() function
  Future<void> _logout() async {
    try {
      // Call the new logout method which handles server side and local clearing
      await _api.logout();
    } catch (e) {
      print('Logout failed: $e. Proceeding with local logout to ensure user is logged out.');
      // Manual local clear fallback if api.logout() fails or throws
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_name');
      await prefs.remove('user_email');
      await prefs.remove('user_role');
      await prefs.remove('user_is_active');
      await prefs.remove('user_login_time');
      await prefs.remove('user_id');

      const secureStorage = FlutterSecureStorage();
      await secureStorage.delete(key: 'jwt');
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
          (route) => false,
    );
  }

  // The pages are now defined as a final list, and the role is passed to the relevant widgets
  late final List<Widget> _pages = [
    const HomePageContent(),
    UserManagementPage(role: widget.role),
    const AlertLogsPage(),
    BlacklistManagementPage(role: widget.role),
    const SettingsPage(),
  ];

  void _onSelect(BuildContext context, int index, String label) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label selected')));
  }

  Future<void> _showCustomMenu(BuildContext context) async {
    final media = MediaQuery.of(context);
    final double top = media.padding.top + kToolbarHeight;
    final double right = 12;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(media.size.width - 220, top, right, 0),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'settings',
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: const [
                Icon(Icons.settings, size: 20, color: Colors.black87),
                SizedBox(width: 14),
                Text('Settings', style: TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'profile',
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: const [
                Icon(Icons.person, size: 20, color: Colors.black87),
                SizedBox(width: 14),
                Text('Profile', style: TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: const [
                Icon(Icons.logout, size: 20, color: Colors.red),
                SizedBox(width: 14),
                Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    );

    if (selected != null) {
      if (selected == 'settings') {
        setState(() {
          _selectedIndex = 4;
        });
      } else if (selected == 'profile') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
      } else if (selected == 'logout') {
        _logout();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: _headerBlue,
            foregroundColor: Colors.white,
            title: const Text(
              "Netra Sena", // MODIFIED TITLE
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => _showCustomMenu(context),
              ),
            ],
            elevation: 2,
          ),
          drawer: AppDrawer(
            userName: widget.userName,
            userEmail: widget.userEmail,
            role: widget.role,
            selectedIndex: _selectedIndex,
            isActive: _isActive,
            onSelect: _onSelect,
          ),
          body: _pages[_selectedIndex],
        ),
      ),
    );
  }
}