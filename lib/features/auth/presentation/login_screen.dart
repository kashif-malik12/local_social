import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final result = await client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      final userId = result.user?.id;
      if (userId == null) {
        throw 'Sign in failed';
      }

      try {
        final profile = await client
            .from('profiles')
            .select('is_disabled')
            .eq('id', userId)
            .maybeSingle();

        if (profile?['is_disabled'] == true) {
          await client.auth.signOut();
          throw 'This account has been disabled. Contact an administrator.';
        }
      } on PostgrestException {
        // Allow login if the moderation migration has not been applied yet.
      }

      if (mounted) context.go('/feed');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5F1E8), Color(0xFFE9EFE7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              final brandPanel = Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF174E4A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.location_on_outlined,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Local Feed',
                      style: TextStyle(
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Neighborhood updates, marketplace deals, gigs, food ads, and local conversations in one place.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Colors.white.withOpacity(0.88),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _brandChip('Nearby posts'),
                        _brandChip('Marketplace'),
                        _brandChip('Offer chats'),
                        _brandChip('Local services'),
                      ],
                    ),
                  ],
                ),
              );

              final loginCard = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFE6DDCE)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to continue to your local network.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          focusNode: _passwordFocus,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_loading) _login();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.go('/forgot-password'),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFD92D20)),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _login,
                            child: Text(_loading ? 'Signing in...' : 'Sign in'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => context.go('/register'),
                            child: const Text('Create an account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

              if (isWide) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: brandPanel,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 5,
                        child: loginCard,
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: brandPanel,
                    ),
                    const SizedBox(height: 16),
                    loginCard,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _brandChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
