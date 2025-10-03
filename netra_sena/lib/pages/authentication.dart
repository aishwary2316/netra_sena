// lib/pages/auth.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

void main() {
  runApp(const AuthPage());
}

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Operator Login',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final ApiService api = ApiService();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Please enter email and password';
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter email and password')));
      return;
    }

    try {
      // Call ApiService.login (ApiService has internal prints if instrumented)
      print('auth.dart -> attempting login for: $email');
      final result = await api.login(email, password);
      print('auth.dart -> login result: $result');

      if (result['ok'] == true) {
        final data = result['data'] ?? {};

        // Save non-sensitive user metadata in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (data['userId'] != null) await prefs.setString('user_id', data['userId'].toString());
        if (data['name'] != null) await prefs.setString('user_name', data['name']);
        if (data['role'] != null) await prefs.setString('user_role', data['role']);

        // If ApiService saved JWT on login, it's already stored securely.

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomePage(userName: data['name'] ?? 'Operator')),
        );
      } else {
        final msg = result['message'] ?? 'Login failed';
        setState(() {
          _error = msg;
        });

        // Provide immediate user feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $msg')));
        }
      }
    } catch (e) {
      print('auth.dart -> unexpected exception in _signIn: $e');
      setState(() {
        _error = 'Unexpected error: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildLoginCard(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 400,
        child: Card(
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Operator Login',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                const SizedBox(height: 30),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Email', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'akshaya@toll.com',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  ),
                ),
                const SizedBox(height: 20),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'operator123',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: _showPassword,
                      onChanged: (bool? value) {
                        setState(() {
                          _showPassword = value ?? false;
                        });
                      },
                    ),
                    const Text('Show Password'),
                  ],
                ),
                const SizedBox(height: 10),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: Colors.indigo[800],
                    ),
                    child: _loading
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                        : const Text(
                      'Sign In',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo[50],
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  // Replace with your asset or remove if not present
                  Image.asset('assets/india_gov.png', height: 50, errorBuilder: (c, o, s) => const SizedBox()),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Government of India', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      Text('MINISTRY OF ROAD TRANSPORT & HIGHWAYS',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            _buildLoginCard(context),
          ],
        ),
      ),
    );
  }
}

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
