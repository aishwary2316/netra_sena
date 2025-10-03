// lib/pages/user_management.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:animate_do/animate_do.dart'; // Import for animations

/// User Management page
/// - GET  /api/users           -> fetch users
/// - POST /api/users           -> add user  { name, email, password, role }
/// - DELETE /api/users/:userId -> delete user
/// - PUT /api/users/:userId    -> try to update user role (may not exist on server)
///
/// If PUT doesn't exist on server, the UI offers to delete+recreate the user with the new role.
class UserManagementPage extends StatefulWidget {
  final String role;
  const UserManagementPage({super.key, required this.role});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  static const String BASE_URL = 'https://ai-tollgate-surveillance-1.onrender.com';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];

  final TextEditingController _searchController = TextEditingController();

  // Add user form controllers
  final _addFormKey = GlobalKey<FormState>();
  final TextEditingController _addName = TextEditingController();
  final TextEditingController _addEmail = TextEditingController();
  final TextEditingController _addPassword = TextEditingController();
  String _addRole = 'enduser'; // default role

  // NEW: prevent double submissions
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addName.dispose();
    _addEmail.dispose();
    _addPassword.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final uri = Uri.parse('$BASE_URL/api/users');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        List<Map<String, dynamic>> items = [];
        if (body is List) {
          items = body.map<Map<String, dynamic>>((e) {
            if (e is Map) return Map<String, dynamic>.from(e);
            return {'entry': e};
          }).toList();
        } else if (body is Map) {
          items = [Map<String, dynamic>.from(body)];
        }
        if (mounted) {
          setState(() {
            _users = items;
            _filterUsers(_searchController.text);
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load users: ${res.statusCode}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error fetching users: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filterUsers(String query) {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _filteredUsers = List.from(_users);
        });
      }
      return;
    }

    final lowerCaseQuery = query.trim().toLowerCase();
    if (mounted) {
      setState(() {
        _filteredUsers = _users.where((u) {
          final name = (u['name'] ?? '').toString().toLowerCase();
          final email = (u['email'] ?? '').toString().toLowerCase();
          final role = (u['role'] ?? '').toString().toLowerCase();
          return name.contains(lowerCaseQuery) || email.contains(lowerCaseQuery) || role.contains(lowerCaseQuery);
        }).toList();
      });
    }
  }

  String _idOf(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map && raw.containsKey(r'$oid')) return raw[r'$oid'].toString();
    if (raw is Map && raw.containsKey('oid')) return raw['oid'].toString();
    if (raw is Map && raw.containsKey('_id')) return _idOf(raw['_id']);
    return raw.toString();
  }

  // NOTE: Now accepts dialogContext so we explicitly pop the dialog route.
  Future<void> _addUser(BuildContext dialogContext) async {
    if (_isAdding) return; // guard
    if (!_addFormKey.currentState!.validate()) return;

    setState(() => _isAdding = true);

    final payload = {
      'name': _addName.text.trim(),
      'email': _addEmail.text.trim(),
      'password': _addPassword.text.trim(),
      'role': _addRole,
    };

    final uri = Uri.parse('$BASE_URL/api/users');
    try {
      final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: json.encode(payload)).timeout(const Duration(seconds: 15));
      if (mounted) {
        if (res.statusCode == 201 || res.statusCode == 200) {
          // Important: pop the dialog using the dialog's context so we don't accidentally pop other routes.
          Navigator.of(dialogContext).pop();
          // Show snackbar using the page's context (this).
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User added')));
          _fetchUsers();
        } else {
          final body = res.body.isNotEmpty ? res.body : 'status ${res.statusCode}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $body')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _deleteUser(String userId) async {
    final uri = Uri.parse('$BASE_URL/api/users/$userId');
    try {
      final res = await http.delete(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User deleted')));
          _fetchUsers();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: ${res.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  /// Attempt to update role with PUT /api/users/:userId
  /// If server responds 404/405 or other method not allowed, fallback to asking user whether to delete+recreate.
  Future<void> _changeRole(String userId, String newRole, Map<String, dynamic> existingUser) async {
    final uri = Uri.parse('$BASE_URL/api/users/$userId');
    try {
      final res = await http.put(uri, headers: {'Content-Type': 'application/json'}, body: json.encode({'role': newRole})).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated')));
          _fetchUsers();
        }
        return;
      }
      // If update endpoint not present, server might return 404 or 405; offer fallback
      if (res.statusCode == 404 || res.statusCode == 405) {
        final doDelete = await _showConfirmDialog(
          'Your server does not support direct user updates (PUT).\n\nWould you like to delete and recreate the user with the new role? This preserves email but requires a password (you will enter a new password).',
        );
        if (doDelete == true) {
          await _deleteAndRecreate(userId, existingUser, newRole);
        }
        return;
      }

      // other non-200 codes: show message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: ${res.statusCode} ${res.body}')));
      }
    } catch (e) {
      // network or other error: fallback offer
      final doDelete = await _showConfirmDialog(
        'Could not update user directly: $e\n\nWould you like to delete and recreate the user with the new role?',
      );
      if (doDelete == true) {
        await _deleteAndRecreate(userId, existingUser, newRole);
      }
    }
  }

  Future<void> _deleteAndRecreate(String userId, Map<String, dynamic> existingUser, String newRole) async {
    // Delete
    await _deleteUserWithToast(userId);

    // Show dialog to enter new password for recreation
    final pwdCtrl = TextEditingController();
    final recreate = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Recreate user', style: TextStyle(fontWeight: FontWeight.bold)),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width * 0.8,
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Recreating user ${existingUser['email'] ?? existingUser['name'] ?? ''} with role $newRole'),
                const SizedBox(height: 16),
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.lock),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Recreate')),
          ],
        );
      },
    );

    if (recreate == true) {
      final payload = {
        'name': existingUser['name'] ?? existingUser['email'] ?? 'User',
        'email': existingUser['email'] ?? '${DateTime.now().millisecondsSinceEpoch}@local',
        'password': pwdCtrl.text.trim(),
        'role': newRole,
      };
      final uri = Uri.parse('$BASE_URL/api/users');
      try {
        final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: json.encode(payload)).timeout(const Duration(seconds: 15));
        if (res.statusCode == 201 || res.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User recreated with new role')));
            _fetchUsers();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recreate failed: ${res.statusCode} ${res.body}')));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recreate error: $e')));
        }
      }
    } else {
      // User cancelled recreate — nothing to do
      _fetchUsers();
    }
  }

  Future<void> _deleteUserWithToast(String id) async {
    try {
      final uri = Uri.parse('$BASE_URL/api/users/$id');
      final res = await http.delete(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User deleted')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: ${res.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<bool?> _showConfirmDialog(String text) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width * 0.8,
            ),
            child: Text(text)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
        ],
      ),
    );
  }

  void _showAddUserDialog() {
    _addName.clear();
    _addEmail.clear();
    _addPassword.clear();
    setState(() => _addRole = 'enduser'); // Reset state
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add User', style: TextStyle(fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(ctx).size.width * 0.8,
          ),
          child: Form(
            key: _addFormKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: _addName,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Name required' : null,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addEmail,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Email required' : null,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addPassword,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Password required' : null,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.work_outline),
                  ),
                  value: _addRole,
                  items: const [
                    DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'enduser', child: Text('End User')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _addRole = v);
                  },
                )
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          // IMPORTANT: pass the dialog's ctx to _addUser so it can pop the dialog safely.
          ElevatedButton(
            onPressed: _isAdding ? null : () => _addUser(ctx),
            child: _isAdding
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add User'),
          ),
        ],
      ),
    );
  }

  // UI: user card
  Widget _userCard(Map<String, dynamic> u) {
    final idRaw = u['_id'] ?? u['userId'] ?? u['id'];
    final id = _idOf(idRaw);
    final name = (u['name'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final role = (u['role'] ?? 'enduser').toString();
    final isActive = u['isActive'] == true;
    final roleIcon = _getRoleIcon(role);

    return FadeInUp(
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {}, // Could show user details
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getRoleColor(role),
                  child: Icon(roleIcon, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : email,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(email, style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      Wrap( // Using Wrap to prevent overflow on small screens
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildRoleBadge(role),
                          _buildStatusBadge(isActive),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.role == 'superadmin')
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.black54),
                    onSelected: (v) async {
                      if (v == 'delete') {
                        final confirm = await _showConfirmDialog('Delete user $email ?');
                        if (confirm == true) {
                          await _deleteUser(id);
                        }
                      } else if (v == 'change_role') {
                        final newRole = await showDialog<String>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: const Text('Select Role'),
                            children: [
                              SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('superadmin'), child: const Text('Super Admin')),
                              SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('admin'), child: const Text('Admin')),
                              SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('enduser'), child: const Text('End User')),
                            ],
                          ),
                        );
                        if (newRole != null && newRole != role) {
                          await _changeRole(id, newRole, u);
                        }
                      } else if (v == 'view_raw') {
                        _showRawJson(u);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'change_role', child: Text('Change Role')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'superadmin':
        return Icons.verified_user_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'enduser':
      default:
        return Icons.person_rounded;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'superadmin':
        return Colors.blue.shade800;
      case 'admin':
        return Colors.indigo.shade600;
      case 'enduser':
      default:
        return Colors.grey.shade400;
    }
  }

  Widget _buildRoleBadge(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getRoleColor(role).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _getRoleColor(role)),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _getRoleColor(role),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? Colors.green.shade700 : Colors.black54),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.green.shade700 : Colors.black54,
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic t) {
    if (t == null) return '';
    try {
      if (t is int) {
        DateTime dt = (t.toString().length > 10) ? DateTime.fromMillisecondsSinceEpoch(t) : DateTime.fromMillisecondsSinceEpoch(t * 1000);
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

  void _showRawJson(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raw JSON'),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.8,
          child: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(item))),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != 'superadmin') {
      return const Center(
        child: Text('Access Denied', style: TextStyle(fontSize: 24, color: Colors.red)),
      );
    }

    const Color primaryBlue = Color(0xFF1E3A8A);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: primaryBlue))
            : _error != null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _fetchUsers,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        )
            : RefreshIndicator(
          onRefresh: _fetchUsers,
          color: primaryBlue,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search users...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filterUsers('');
                            },
                          )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onChanged: _filterUsers,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _showAddUserDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _filteredUsers.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.group_off, size: 80, color: Colors.black26),
                      SizedBox(height: 16),
                      Text('No users found', style: TextStyle(fontSize: 18, color: Colors.black54)),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    return _userCard(_filteredUsers[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}