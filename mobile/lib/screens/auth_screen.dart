import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../widgets/pulse.dart';

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
        SnackBar(content: Text(widget.app.error!), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PulseBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.bolt_rounded, color: AppTheme.primaryInk, size: 30),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(_isLogin ? 'hey,\nyou’re back.' : 'new here.\nlet’s go.', style: AppTheme.display(size: 40, letterSpacing: -1.6)),
                      const SizedBox(height: 10),
                      Text(
                        _isLogin ? 'drop in. your people are already talking.' : 'username, vibe, password. thirty seconds.',
                        style: AppTheme.body(size: 15, color: AppTheme.textSecondary, height: 1.45),
                      ),
                      const SizedBox(height: 32),
                      if (!_isLogin) ...[
                        _field(
                          controller: _usernameCtrl,
                          label: 'username',
                          hint: 'vothaianh',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'need a username' : null,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _fullNameCtrl,
                          label: 'full name',
                          hint: 'Anh Vo Thai',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'who are you?' : null,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _emailCtrl,
                          label: 'email',
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => (v == null || !v.contains('@')) ? 'that email looks off' : null,
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        _field(
                          controller: _loginCtrl,
                          label: 'username or email',
                          hint: 'vothaianh',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'type something' : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _field(
                        controller: _passwordCtrl,
                        label: 'password',
                        hint: '••••••••',
                        obscure: _obscure,
                        suffix: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        validator: (v) => (v == null || v.length < 8) ? '8+ characters' : null,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: widget.app.loading ? null : _submit,
                        child: widget.app.loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryInk),
                              )
                            : Text(_isLogin ? 'enter' : 'create account'),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isLogin ? "no account?" : 'already in?',
                            style: AppTheme.body(color: AppTheme.textSecondary),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _isLogin = !_isLogin),
                            child: Text(_isLogin ? 'sign up' : 'sign in'),
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
