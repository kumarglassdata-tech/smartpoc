import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'auth/db_service.dart';

// Connects a Gmail App Password (not the real account password) so the
// backend can parse order-confirmation emails - matches smartglass_flutter's
// gmail_sync table/workflow against the same shared DB. Native only; there's
// no DB write path on web.
class GmailSyncDialog extends StatefulWidget {
  const GmailSyncDialog({super.key});

  @override
  State<GmailSyncDialog> createState() => _GmailSyncDialogState();
}

class _GmailSyncDialogState extends State<GmailSyncDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final appPassword = _passwordController.text.trim().replaceAll(' ', '');
    final userId = context.read<AuthProvider>().userId;

    try {
      if (kIsWeb) throw Exception('Gmail sync needs the native app, not the web build.');
      if (userId == null) throw Exception('Not logged in.');
      await DbService().saveGmailSync(userId, email, appPassword, 'success');
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gmail synced successfully.')));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sync Gmail', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Connect your email to securely parse past order receipts.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Text('Email address', style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Email is required' : null,
                decoration: const InputDecoration(hintText: 'you@gmail.com', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Text('App password (IMAP)', style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(hintText: '16-character Google App Password', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'App password is required';
                  final cleaned = value.replaceAll(' ', '');
                  if (cleaned.length != 16) return 'App password must be exactly 16 letters';
                  if (!RegExp(r'^[a-zA-Z]+$').hasMatch(cleaned)) return 'App password must contain only letters';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isBusy ? null : _sync,
                child: _isBusy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Secure Sync Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
