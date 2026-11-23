import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_tracker/services/auth_service.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/screens/login_screen.dart';
import 'package:expense_tracker/screens/home_screen.dart';
import 'package:expense_tracker/widgets/loading_screen.dart';
import 'package:expense_tracker/utils/app_theme.dart';

const uid = 'bba38328-ad81-4e4f-a77e-2e38f333f122';

class RestoreProvider extends ExpenseProvider {
  RestoreProvider() : super(initialize: false);
  @override
  Future<void> reloadSession() async {}
}

class RestoreAuth extends SpendlyAuthService {
  RestoreAuth(SupabaseClient client) : super(client: client);
  final first = Completer<User>();
  var calls = 0;
  @override
  Future<User> saveVerifiedProfile() async =>
      calls++ == 0 ? await first.future : client.auth.currentUser!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'legacyImportChecked:$uid': true});
    final data = {
      'id': uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'test@example.com',
      'created_at': '2026-10-13T00:00:00Z',
      'email_confirmed_at': '2026-10-13T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{}
    };
    client = SupabaseClient('https://test.supabase.co', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async => http.Response('{}', 200)));
    await client.auth.recoverSession(jsonEncode({
      'access_token': 'test-token',
      'refresh_token': 'refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': data
    }));
  });
  tearDown(() => client.dispose());
  testWidgets(
      'saved-session retry and home transition never show the login form',
      (tester) async {
    final auth = RestoreAuth(client);
    final provider = RestoreProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ExpenseProvider>.value(
        value: provider,
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: LoginScreen(auth: auth))));
    await tester.pump();
    expect(find.byType(LoadingScreen), findsOneWidget);
    auth.first.completeError(StateError('Temporary network failure'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sign in to Spendly'), findsNothing);
    expect(find.text('Retry profile sync'), findsOneWidget);
    await tester.tap(find.text('Retry profile sync'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Sign in to Spendly'), findsNothing);
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
