import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/main.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/screens/login_screen.dart';
import 'package:personaltodo/screens/task_editor_screen.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/settings_store.dart';
import 'package:personaltodo/todo_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // These UI tests have no queued native widget edits.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.example.personaltodo/widget_actions'),
            (call) async => call.method == 'consumePendingWidgetActions'
                ? const <dynamic>[]
                : null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async => {
        'getWidgetData',
        'initiallyLaunchedFromHomeWidget',
      }.contains(call.method)
          ? null
          : true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget/updates'),
      (call) async => null,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget/updates'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.personaltodo/widget_actions'),
      null,
    );
  });

  testWidgets('Mac uses two-hour polls behind windows and pulls on resume',
      (tester) async {
    var syncCount = 0;
    await tester.pumpWidget(PersonalTodoApp(
      repository: _FakeAppRepository(),
      settings: _connectedSettings(),
      periodicSyncRunner: () async {
        syncCount++;
        return const TodoSyncResult(
          pushedCount: 0,
          pulledCount: 0,
          failedCount: 0,
          cursor: 'cursor',
        );
      },
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(syncCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(minutes: 119));
    expect(syncCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 1));
    expect(syncCount, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(syncCount, 3);
    await tester.pump(const Duration(seconds: 30));
    expect(syncCount, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('leaving a phone uploads a queued edit before its debounce fires',
      (tester) async {
    final repository = _FakeAppRepository(queuedItems: [
      SyncQueueItem(
        id: 1,
        entityType: 'task',
        entitySyncId: 'task',
        operation: 'upsert',
        attemptCount: 0,
        createdAt: DateTime.now(),
        nextAttemptAt: DateTime.now(),
      ),
    ]);
    var syncCount = 0;
    await tester.pumpWidget(PersonalTodoApp(
      repository: repository,
      settings: _connectedSettings(),
      periodicSyncRunner: () async {
        syncCount++;
        repository.queuedItems = [];
        return const TodoSyncResult(
          pushedCount: 1,
          pulledCount: 0,
          failedCount: 0,
          cursor: 'cursor',
        );
      },
    ));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(syncCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 1));
    expect(syncCount, 1);
    expect(repository.queuedItems, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('pulls on resume', (tester) async {
    final repository = _FakeAppRepository();
    final settings = _connectedSettings();
    var syncCount = 0;

    await tester.pumpWidget(
      PersonalTodoApp(
        repository: repository,
        settings: settings,
        periodicSyncRunner: () async {
          syncCount += 1;
          return const TodoSyncResult(
            pushedCount: 0,
            pulledCount: 0,
            failedCount: 0,
            cursor: 'cursor',
          );
        },
      ),
    );
    await tester.pump();

    expect(syncCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(repository.reloadCount, 1);
    expect(syncCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  final widgetPlatforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  });

  for (final coldStart in [true, false]) {
    testWidgets(
      'widget task navigation ${coldStart ? 'at startup' : 'while running'} opens the task without completing it',
      (tester) async {
        final task = TodoTask(
          id: 42,
          title: 'Widget task',
          note: 'Keep this note',
        );
        final repository = _FakeAppRepository(cachedTasks: [task]);
        final pending = <Map<String, Object?>>[];
        final acknowledged = <String>[];
        const action = {'id': 'navigation', 'type': 'open_task', 'taskId': 42};
        if (coldStart) pending.add(action);
        const channel = MethodChannel(
          'com.example.personaltodo/widget_actions',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'consumePendingWidgetActions') {
              final actions = pending.toList();
              pending.clear();
              return actions;
            }
            if (call.method == 'acknowledgeWidgetActions') {
              acknowledged.addAll((call.arguments as List).cast<String>());
            }
            return null;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('home_widget'),
          (call) async {
            if (call.method == 'initiallyLaunchedFromHomeWidget') {
              return coldStart
                  ? 'personaltodo://open-task?taskId=42&homeWidget=1'
                  : null;
            }
            return call.method == 'getWidgetData' ? null : true;
          },
        );

        await tester.pumpWidget(
          PersonalTodoApp(
            repository: repository,
            settings: _connectedSettings(),
            periodicSyncRunner: () async => const TodoSyncResult(
              pushedCount: 0,
              pulledCount: 0,
              failedCount: 0,
              cursor: 'cursor',
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> sendTask(int id) async {
          switch (defaultTargetPlatform) {
            case TargetPlatform.iOS:
              tester.binding.channelBuffers.push(
                'home_widget/updates',
                const StandardMethodCodec().encodeSuccessEnvelope(
                  'personaltodo://open-task?taskId=$id&homeWidget=1',
                ),
                (_) {},
              );
            case TargetPlatform.macOS:
              pending.add({...action, 'taskId': id});
              await _sendNativeWidgetMethod(
                tester,
                'widgetActionsAvailable',
                null,
              );
            default:
              await _sendNativeWidgetMethod(tester, 'widgetAction', {
                ...action,
                'taskId': id,
              });
          }
          await tester.pumpAndSettle();
        }

        if (!coldStart) {
          expect(find.byType(TaskEditorScreen), findsNothing);
          await sendTask(42);
        }
        expect(find.byType(TaskEditorScreen), findsOneWidget);
        expect(
          tester.widget<TaskEditorScreen>(find.byType(TaskEditorScreen)).task,
          same(task),
        );
        expect(find.text('Keep this note'), findsOneWidget);
        expect(task.isCompleted, isFalse);
        expect(await repository.getPendingSyncQueue(), isEmpty);
        if (defaultTargetPlatform == TargetPlatform.macOS) {
          // Navigation must be acknowledged while the editor is still open.
          expect(acknowledged, ['navigation']);
        }

        await sendTask(42);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditorScreen), findsNothing);

        await sendTask(999);
        await sendTask(-1);
        expect(find.byType(TaskEditorScreen), findsNothing);
        expect(task.isCompleted, isFalse);
        expect(await repository.getPendingSyncQueue(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: widgetPlatforms,
    );
  }

  for (final expiredAtStartup in [false, true]) {
    testWidgets(
        'opens one same-account login when session expires ${expiredAtStartup ? 'before startup' : 'while open'}',
        (tester) async {
      final task = TodoTask(
        id: 1,
        syncId: 'offline-task',
        ownerUserId: partnerUserId,
        title: 'Offline task',
      );
      final queuedChange = SyncQueueItem(
        id: 1,
        entityType: 'task',
        entitySyncId: task.syncId,
        operation: 'upsert',
        attemptCount: 0,
        createdAt: DateTime.now(),
        nextAttemptAt: DateTime.now(),
      );
      final repository = _FakeAppRepository(
        cachedTasks: [task],
        queuedItems: [queuedChange],
      );
      final settings = _connectedSettings(store: _FakeSettingsStore())
        ..currentUserId = partnerUserId;
      if (expiredAtStartup) await settings.requireReauthentication();

      await tester.pumpWidget(PersonalTodoApp(
        repository: repository,
        settings: settings,
        periodicSyncRunner: () async => const TodoSyncResult(
          pushedCount: 0,
          pulledCount: 0,
          failedCount: 0,
          cursor: 'cursor',
        ),
      ));
      await tester.pumpAndSettle();
      if (!expiredAtStartup) {
        expect(find.byType(LoginScreen), findsNothing);
        await settings.requireReauthentication();
        await tester.pumpAndSettle();
      }

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('User 2'), findsOneWidget);
      expect(find.text('User 1'), findsNothing);

      settings.notifyListeners();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(LoginScreen))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text(task.title), findsOneWidget);
      expect(repository.tasks, [task]);
      expect(await repository.getPendingSyncQueue(), [queuedChange]);
      expect(settings.initialLoginCompleted, isTrue);
      expect(settings.currentUserId, partnerUserId);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _sendNativeWidgetMethod(
  WidgetTester tester,
  String method,
  Object? arguments,
) async {
  final received = Completer<void>();
  tester.binding.channelBuffers.push(
    'com.example.personaltodo/widget_actions',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) => received.complete(),
  );
  await tester.pump();
  await received.future;
}

SettingsController _connectedSettings({SettingsStore? store}) {
  return _FakeAppSettings(store: store)
    ..initialLoginCompleted = true
    ..refreshToken = 'refresh-token';
}

class _FakeAppSettings extends SettingsController {
  _FakeAppSettings({super.store});

  @override
  Future<void> reload() async {}
}

class _FakeAppRepository extends LocalTodoRepository {
  _FakeAppRepository({
    this.cachedTasks = const [],
    this.queuedItems = const [],
  });

  int reloadCount = 0;
  final List<TodoTask> cachedTasks;
  List<SyncQueueItem> queuedItems;

  @override
  Future<int> retryFailedSyncQueueNow() async => 0;

  @override
  String get deviceId => 'test-device';

  @override
  List<TodoTask> get tasks => cachedTasks;

  @override
  TodoTask? getTask(int id) {
    for (final task in cachedTasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  @override
  List<TodoTask> get trashTasks => const [];

  @override
  Future<List<SyncQueueItem>> getPendingSyncQueue(
          {int? limit, DateTime? now, Set<String>? entityTypes}) async =>
      queuedItems;

  @override
  Future<void> reload({bool refreshNativeWidget = true}) async {
    reloadCount += 1;
    notifyListeners();
  }
}

class _FakeSettingsStore extends SettingsStore {
  @override
  Future<void> setString(String key, String value) async {}
}
