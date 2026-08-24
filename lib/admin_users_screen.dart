import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'auth/db_service.dart';

// Mirrors smartglass_flutter's AdminUsersScreen (list/grant/revoke/delete)
// against the same shared `users` table - reachable from Profile only when
// AuthProvider.isSuperAdmin is true (DB-driven is_superadmin flag, set via
// this same screen or directly in Postgres; plain admin is deliberately
// excluded from user management, see profile_screen.dart).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _dbService = DbService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final users = await _dbService.getAllUsersForAdmin();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAdmin(Map<String, dynamic> user) async {
    final userId = user['user_id'] as int;
    final makeAdmin = !(user['is_admin'] == true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(makeAdmin ? 'Grant admin access?' : 'Remove admin access?'),
        content: Text(
          makeAdmin
              ? "Give '${user['email']}' full admin privileges?"
              : "Revoke admin privileges from '${user['email']}'?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(makeAdmin ? 'Grant' : 'Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _dbService.setUserAdminStatus(userId, makeAdmin);
      if (!mounted) return;
      setState(() => user['is_admin'] = makeAdmin);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(makeAdmin ? 'Admin access granted' : 'Admin access removed')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update admin status: $error')));
    }
  }

  // Superadmin is the only tier that reaches this screen and Developer
  // Tools (see profile_screen.dart) - plain admin is deliberately excluded
  // from user management.
  Future<void> _toggleSuperAdmin(Map<String, dynamic> user) async {
    final userId = user['user_id'] as int;
    final makeSuperAdmin = !(user['is_superadmin'] == true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(makeSuperAdmin ? 'Grant superadmin access?' : 'Remove superadmin access?'),
        content: Text(
          makeSuperAdmin
              ? "Give '${user['email']}' superadmin privileges (user management + developer tools)?"
              : "Revoke superadmin privileges from '${user['email']}'?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(makeSuperAdmin ? 'Grant' : 'Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _dbService.setUserSuperAdminStatus(userId, makeSuperAdmin);
      if (!mounted) return;
      setState(() => user['is_superadmin'] = makeSuperAdmin);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(makeSuperAdmin ? 'Superadmin access granted' : 'Superadmin access removed')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update superadmin status: $error')));
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final userId = user['user_id'] as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text("This permanently deletes '${user['email']}' and all their data. This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _dbService.deleteUser(userId);
      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u['user_id'] == userId));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete user: $error')));
    }
  }

  String _formatLastLogin(dynamic value) {
    if (value is! DateTime) return 'Never';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = context.watch<AuthProvider>().email.toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [IconButton(onPressed: _fetchUsers, icon: const Icon(Icons.refresh))],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: TextStyle(color: AppColors.danger))))
          : _users.isEmpty
          ? Center(child: Text('No users found', style: TextStyle(color: AppColors.textSecondary)))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingTextStyle: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w700),
                      dataTextStyle: TextStyle(color: AppColors.textPrimary),
                      columns: const [
                        DataColumn(label: Text('ID')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Last Login')),
                        DataColumn(label: Text('Role')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: _users.map((user) {
                        final email = (user['email'] ?? '').toString().toLowerCase();
                        final isDbAdmin = user['is_admin'] == true;
                        final isDbSuperAdmin = user['is_superadmin'] == true;
                        final isSelf = email == currentUserEmail;
                        final roleLabel = isDbSuperAdmin ? 'SUPERADMIN' : (isDbAdmin ? 'ADMIN' : 'USER');
                        final roleColor = isDbSuperAdmin || isDbAdmin ? AppColors.accentStrong : AppColors.textSecondary;

                        return DataRow(
                          cells: [
                            DataCell(Text(user['user_id']?.toString() ?? '-')),
                            DataCell(Text(user['email'] ?? '-')),
                            DataCell(Text(user['display_name'] ?? 'Unknown')),
                            DataCell(Text(_formatLastLogin(user['last_login']))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDbSuperAdmin || isDbAdmin ? AppColors.accentTint : AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  roleLabel,
                                  style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(isDbAdmin ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined, size: 20),
                                    tooltip: isDbAdmin ? 'Remove admin access' : 'Grant admin access',
                                    onPressed: () => _toggleAdmin(user),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      isDbSuperAdmin ? Icons.shield_moon : Icons.shield_moon_outlined,
                                      size: 20,
                                      color: isDbSuperAdmin ? AppColors.accentStrong : null,
                                    ),
                                    tooltip: isDbSuperAdmin ? 'Remove superadmin access' : 'Grant superadmin access',
                                    onPressed: () => _toggleSuperAdmin(user),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 20, color: isSelf ? AppColors.textSecondary : AppColors.danger),
                                    tooltip: isSelf ? "Can't delete your own account" : 'Delete user',
                                    onPressed: isSelf ? null : () => _deleteUser(user),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
