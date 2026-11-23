import '../widgets/spendly_logo.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/expense_provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';
import '../widgets/loading_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.auth});
  final SpendlyAuthService? auth;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  SpendlyAuthService? _auth;
  StreamSubscription<AuthState>? _subscription;
  bool _restoring = true;
  bool _navigatingHome = false;
  bool _register = false;
  bool _busy = false;
  bool _finishing = false;
  bool _hidden = true;
  bool _legacy = false;
  bool _needsConfirmation = false;
  bool _recovering = false;
  bool _submitting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    try {
      _auth = widget.auth ?? SpendlyAuthService();
      _subscription = _auth!.client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          if (mounted) {
            setState(() {
              _recovering = true;
              _register = false;
              _legacy = false;
              _password.clear();
              _message = 'Enter a new password of at least 8 characters.';
            });
          }
          return;
        }
        if (state.session != null && !_submitting && !_recovering) {
          _finishOnline();
        }
      },
          onError: (Object error) => _show(
              'Sign-in link could not be opened. Please try signing in again.'));
    } catch (_) {
      _message =
          'Online sign-in is unavailable. Restart the app and check your connection.';
    }
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _email.text = prefs.getString('authEmail') ?? '';
      if (!_recovering && _auth?.client.auth.currentSession != null) {
        await _finishOnline();
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _show(String message) {
    if (mounted) setState(() => _message = message);
  }

  Future<void> _finishOnline() async {
    if (_finishing || !mounted) return;
    _finishing = true;
    setState(() => _busy = true);
    try {
      final user = await _auth!.saveVerifiedProfile();
      if (!mounted) return;
      await _offerLegacyImport(user);
      if (!mounted) return;
      await context.read<ExpenseProvider>().reloadSession();
      _home();
    } on AuthException catch (error) {
      _show(error.message);
    } catch (_) {
      _show(
          'Signed in, but your profile could not be saved online. Check your connection and the database setup, then tap Retry profile sync.');
    } finally {
      _finishing = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerLegacyImport(User user) async {
    if (user.email == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'legacyImportChecked:${user.id}';
    if (prefs.getBool(key) == true) return;
    final legacy = await DatabaseService().getUserByEmail(user.email!);
    if (legacy == null || !legacy.id.startsWith('SP-') || !mounted) return;
    String pin = '';
    String? error;
    final imported = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Keep your existing expenses'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'An offline account with this email exists on this phone. Enter its old PIN to move its records into your online account.'),
                    TextField(
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        onChanged: (value) => pin = value,
                        decoration: InputDecoration(
                            labelText: 'Existing offline PIN',
                            errorText: error)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep separate')),
                    TextButton(
                        onPressed: () {
                          if (pin != legacy.pin) {
                            update(() => error = 'Incorrect PIN');
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Move my records')),
                  ],
                )));
    if (imported == true) {
      await DatabaseService().moveLegacyRecords(legacy.id, user.id);
    }
    await prefs.setBool(key, true);
  }

  Future<void> _submit() async {
    if (_recovering) {
      if (_password.text.length < 8) {
        _show('Use at least 8 characters.');
        return;
      }
      setState(() => _busy = true);
      try {
        await _auth!.updatePassword(_password.text);
        _recovering = false;
        await _finishOnline();
      } on AuthException catch (error) {
        _show(error.message);
      } catch (_) {
        _show('Could not update your password. Please try again.');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _show('Enter a valid email address as your account ID.');
      return;
    }
    if (_password.text.isEmpty ||
        (!_legacy && _register && _password.text.length < 8)) {
      _show(_legacy
          ? 'Enter your existing PIN.'
          : 'Use a password of at least 8 characters.');
      return;
    }
    if (_register && _name.text.trim().isEmpty) {
      _show('Enter your name.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    _submitting = true;
    try {
      if (_legacy) {
        final user = await DatabaseService().getUserByEmail(email);
        if (user == null || user.pin != _password.text) {
          _show('Email or offline PIN is incorrect.');
          return;
        }
        await _auth?.client.auth.signOut(scope: SignOutScope.local);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('currentUserId', user.id);
        await prefs.setString('userId', user.id);
        await prefs.setString('userName', user.name);
        await prefs.setString('userEmail', user.email);
        await prefs.setString('authEmail', user.email);
        await prefs.setBool('is_logged_in', true);
        if (!mounted) return;
        await context.read<ExpenseProvider>().reloadSession();
        _home();
      } else if (_register) {
        final response = await _auth!.signUp(_name.text, email, _password.text);
        if (response.session == null) {
          if (!mounted) return;
          setState(() => _needsConfirmation = true);
          _show(
              'Check your inbox (including spam) and confirm your email. Then return here and sign in.');
        } else {
          await _finishOnline();
        }
      } else {
        await _auth!.signIn(email, _password.text);
        await _finishOnline();
      }
    } on AuthException catch (error) {
      _show(error.message);
    } catch (_) {
      _show('Unable to sign in. Check your internet connection and try again.');
    } finally {
      _submitting = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final launched = await _auth!.signInWithGoogle();
      _show(launched
          ? 'Complete sign-in in Google, then return to Spendly.'
          : 'Could not open Google sign-in. Try again.');
    } on AuthException catch (error) {
      _show(error.message);
    } catch (_) {
      _show(
          'Google sign-in could not start. Check your connection and Google provider setup.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await _auth!.resendConfirmation(_email.text);
      _show('Confirmation email requested. Check your inbox and spam.');
    } on AuthException catch (error) {
      _show(error.message);
    } catch (_) {
      _show('Could not resend. Please try again later.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      _show('Enter your email ID first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth!.requestPasswordReset(_email.text);
      _show(
          'If this email has an account, a password reset link will arrive in its inbox.');
    } on AuthException catch (error) {
      _show(error.message);
    } catch (_) {
      _show('Could not request a reset. Please try again later.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _home() {
    if (!mounted || _navigatingHome) return;
    setState(() => _navigatingHome = true);
    Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero),
        (_) => false);
  }

  Widget _restorationHelp() => Scaffold(
          body: Stack(children: [
        const LoadingScreen(),
        SafeArea(
            child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      _message ??
                                          'Finishing your sign-in. Please check your connection.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12)),
                                  Wrap(spacing: 12, children: [
                                    TextButton(
                                        onPressed: _finishOnline,
                                        child:
                                            const Text('Retry profile sync')),
                                    TextButton(
                                        onPressed: () async {
                                          await _auth!.signOut();
                                          if (mounted)
                                            setState(() => _message = null);
                                        },
                                        child: const Text('Sign out'))
                                  ]),
                                ])))))),
      ]));

  @override
  Widget build(BuildContext context) => (_restoring ||
          _finishing ||
          _navigatingHome)
      ? const LoadingScreen()
      : (_auth?.client.auth.currentSession != null &&
              !_recovering &&
              !_needsConfirmation)
          ? _restorationHelp()
          : Scaffold(
              backgroundColor: AppPalette.of(context).bgDark,
              body: SafeArea(
                  child: Center(
                      child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AutofillGroup(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SpendlyLogo(size: 100),
                        const SizedBox(height: 20),
                        Text(
                            _legacy
                                ? 'Existing offline account'
                                : _register
                                    ? 'Create Spendly account'
                                    : 'Sign in to Spendly',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: AppPalette.of(context).textPrimary)),
                        const SizedBox(height: 10),
                        Text(
                            _legacy
                                ? 'Access records saved on this phone. AI scanning requires an online account.'
                                : 'Use your email ID and password, or continue with Google. Your online account enables AI receipt scanning.',
                            style: TextStyle(
                                color: AppPalette.of(context).textSecondary)),
                        const SizedBox(height: 24),
                        if (_register)
                          TextField(
                              controller: _name,
                              enabled: !_busy,
                              autofillHints: const [AutofillHints.name],
                              decoration:
                                  const InputDecoration(labelText: 'Name')),
                        TextField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration:
                                const InputDecoration(labelText: 'Email ID')),
                        const SizedBox(height: 12),
                        TextField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: _hidden,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: _legacy
                                ? null
                                : [
                                    _register
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password
                                  ],
                            decoration: InputDecoration(
                                labelText:
                                    _legacy ? 'Existing PIN' : 'Password',
                                suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => _hidden = !_hidden),
                                    icon: Icon(_hidden
                                        ? Icons.visibility
                                        : Icons.visibility_off)))),
                        const SizedBox(height: 20),
                        if (_message != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(_message!,
                                  style: TextStyle(
                                      color: AppPalette.of(context)
                                          .textSecondary))),
                        if (_busy)
                          const Center(child: CircularProgressIndicator()),
                        ElevatedButton(
                            onPressed: _busy || (!_legacy && _auth == null)
                                ? null
                                : _submit,
                            child: Text(_recovering
                                ? 'Save new password'
                                : _register
                                    ? 'Sign up'
                                    : 'Sign in')),
                        if (!_legacy && !_recovering) ...[
                          TextButton(
                              onPressed: _busy || _auth == null
                                  ? null
                                  : _resetPassword,
                              child: const Text('Forgot password?')),
                          OutlinedButton.icon(
                              onPressed:
                                  _busy || _auth == null ? null : _google,
                              icon: const Icon(Icons.account_circle_outlined),
                              label: const Text('Continue with Google')),
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _register = !_register;
                                        _message = null;
                                        _password.clear();
                                      }),
                              child: Text(_register
                                  ? 'Already registered? Sign in'
                                  : 'New here? Sign up')),
                          if (_needsConfirmation)
                            TextButton(
                                onPressed: _busy ? null : _resend,
                                child: const Text('Resend confirmation email')),
                          if (_auth?.client.auth.currentSession != null)
                            TextButton(
                                onPressed: _busy ? null : _finishOnline,
                                child: const Text('Retry profile sync')),
                        ],
                        TextButton(
                            onPressed: _busy || _recovering
                                ? null
                                : () => setState(() {
                                      _legacy = !_legacy;
                                      _register = false;
                                      _message = null;
                                      _password.clear();
                                    }),
                            child: Text(_legacy
                                ? 'Back to online sign-in'
                                : 'Access an existing offline account')),
                      ],
                    ))),
              ))),
            );
}
