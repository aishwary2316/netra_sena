// lib/pages/user_management.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../services/api_service.dart';

/// User Management page
/// - GET: uses api.getUsers()
/// - POST: uses api.createUser(username, password, role)
/// - DELETE: uses api.deleteUserById(id)
class UserManagementPage extends StatefulWidget {
  final String role;
  const UserManagementPage({super.key, required this.role});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final ApiService _api = ApiService(debug: true);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];

  final TextEditingController _searchController = TextEditingController();

  // Prevent double submissions at page-level
  bool _isAdding = false;

  // New: whether to show deleted users (soft-deleted). Default: hide deleted users.
  bool _showDeleted = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => _filterUsers(_searchController.text));
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------
  // API Fetching: Uses api.getUsers()
  // ---------------------------
  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await _api.getUsers();

      final body = resp['users'] ?? resp['data'] ?? resp;
      List<Map<String, dynamic>> items = [];

      if (body is List) {
        items = body.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else if (body is Map) {
        items = [Map<String, dynamic>.from(body)];
      }

      if (mounted) {
        if (items.isNotEmpty || (resp['success'] == true && (resp['users'] ?? []).isEmpty)) {
          setState(() {
            _users = items;
            _filterUsers(_searchController.text); // apply current showDeleted & search
          });
        } else {
          setState(() {
            _users = [];
            _filteredUsers = [];
            _error = resp['message'] ?? 'Failed to load users: Invalid response format or empty list.';
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = 'API Error fetching users: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network Error fetching users: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filterUsers(String query) {
    final trimmed = query.trim();
    final lowerCaseQuery = trimmed.toLowerCase();

    List<Map<String, dynamic>> candidates = List.from(_users);

    // Filter by active/deleted according to _showDeleted flag
    if (!_showDeleted) {
      candidates = candidates.where((u) => _isUserActive(u)).toList();
    }

    if (lowerCaseQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredUsers = candidates;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _filteredUsers = candidates.where((u) {
          final username = (u['username'] ?? u['name'] ?? u['email'] ?? '').toString().toLowerCase();
          final role = (u['role'] ?? '').toString().toLowerCase();
          return username.contains(lowerCaseQuery) || role.contains(lowerCaseQuery);
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

  bool _isUserActive(Map<String, dynamic> u) {
    // Prefer 'active' boolean (server uses this)
    if (u.containsKey('active')) return u['active'] == true;

    if (u.containsKey('isActive')) return u['isActive'] == true;
    if (u.containsKey('is_active')) return u['is_active'] == true;
    if (u.containsKey('status')) {
      final s = u['status']?.toString().toLowerCase();
      return s == 'active' || s == 'enabled' || s == 'true';
    }
    // Default: assume active if not specified
    return true;
  }

  // ---------------------------
  // Create user with timeout
  // ---------------------------
  Future<bool> _createUserWithTimeout({
    required String username,
    required String password,
    required String role,
    Duration timeout = const Duration(seconds: 20)
  }) async {
    if (_isAdding) return false;

    setState(() => _isAdding = true);

    try {
      final resp = await _api
          .createUser(username: username, password: password, role: role)
          .timeout(timeout, onTimeout: () => throw TimeoutException('Request timed out'));

      if (resp['success'] == true) {
        if (mounted) _fetchUsers();
        return true;
      }
      return false;
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  // ---------------------------
  // API Deleting User: Uses api.deleteUserById()
  // Returns true if deleted, false otherwise
  // ---------------------------
  Future<bool> _deleteUser(String userId) async {
    if (userId.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid user id.'), backgroundColor: Colors.red),
        );
      }
      return false;
    }

    try {
      final resp = await _api
          .deleteUserById(userId)
          .timeout(const Duration(seconds: 25), onTimeout: () => throw TimeoutException('Request timed out'));

      if (resp is Map && resp['success'] == true) {
        // Optimistically update local list: mark user as inactive if possible
        if (mounted) {
          setState(() {
            for (var u in _users) {
              final idRaw = u['_id'] ?? u['userId'] ?? u['id'];
              if (_idOf(idRaw) == userId) {
                // set the server-side soft-delete flag locally to reflect deletion instantly
                u['active'] = false;
                u['deletedAt'] = DateTime.now().toIso8601String();
                break;
              }
            }
            _filterUsers(_searchController.text);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully.'), backgroundColor: Colors.green),
          );
        }

        // Refresh authoritative list from server
        if (mounted) await _fetchUsers();

        return true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp['message'] ?? 'Failed to delete user.'), backgroundColor: Colors.red),
          );
        }
        return false;
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delete request timed out.'), backgroundColor: Colors.red),
        );
      }
      return false;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('API Error: ${e.message}'), backgroundColor: Colors.red),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
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
            child: Text(text)
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
        ],
      ),
    );
  }

  // ---------------------------
  // Bottom sheet to add a user (FIXED)
  // ---------------------------
  void _showAddUserBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => _AddUserBottomSheet(
        onUserAdded: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User added successfully.'), backgroundColor: Colors.green)
            );
            _fetchUsers();
          }
        },
        createUserCallback: _createUserWithTimeout,
        isAdding: _isAdding,
      ),
    );
  }

  // UI: user card
  Widget _userCard(Map<String, dynamic> u) {
    final idRaw = u['_id'] ?? u['userId'] ?? u['id'];
    final id = _idOf(idRaw);
    final username = (u['username'] ?? u['name'] ?? u['email'] ?? 'N/A').toString();
    final role = (u['role'] ?? 'officer').toString();
    final isActive = _isUserActive(u);
    final roleIcon = _getRoleIcon(role);

    return FadeInUp(
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {},
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
                        username,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      if (u['email'] != null && u['email'].toString().isNotEmpty)
                        Text(u['email'].toString(), style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      Wrap(
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
                        final confirm = await _showConfirmDialog('Delete user $username?');
                        if (confirm == true && mounted) {
                          // show loading dialog with rootNavigator to ensure it attaches to the app navigator
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            useRootNavigator: true,
                            builder: (_) => const Center(child: CircularProgressIndicator()),
                          );

                          try {
                            // _deleteUser has internal timeout/handling
                            await _deleteUser(id);
                          } finally {
                            // always dismiss the loading dialog if still mounted
                            if (mounted) {
                              try {
                                Navigator.of(context, rootNavigator: true).pop();
                              } catch (_) {
                                // ignore - already popped or navigator gone
                              }
                            }
                          }
                        }
                      } else if (v == 'change_role') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Role update requires manual delete and re-add in the current API version.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'change_role', child: Text('Change Role (Re-add Required)')),
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
      case 'officer':
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
      case 'officer':
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
    // Active = green, Deleted/Inactive = red
    final bg = isActive ? Colors.green.shade50 : Colors.red.shade50;
    final border = isActive ? Colors.green.shade700 : Colors.red.shade700;
    final txt = isActive ? 'Active' : 'Deleted';
    final txtColor = isActive ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        txt,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: txtColor,
        ),
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
      // appBar: AppBar(
      //   title: const Text('User Management', style: TextStyle(fontWeight: FontWeight.bold)),
      //   backgroundColor: primaryBlue,
      //   foregroundColor: Colors.white,
      //   centerTitle: true,
      // ),
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
                          hintText: 'Search username or role...',
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
                      onPressed: _showAddUserBottomSheet,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Three-dot popup menu beside Add button to toggle deleted users
                    PopupMenuButton<String>(
                      tooltip: _showDeleted ? 'Hide deleted users' : 'Show deleted users',
                      icon: const Icon(Icons.more_vert, color: Colors.black54),
                      onSelected: (v) {
                        if (v == 'toggle_deleted') {
                          setState(() {
                            _showDeleted = !_showDeleted;
                            _filterUsers(_searchController.text);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_showDeleted ? 'Showing deleted users' : 'Hiding deleted users'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        } else if (v == 'refresh') {
                          _fetchUsers();
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'toggle_deleted',
                          child: Row(
                            children: [
                              Icon(_showDeleted ? Icons.visibility_off : Icons.visibility, color: Colors.black54),
                              const SizedBox(width: 8),
                              Text(_showDeleted ? 'Hide Deleted Users' : 'Show Deleted Users'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, color: Colors.black54),
                              SizedBox(width: 8),
                              Text('Refresh'),
                            ],
                          ),
                        ),
                      ],
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

// ---------------------------
// Separate StatefulWidget for bottom sheet
// ---------------------------
class _AddUserBottomSheet extends StatefulWidget {
  final VoidCallback onUserAdded;
  final Future<bool> Function({required String username, required String password, required String role, Duration timeout}) createUserCallback;
  final bool isAdding;

  const _AddUserBottomSheet({
    required this.onUserAdded,
    required this.createUserCallback,
    required this.isAdding,
  });

  @override
  State<_AddUserBottomSheet> createState() => _AddUserBottomSheetState();
}

class _AddUserBottomSheetState extends State<_AddUserBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();

  String _currentRole = 'officer';
  bool _localLoading = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    // Auto-focus username field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _usernameFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_localLoading || widget.isAdding) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _localLoading = true;
      _localError = null;
    });

    try {
      final success = await widget.createUserCallback(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        role: _currentRole,
        timeout: const Duration(seconds: 20),
      );

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop();
        widget.onUserAdded();
      } else {
        setState(() => _localError = 'Add failed: server returned failure.');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _localError = 'Request timed out after 20 seconds.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _localError = 'API Error: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _localError = 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _localLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_localLoading && !widget.isAdding,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        padding: EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Text(
                    'Add User',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          focusNode: _usernameFocus,
                          enabled: !_localLoading && !widget.isAdding,
                          validator: (v) => v == null || v.trim().isEmpty ? 'Username required' : null,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !_localLoading && !widget.isAdding,
                          validator: (v) => v == null || v.trim().isEmpty ? 'Password required' : null,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Role',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.work_outline),
                          ),
                          value: _currentRole,
                          items: const [
                            DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                            DropdownMenuItem(value: 'admin', child: Text('Admin')),
                            DropdownMenuItem(value: 'officer', child: Text('Officer')),
                          ],
                          onChanged: (_localLoading || widget.isAdding)
                              ? null
                              : (v) {
                            if (v != null) setState(() => _currentRole = v);
                          },
                        ),
                        const SizedBox(height: 20),
                        if (_localError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _localError!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_localLoading || widget.isAdding) ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: (_localLoading || widget.isAdding)
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                                : const Text('Add User', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Full overlay when loading
            if (_localLoading || widget.isAdding)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
