import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Credentials are handled only by Supabase Auth, never by the profile table.
class SpendlyAuthService {
  static const redirectUrl = 'com.spendly.app://auth-callback/';
  final SupabaseClient client;
  SpendlyAuthService({SupabaseClient? client})
      : client = client ?? Supabase.instance.client;

  Future<AuthResponse> signIn(String email, String password) =>
      client.auth.signInWithPassword(
          email: email.trim().toLowerCase(), password: password);

  Future<AuthResponse> signUp(
      String name, String email, String password) async {
    final response = await client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        emailRedirectTo: redirectUrl,
        data: {'name': name.trim()});
    if (response.user?.identities?.isEmpty == true) {
      throw const AuthException(
          'This email is already registered. Sign in or reset your password.');
    }
    return response;
  }

  Future<bool> signInWithGoogle() => client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        queryParams: {'prompt': 'select_account'},
      );

  Future<void> resendConfirmation(String email) => client.auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
      emailRedirectTo: redirectUrl);

  Future<void> requestPasswordReset(String email) =>
      client.auth.resetPasswordForEmail(email.trim(), redirectTo: redirectUrl);

  Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }

  Future<User> saveVerifiedProfile() async {
    // Validate with the server before associating local data or uploading a profile.
    final user = (await client.auth.getUser()).user;
    if (user == null || user.emailConfirmedAt == null) {
      throw const AuthException('Please confirm your email before signing in.');
    }
    final profile = await client
        .from('app_users')
        .select('name')
        .eq('id', user.id)
        .maybeSingle();
    final metadata = user.userMetadata ?? {};
    final name = profile?['name'] as String? ??
        metadata['name'] as String? ??
        metadata['full_name'] as String? ??
        user.email?.split('@').first ??
        'User';
    await client.from('app_users').upsert({
      'id': user.id,
      'name': name,
      'email': user.email ?? '',
      'created_at': user.createdAt,
      'last_login_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentUserId', user.id);
    await prefs.setString('userId', user.id);
    await prefs.setString('userName', name);
    await prefs.setString('userEmail', user.email ?? '');
    await prefs.setString('authEmail', user.email ?? '');
    await prefs.remove('authPin');
    await prefs.setBool('is_logged_in', true);
    return user;
  }

  Future<void> signOut() async {
    await client.auth.signOut(scope: SignOutScope.local);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    for (final key in [
      'currentUserId',
      'userId',
      'userName',
      'userEmail',
      'authPin'
    ]) {
      await prefs.remove(key);
    }
  }
}
