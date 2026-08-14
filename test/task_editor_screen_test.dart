import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/screens/task_editor_screen.dart';
import 'package:personaltodo/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new task editor shows a back button and lower category row',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: LocalTodoRepository(),
          settings: SettingsController(),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    final privateTop = tester.getTopLeft(find.text('Private')).dy;
    final categoryTop = tester.getTopLeft(find.text('No category')).dy;
    final subtaskTop = tester.getTopLeft(find.text('Add subtask')).dy;
    expect(categoryTop, greaterThan(privateTop));
    expect(categoryTop, lessThan(subtaskTop));
  });

  testWidgets('edit task editor shows back and delete buttons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: LocalTodoRepository(),
          settings: SettingsController(),
          task: TodoTask(id: 1, title: 'Existing task'),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    final backLeft = tester.getTopLeft(find.byIcon(Icons.arrow_back)).dx;
    final deleteLeft = tester.getTopLeft(find.byIcon(Icons.delete_outline)).dx;
    expect(backLeft, lessThan(deleteLeft));
  });

  testWidgets('alarm picker is scrollable on a small phone surface',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: LocalTodoRepository(),
          settings: SettingsController(),
          initialDueDate: DateTime(2026, 5, 31),
        ),
      ),
    );

    expect(find.textContaining('May 31'), findsOneWidget);
    expect(find.textContaining('2026'), findsNothing);

    await tester.tap(find.text('no alarm'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('no alarm'), findsWidgets);
    expect(find.text('start'), findsOneWidget);
    expect(find.text('before 5 min'), findsOneWidget);
    expect(find.text('before 1 hour'), findsOneWidget);
    expect(find.text('start of day'), findsOneWidget);
    expect(find.text('Custom'), findsNWidgets(3));
  });

  testWidgets('shared completion switch appears inline for shared tasks',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: LocalTodoRepository(),
          settings: SettingsController(),
        ),
      ),
    );

    expect(find.text('Both'), findsNothing);
    final privateToCategoryGap =
        tester.getTopLeft(find.text('No category')).dy -
            tester.getTopLeft(find.text('Private')).dy;

    await tester.tap(find.text('Private'));
    await tester.pump();

    expect(find.text('Shared'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Both'), findsOneWidget);
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    final sharedToCategoryGap = tester.getTopLeft(find.text('No category')).dy -
        tester.getTopLeft(find.text('Shared')).dy;
    expect(sharedToCategoryGap, closeTo(privateToCategoryGap, 1));
  });

  testWidgets('category picker can add category while editing a task',
      (tester) async {
    final repository = _CapturingTodoRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: repository,
          settings: SettingsController(),
        ),
      ),
    );

    await tester.tap(find.text('No category'));
    await tester.pumpAndSettle();

    expect(find.text('Add category'), findsOneWidget);

    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();

    expect(find.text('Category name'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Home');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Task with category');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Task'));
    await tester.pumpAndSettle();

    expect(repository.savedTask, isNotNull);
    expect(repository.savedTask!.category, 'Home');
  });

  testWidgets('saving older task as shared keeps shared sync metadata',
      (tester) async {
    final repository = _CapturingTodoRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: repository,
          settings: SettingsController(),
          task: TodoTask(
            id: 7,
            syncId: '00000000-0000-4000-8000-000000000777',
            ownerUserId: '',
            title: 'Older private task',
            visibility: SyncVisibility.privateItem,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Private'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.savedTask, isNotNull);
    expect(repository.savedTask!.visibility, SyncVisibility.shared);
    expect(repository.savedTask!.workspaceId, defaultSharedWorkspaceId);
    expect(repository.savedTask!.ownerUserId, defaultCurrentUserId);
  });

  testWidgets('due time selection uses dial wheels instead of clock picker',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: LocalTodoRepository(),
          settings: SettingsController(),
          initialDueDate: DateTime(2026, 5, 31),
        ),
      ),
    );

    await tester.tap(find.text('Add time'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    expect(find.text('Time'), findsOneWidget);
  });

  testWidgets('custom alarm input opens after closing alarm sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorScreen(
          repository: LocalTodoRepository(),
          settings: SettingsController(),
          initialDueDate: DateTime(2026, 5, 31),
        ),
      ),
    );

    await tester.tap(find.text('no alarm'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Custom').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Custom minutes'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsOneWidget);

    await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -88));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('before 15 min'), findsOneWidget);
  });
}

class _CapturingTodoRepository extends LocalTodoRepository {
  TodoTask? savedTask;

  @override
  Future<void> upsertTask(TodoTask task) async {
    savedTask = task;
  }
}
