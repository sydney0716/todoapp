import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/screens/completed_screen.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/theme.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets(
        'completed dates and order survive later edits (${language.languageCode})',
        (tester) async {
      final repository = _CompletedRepository([
        TodoTask(
          title: 'Older completion edited later',
          isCompleted: true,
          completedAt: DateTime(2026, 6, 1),
          updatedAt: DateTime(2026, 6, 20),
        ),
        TodoTask(
          title: 'Recent completion',
          isCompleted: true,
          completedAt: DateTime(2026, 6, 10),
          updatedAt: DateTime(2026, 6, 10),
        ),
        TodoTask(
          title: 'Legacy completion',
          isCompleted: true,
          updatedAt: DateTime(2026, 6, 5),
        ),
        TodoTask(title: 'Still open'),
      ]);
      final settings = SettingsController()..language = language;
      addTearDown(repository.dispose);
      addTearDown(settings.dispose);

      await tester.pumpWidget(MaterialApp(
        locale: language.locale,
        supportedLocales: const [Locale('en'), Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildLightTheme(),
        home: CompletedScreen(repository: repository, settings: settings),
      ));
      await tester.pumpAndSettle();

      final dates = language == AppLanguage.korean
          ? ['2026년 6월 1일 완료됨', '2026년 6월 5일 완료됨', '2026년 6월 10일 완료됨']
          : [
              'Completed Jun 1, 2026',
              'Completed Jun 5, 2026',
              'Completed Jun 10, 2026'
            ];
      for (final date in dates) {
        expect(find.text(date), findsOneWidget);
      }
      expect(find.text('Still open'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Recent completion')).dy,
        lessThan(tester.getTopLeft(find.text('Legacy completion')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Legacy completion')).dy,
        lessThan(
            tester.getTopLeft(find.text('Older completion edited later')).dy),
      );
    });
  }
}

class _CompletedRepository extends LocalTodoRepository {
  _CompletedRepository(this._completedTasks);

  final List<TodoTask> _completedTasks;

  @override
  List<TodoTask> get tasks => _completedTasks;
}
