import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../widgets/auth_field_glyph.dart';
import '../../../widgets/brand_lockup.dart';
import '../../../widgets/google_mark.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.errorCode});
  final String? errorCode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _googleWebClientId =
      '460437609061-1haaf4f257071s7jsa7kqb4jatartf73.apps.googleusercontent.com';

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.errorCode == 'disabled' && _error == null) {
      _error = context.l10n.tr('account_disabled_contact_admin');
    }
  }

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
      await _finishLogin(result.user?.id);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    final l10n = context.l10n;
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

      final googleSignIn = GoogleSignIn(serverClientId: _googleWebClientId);
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return;
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw l10n.tr('google_tokens_missing');
      }

      final result = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      await _finishLogin(result.user?.id);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finishLogin(String? userId) async {
    final l10n = context.l10n;
    if (userId == null) {
      throw l10n.tr('sign_in_failed');
    }

    final client = Supabase.instance.client;
    try {
      final profile = await client.from('profiles').select('is_disabled').eq('id', userId).maybeSingle();

      if (profile?['is_disabled'] == true) {
        await client.auth.signOut();
        throw l10n.tr('account_disabled_contact_admin');
      }
    } on PostgrestException {
      // Allow login if the moderation migration has not been applied yet.
    }

    if (mounted) context.go('/feed');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        color: const Color(0xFFF3F1E8),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 920;

              final brandPanel = Container(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 30 : 26,
                  isWide ? 56 : 36,
                  isWide ? 30 : 26,
                  isWide ? 40 : 30,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF147A74), Color(0xFF0F6863)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isWide ? 22 : 28),
                    topRight: Radius.circular(isWide ? 22 : 28),
                    bottomLeft: Radius.circular(isWide ? 22 : 28),
                    bottomRight: Radius.circular(isWide ? 120 : 28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.location_on_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    SizedBox(height: isWide ? 26 : 22),
                    Text(
                      l10n.tr('welcome_to'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const BrandLockup(height: 52),
                    const SizedBox(height: 16),
                    Text(
                      l10n.tr('login_intro'),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _brandChip(l10n.tr('nearby_posts')),
                        _brandChip(l10n.tr('marketplace')),
                        _brandChip(l10n.tr('offer_chats')),
                        _brandChip(l10n.tr('local_services')),
                      ],
                    ),
                  ],
                ),
              );

              final loginCard = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0xFFF0E8DA)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140F2B24),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('welcome_back'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFF202124),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.tr('sign_in_to_network'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF6C6C6C),
                          ),
                        ),
                        const SizedBox(height: 22),
                        _buildField(
                          controller: _email,
                          hintText: l10n.tr('email'),
                          prefix: const AuthFieldGlyph(kind: AuthFieldGlyphKind.email),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _password,
                          hintText: l10n.tr('password'),
                          prefix: const AuthFieldGlyph(kind: AuthFieldGlyphKind.password),
                          focusNode: _passwordFocus,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_loading) _login();
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.go('/forgot-password'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF18847A),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(l10n.tr('forgot_password')),
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
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF147A74),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              _loading ? l10n.tr('signing_in') : l10n.tr('sign_in'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _loading ? null : _loginWithGoogle,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF202124),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF9AA0A6), width: 1.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const GoogleMark(size: 22),
                                const SizedBox(width: 10),
                                Text(l10n.tr('continue_with_google')),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => context.go('/register'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF18847A),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFFD8E0DD)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(l10n.tr('create_account_cta')),
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
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 11,
                        child: brandPanel,
                      ),
                      const SizedBox(width: 22),
                      Expanded(
                        flex: 10,
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

  Widget _buildField({
    required TextEditingController controller,
    required String hintText,
    required Widget prefix,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    FocusNode? focusNode,
    bool obscureText = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      focusNode: focusNode,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF6E6E6E),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(14),
          child: prefix,
        ),
        filled: true,
        fillColor: const Color(0xFFFFFCF7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD3DBD7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD3DBD7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF147A74), width: 1.4),
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
