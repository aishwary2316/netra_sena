// lib/pages/home_ui.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import 'auth.dart' show LoginPage;

class HomePage extends StatefulWidget {
  final String userName;
  const HomePage({super.key, required this.userName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService api = ApiService();
  bool _busy = false;

  Future<void> _logout() async {
    await api.localLogout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  Future<void> _pickAndVerify() async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked == null) return;

    final file = File(picked.path);

    setState(() {
      _busy = true;
    });

    // show loading dialog
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    final res = await api.verifyDriver(
      driverImage: file,
      dlNumber: '',
      rcNumber: '',
      location: '',
      tollgate: '',
    );

    Navigator.of(context).pop(); // close loading dialog

    setState(() {
      _busy = false;
    });

    if (res['ok'] == true) {
      final data = res['data'] ?? {};
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Verify Result'),
          content: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(data))),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } else {
      final msg = res['message'] ?? 'Verification failed';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = widget.userName.isNotEmpty ? widget.userName : 'Operator';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operator Dashboard'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Welcome, $displayName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _pickAndVerify,
              child: _busy ? const CircularProgressIndicator() : const Text('Scan Driver (Camera)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final logs = await api.getLogs();
                if (logs['ok'] == true) {
                  final data = logs['data'];
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Recent Logs'),
                      content: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(data))),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(logs['message'] ?? 'Failed to fetch logs')));
                }
              },
              child: const Text('Fetch Logs'),
            ),
          ]),
        ),
      ),
    );
  }
}
