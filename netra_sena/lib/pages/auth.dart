// lib/pages/auth.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Make the native status bar transparent so our top container shows through.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  runApp(const AuthPage());
}

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Surveillance Portal Login',
      debugShowCheckedModeBanner: false,
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

  bool parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Please enter username and password';
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter username and password')));
      return;
    }

    try {
      print('auth.dart -> attempting login for: $email');
      // MODIFIED: Use named parameters (username: email) for the new service
      final result = await api.login(username: email, password: password);
      print('auth.dart -> login result: $result');

      // MODIFIED: Check for 'success' key and extract 'user' data
      if (result['success'] == true) {
        final data = result['user'] ?? {};
        final prefs = await SharedPreferences.getInstance();

        final String name = data['username'] ?? data['name'] ?? '';
        final String userId = data['userId']?.toString() ?? data['id']?.toString() ?? data['_id']?.toString() ?? '';
        final String userEmail = data['email'] ?? email;
        final String role = data['role'] ?? '';

        final String loginTimeIso = DateTime.now().toIso8601String();

        // Save session data to SharedPreferences for HomePage to use
        if (userId.isNotEmpty) await prefs.setString('user_id', userId);
        if (name.isNotEmpty) await prefs.setString('user_name', name);
        if (userEmail.isNotEmpty) await prefs.setString('user_email', userEmail);
        if (role.isNotEmpty) await prefs.setString('user_role', role);
        await prefs.setBool('user_is_active', parseBool(data['isActive']));
        await prefs.setString('user_login_time', loginTimeIso);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(
              userName: name.isNotEmpty ? name : 'Operator',
              userEmail: userEmail,
              role: role,
              isActive: parseBool(data['isActive']),
              loginTime: DateTime.parse(loginTimeIso),
            ),
          ),
        );
      } else {
        // Handle explicit success: false response
        final msg = result['message'] ?? result['error'] ?? 'Login failed';
        setState(() {
          _error = msg;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $msg')));
        }
      }
    } on ApiException catch (e) { // Catch the specific exception from the new api_service
      print('auth.dart -> API exception in _signIn: $e');
      final msg = e.message;
      setState(() {
        _error = msg;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $msg')));
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

  Widget _buildLoginCard(BuildContext context, double parentWidth) {
    final double horizontalPadding = (parentWidth > 420) ? 34 : 20;
    const double verticalPadding = 28;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 280),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'User Login',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                const SizedBox(height: 24),
                const Align(
                    alignment: Alignment.centerLeft,
                    // UPDATED LABEL from Email to Username
                    child: Text('Username', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  // Removed explicit keyboardType: TextInputType.emailAddress
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'Enter your username', // UPDATED HINT
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
                  ),
                ),
                const SizedBox(height: 18),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'Shhhh...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
    // NOTE: we set SafeArea(top: false) because we are explicitly drawing a
    // top bar of exact status-bar height so we don't want SafeArea to add extra top padding.
    return Scaffold(
      backgroundColor: Colors.indigo[50],
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double height = constraints.maxHeight;
            final double width = constraints.maxWidth;
            // height reserved for content spacing
            final double topSpacing = (height * 0.14).clamp(24.0, 220.0);
            final double bottomSpacing = (height * 0.08).clamp(20.0, 140.0);

            // exact status bar height
            final double statusBarHeight = MediaQuery.of(context).padding.top;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // This top bar has the same color as the scaffold background
                  // and sits *under* the native status bar because we made it transparent.
                  // This creates the illusion that the status bar is Colors.indigo[50].
                  Container(height: statusBarHeight, width: double.infinity, color: Colors.white),

                  // HEADER: full width, NO outer margin
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        Image.asset('assets/logo.png', height: 50, errorBuilder: (c, o, s) => const SizedBox()),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              //Text('Government of India', style: TextStyle(fontSize: 12, color: Colors.black54)),
                              Text('Face Surveillance Portal', // UPDATED TITLE
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Remaining content (keeps internal padding)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      children: [
                        SizedBox(height: topSpacing),
                        _buildLoginCard(context, width),
                        SizedBox(height: bottomSpacing),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}