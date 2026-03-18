import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../widgets/auth_field_glyph.dart';
import '../../../widgets/brand_lockup.dart';
import '../../../widgets/google_mark.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _passwordFocus = FocusNode();
  final _otpFocus = FocusNode();

  bool _loading = false;
  bool _success = false;
  bool _verified = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    _passwordFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    final code = _otp.text.trim();
    if (code.length != 6) {
      setState(() => _error = l10n.tr('invalid_otp_code'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: _email.text.trim(),
        token: code,
        type: OtpType.signup,
      );
      if (!mounted) return;
      setState(() {
        _verified = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = l10n.tr('invalid_otp_code');
        _loading = false;
      });
    }
  }

  Future<void> _registerWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: '${Uri.base.origin}/login',
        );
        return;
      }
      // On Android, Google sign-in/up is the same flow — redirect to login
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
      _success = false;
    });

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: kIsWeb ? null : 'com.allonssy.app://login-callback',
      );

      if (res.user == null) throw l10n.tr('sign_up_failed');

      final identities = res.user!.identities ?? const [];
      final looksLikeExistingUser = res.session == null &&
          identities.isEmpty &&
          (res.user!.email?.trim().toLowerCase() == _email.text.trim().toLowerCase());

      if (looksLikeExistingUser) {
        throw l10n.tr('email_exists_login');
      }

      // If email verification is enabled, session might be null
      if (res.session == null) {
        if (mounted) {
          setState(() {
            _success = true;
            _loading = false;
          });
        }
      } else {
        if (mounted) context.go('/home');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted && !_success) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5F1E8), Color(0xFFF0EEE7)],
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
                    colors: [Color(0xFFCC7A00), Color(0xFF8B5A12)],
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
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.groups_2_outlined,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('join'),
                          style: TextStyle(
                            fontSize: 40,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -1.0,
                          ),
                        ),
                        SizedBox(height: 8),
                        const BrandLockup(height: 46),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.tr('register_intro'),
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _brandChip(l10n.tr('create_profile')),
                        _brandChip(l10n.tr('share_locally')),
                        _brandChip(l10n.tr('find_nearby_deals')),
                        _brandChip(l10n.tr('chat_safely')),
                      ],
                    ),
                  ],
                ),
              );

              final registerCard = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
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
                    child: _success
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _verified
                                    ? Icons.verified_outlined
                                    : Icons.mark_email_read_outlined,
                                color: _verified
                                    ? const Color(0xFF147A74)
                                    : const Color(0xFFCC7A00),
                                size: 64,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _verified
                                    ? l10n.tr('verification_success')
                                    : l10n.tr('check_your_email'),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              if (!_verified) ...[
                                Text(
                                  l10n.tr(
                                    'verification_email_sent',
                                    args: {'email': _email.text},
                                  ),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                TextField(
                                  controller: _otp,
                                  focusNode: _otpFocus,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  maxLength: 6,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 10,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '000000',
                                    hintStyle: const TextStyle(
                                      letterSpacing: 10,
                                      color: Color(0xFFBBBBBB),
                                    ),
                                    labelText: l10n.tr('verification_code'),
                                    counterText: '',
                                  ),
                                  onSubmitted: (_) {
                                    if (!_loading) _verifyOtp();
                                  },
                                ),
                                const SizedBox(height: 16),
                                if (_error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Color(0xFFD92D20)),
                                    ),
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _loading ? null : _verifyOtp,
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF147A74),
                                    ),
                                    child: Text(
                                      _loading
                                          ? l10n.tr('verifying')
                                          : l10n.tr('verify_email'),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => context.go('/login'),
                                  child: Text(l10n.tr('return_to_login')),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.tr('create_account'),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.tr('start_local_profile'),
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
                                decoration: InputDecoration(
                                  labelText: l10n.tr('email'),
                                  prefixIcon: Padding(
                                    padding: EdgeInsets.all(14),
                                    child: AuthFieldGlyph(
                                      kind: AuthFieldGlyphKind.email,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!_loading) _register();
                                },
                                decoration: InputDecoration(
                                  labelText: l10n.tr('password'),
                                  prefixIcon: Padding(
                                    padding: EdgeInsets.all(14),
                                    child: AuthFieldGlyph(
                                      kind: AuthFieldGlyphKind.password,
                                    ),
                                  ),
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
                                  onPressed: _loading ? null : _register,
                                  child: Text(
                                    _loading
                                        ? l10n.tr('creating')
                                        : l10n.tr('create_account'),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _loading ? null : _registerWithGoogle,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF202124),
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(color: Color(0xFF9AA0A6), width: 1.2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  icon: const GoogleMark(size: 22),
                                  label: Text(l10n.tr('continue_with_google')),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => context.go('/login'),
                                  child: Text(l10n.tr('back_to_login')),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const _LegalFooter(),
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
                        child: registerCard,
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
                    registerCard,
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
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
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

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      fontSize: 12,
      color: Color(0xFF18847A),
      decoration: TextDecoration.underline,
    );
    const sepStyle = TextStyle(fontSize: 12, color: Color(0xFF9E9E9E));

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        GestureDetector(
          onTap: () => context.push('/about'),
          child: const Text('About Us', style: linkStyle),
        ),
        const Text('·', style: sepStyle),
        GestureDetector(
          onTap: () => context.push('/terms'),
          child: const Text('Terms & Conditions', style: linkStyle),
        ),
        const Text('·', style: sepStyle),
        GestureDetector(
          onTap: () => context.push('/privacy'),
          child: const Text('Privacy Policy', style: linkStyle),
        ),
      ],
    );
  }
}
