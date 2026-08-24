import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import 'auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSignUp = false;
  bool _isBusy = false;
  String? _error;

  Future<void> _submitEmailForm() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final error = _isSignUp
        ? await auth.signUpWithEmail(_emailController.text, _passwordController.text, _nameController.text)
        : await auth.loginWithEmail(_emailController.text, _passwordController.text);
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _error = error;
    });
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final error = await context.read<AuthProvider>().loginWithGoogle();
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _error = error;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: SvgPicture.asset('assets/images/myna-logo.svg', width: 128, height: 128)),
              const SizedBox(height: 24),
              Text(_isSignUp ? 'Create account' : 'Welcome back', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                _isSignUp ? 'Sign up for your SmartPoc account' : 'Log in to your SmartPoc account',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              if (_isSignUp) ...[
                const Text('Name', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(hintText: 'Your name', border: InputBorder.none),
                ),
                const SizedBox(height: 20),
              ],
              const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'you@example.com', border: InputBorder.none),
              ),
              const SizedBox(height: 20),
              const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(hintText: '••••••••', border: InputBorder.none),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _isBusy ? null : _submitEmailForm,
                child: _isBusy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isSignUp ? 'Sign Up' : 'Log In'),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _isBusy ? null : () => setState(() => _isSignUp = !_isSignUp),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(color: AppColors.textSecondary),
                      children: [
                        TextSpan(text: _isSignUp ? 'Already have an account? ' : "Don't have an account? "),
                        TextSpan(
                          text: _isSignUp ? 'Log in' : 'Sign up',
                          style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: AppColors.textSecondary))),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton(onPressed: _isBusy ? null : _submitGoogle, child: const Text('Continue with Google')),
            ],
          ),
        ),
      ),
    );
  }
}
