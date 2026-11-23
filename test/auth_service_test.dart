import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_tracker/services/auth_service.dart';
import 'package:expense_tracker/services/supabase_sync_service.dart';

const userId = 'bba38328-ad81-4e4f-a77e-2e38f333f122';
Map<String, dynamic> user({bool confirmed = true}) => {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'test@example.com',
      'created_at': '2026-10-13T00:00:00Z',
      if (confirmed) 'email_confirmed_at': '2026-10-13T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': {'name': 'Test User'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'email registration sends credentials only to Auth, with confirmation redirect',
      () async {
    final requests = <http.Request>[];
    final client = SupabaseClient('https://test.supabase.co', 'test-key',
        authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryStorage()),
        httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(user(confirmed: false)), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);
    final auth = SpendlyAuthService(client: client);
    final response =
        await auth.signUp('Test User', 'test@example.com', 'Test-password-123');
    expect(response.session, isNull);
    expect(requests.single.url.path, '/auth/v1/signup');
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['password'], 'Test-password-123');
    expect(body['data'], {'name': 'Test User'});
    expect(requests.single.url.queryParameters['redirect_to'],
        SpendlyAuthService.redirectUrl);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('is_logged_in'), isNull);
  });

  test('registration normalizes email and rejects an existing-account response',
      () async {
    String? sent;
    final client = SupabaseClient('https://test.supabase.co', 'test-key',
        authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryStorage()),
        httpClient: MockClient((request) async {
      sent = (jsonDecode(request.body) as Map)['email'] as String;
      return http.Response(jsonEncode({...user(), 'identities': []}), 200,
          headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    await expectLater(
        SpendlyAuthService(client: client)
            .signUp('Test', ' TEST@Example.Com ', 'Test-password-123'),
        throwsA(isA<AuthException>()));
    expect(sent, 'test@example.com');
  });

  test(
      'verified login uploads a profile without passwords or PIN and saves auth UUID',
      () async {
    Map? uploaded;
    final client = SupabaseClient('https://test.supabase.co', 'test-key',
        authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryStorage()),
        httpClient: MockClient((request) async {
      Object data;
      if (request.url.path.endsWith('/token')) {
        data = {
          'access_token': 'test-token',
          'refresh_token': 'test-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': user()
        };
      } else if (request.url.path.endsWith('/user')) {
        data = user();
      } else if (request.method == 'GET') {
        data = <Object>[];
      } else {
        uploaded = jsonDecode(request.body) as Map;
        data = <Object>[];
      }
      return http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);
    final auth = SpendlyAuthService(client: client);
    await auth.signIn('test@example.com', 'Test-password-123');
    await auth.saveVerifiedProfile();
    expect(uploaded?['id'], userId);
    expect(uploaded?['name'], 'Test User');
    expect(uploaded?.containsKey('pin'), isFalse);
    expect(uploaded?.containsKey('password'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('currentUserId'), userId);
    expect(prefs.getBool('is_logged_in'), isTrue);
  });

  test(
      'unverified users cannot upload profiles or activate a local online session',
      () async {
    var profileRequests = 0;
    final client = SupabaseClient('https://test.supabase.co', 'test-key',
        authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryStorage()),
        httpClient: MockClient((request) async {
      if (request.url.path.startsWith('/rest/')) profileRequests++;
      return http.Response(jsonEncode(user(confirmed: false)), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);
    await expectLater(SpendlyAuthService(client: client).saveVerifiedProfile(),
        throwsA(isA<AuthException>()));
    expect(profileRequests, 0);
    expect((await SharedPreferences.getInstance()).getBool('is_logged_in'),
        isNull);
  });

  test('shared default categories get distinct cloud IDs for each user', () {
    expect(
        SupabaseSyncService.cloudCategoryId('a', 'groceries'), 'a:groceries');
    expect(SupabaseSyncService.cloudCategoryId('b', 'groceries'),
        isNot('a:groceries'));
  });
}

class _MemoryStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}
