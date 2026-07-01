import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

class AuthScreen extends StatefulWidget {
  final AppState app;
  const AuthScreen({super.key, required this.app});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  final _formKey = GlobalKey<FormState>();
  final _loginCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    bool ok;
    if (_isLogin) {
      ok = await widget.app.login(login: _loginCtrl.text.trim(), password: _passwordCtrl.text);
    } else {
      ok = await widget.app.register(
        username: _usernameCtrl.text.trim().toLowerCase(),
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim().toLowerCase(),
        password: _passwordCtrl.text,
      );
    }
    if (!ok && widget.app.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.app.error!), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.forum, color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _isLogin ? 'Welcome back' : 'Create your account',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isLogin ? 'Sign in to continue chatting' : 'Join the conversation in seconds',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 26),
                    if (!_isLogin) ...[
                      _field(
                        controller: _usernameCtrl,
                        label: 'Username',
                        hint: 'e.g. vothaianh',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a username' : null,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _fullNameCtrl,
                        label: 'Full name',
                        hint: 'Anh Vo Thai',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _emailCtrl,
                        label: 'Email',
                        hint: 'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      _field(
                        controller: _loginCtrl,
                        label: 'Username or email',
                        hint: 'vothaianh',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter username or email' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _field(
                      controller: _passwordCtrl,
                      label: 'Password',
                      hint: '••••••••',
                      obscure: _obscure,
                      suffix: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: widget.app.loading ? null : _submit,
                      child: widget.app.loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isLogin ? 'Sign in' : 'Create account'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin ? "Don't have an account?" : 'Already have an account?',
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _isLogin = !_isLogin),
                          child: Text(_isLogin ? 'Sign up' : 'Sign in'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
      ),
    );
  }
}