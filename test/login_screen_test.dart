import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/screens/login_screen.dart';
import 'package:personaltodo/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selects an account before showing password login',
      (tester) async {
    AppAccount? submittedAccount;
    String? submittedPassword;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: LoginScreen(
          onLogin: (account, password) async {
            submittedAccount = account;
            submittedPassword = password;
          },
        ),
      ),
    );

    expect(find.text('User'), findsOneWidget);
    expect(find.text('Partner'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-password-field')), findsNothing);

    await tester.tap(find.text('Partner'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-password-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('login-password-field')),
      'private-password',
    );
    await tester.tap(find.byKey(const ValueKey('login-submit-button')));
    await tester.pumpAndSettle();

    expect(submittedAccount?.id, partnerUserId);
    expect(submittedAccount?.username, 'partner');
    expect(submittedPassword, 'private-password');
  });

  testWidgets('requires a password after account selection', (tester) async {
    var loginCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: LoginScreen(
          onLogin: (account, password) async {
            loginCount += 1;
          },
        ),
      ),
    );

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('login-submit-button')));
    await tester.pumpAndSettle();

    expect(loginCount, 0);
    expect(find.text('Password is required.'), findsOneWidget);
  });
}
