import 'helpers/repository_test_helpers.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:personaltodo/api/todo_api_client.dart';
import 'package:personaltodo/api/todo_api_models.dart';
import 'package:personaltodo/api/todo_api_transport.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/settings_store.dart';
import 'package:personaltodo/todo_sync_service.dart';
import 'helpers/todo_api_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('successful push followed by old partner event preserves latest title',
      () async {
    final dir = await Directory.systemTemp.createTemp('todo_sync_audit_');
    final repo = LocalTodoRepository(databasePath: '${dir.path}/tasks.db');
    final settings = SettingsController(
        store: SettingsStore(databasePath: '${dir.path}/settings.db'));
    await repo.init();
    await settings.init();
    addTearDown(() async {
      await settings.close();
      await repo.close();
      await dir.delete(recursive: true);
    });
    await settings.recordServerConnectionSuccess(
        username: 'user1',
        cursor: '1',
        taskCount: 0,
        session: AuthSession(
            accessToken: 'access',
            refreshToken: 'refresh',
            tokenType: 'bearer',
            userId: defaultCurrentUserId,
            deviceId: repo.deviceId));
    await repo.upsertTask(TodoTask(title: 'Baseline'));
    await acknowledgeLocalQueueItem(
        repo, (await repo.getPendingSyncQueue()).single.id);
    await repo.upsertTask(
        repo.tasks.single.copyWith(title: 'Latest local accepted title'));
    final payload =
        jsonDecode((await repo.getPendingSyncQueue()).single.payloadJson!)
            as Map<String, Object?>;
    final accepted = {...payload, 'version': 3};
    final older = {
      ...payload,
      'title': 'Older partner title',
      'version': 2,
      'device_id': '10000000-0000-4000-8000-000000000002'
    };
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '3',
        'accepted': [accepted],
        'rejected': <String>[]
      }),
      jsonResponse({
        'cursor': '3',
        'changes': [
          {
            'operation': 'upsert',
            'record': older,
            'event_id': 2,
            'origin_device_id': older['device_id'],
            'changed_task_fields': ['title'],
            'changed_subtask_ids': <String>[]
          }
        ]
      }),
    ]);
    final result = await TodoSyncService(
        repository: repo,
        settings: settings,
        clientFactory: (url) =>
            TodoApiClient(baseUrl: url, transport: transport)).syncNow();
    expect(result.failedCount, 0);
    expect(repo.tasks.single.title, 'Latest local accepted title');
    expect((await repo.getPendingSyncQueue()), isEmpty);
    expect(settings.lastSyncCursor, '3');
  });
  test('expired refresh preserves offline data and provides a reconnect state',
      () async {
    final dir = await Directory.systemTemp.createTemp('todo_auth_recovery_');
    final repo = LocalTodoRepository(databasePath: '${dir.path}/tasks.db');
    final settings = SettingsController(
        store: SettingsStore(databasePath: '${dir.path}/settings.db'));
    await repo.init();
    await settings.init();
    addTearDown(() async {
      await settings.close();
      await repo.close();
      await dir.delete(recursive: true);
    });
    await settings.recordServerConnectionSuccess(
        username: 'user1',
        cursor: '1',
        taskCount: 0,
        session: AuthSession(
            accessToken: 'expired',
            refreshToken: 'expired-refresh',
            tokenType: 'bearer',
            userId: defaultCurrentUserId,
            deviceId: repo.deviceId));
    await repo.upsertTask(TodoTask(title: 'Keep my offline work'));
    await repo.markSyncQueueItemFailed(
        (await repo.getPendingSyncQueue()).single.id, 'offline',
        nextAttemptAt: DateTime.now().add(const Duration(hours: 1)));
    final transport = FakeTodoApiTransport([
      const TodoApiResponse(
          statusCode: 401, headers: {}, body: '{"detail":"expired"}'),
      const TodoApiResponse(
          statusCode: 401, headers: {}, body: '{"detail":"expired refresh"}'),
    ]);
    await expectLater(
        TodoSyncService(
            repository: repo,
            settings: settings,
            clientFactory: (url) =>
                TodoApiClient(baseUrl: url, transport: transport)).syncNow(),
        throwsA(isA<TodoSyncException>()));
    expect(repo.tasks.single.title, 'Keep my offline work');
    expect(await repo.getPendingSyncQueue(), hasLength(1));
    expect(settings.initialLoginCompleted, isTrue);
    expect(settings.refreshToken, isEmpty);
  });
  test('pull follows pages even when every event in a page is filtered out',
      () async {
    final dir = await Directory.systemTemp.createTemp('todo_pull_pages_');
    final repo = LocalTodoRepository(databasePath: '${dir.path}/tasks.db');
    final settings = SettingsController(
        store: SettingsStore(databasePath: '${dir.path}/settings.db'));
    await repo.init();
    await settings.init();
    addTearDown(() async {
      await settings.close();
      await repo.close();
      await dir.delete(recursive: true);
    });
    await settings.recordServerConnectionSuccess(
        username: 'user1',
        cursor: '0',
        taskCount: 0,
        session: AuthSession(
            accessToken: 'access',
            refreshToken: 'refresh',
            tokenType: 'bearer',
            userId: defaultCurrentUserId,
            deviceId: repo.deviceId));
    final transport = FakeTodoApiTransport([
      jsonResponse({'cursor': '500', 'changes': [], 'has_more': true}),
      jsonResponse({'cursor': '501', 'changes': [], 'has_more': false}),
    ]);
    await TodoSyncService(
        repository: repo,
        settings: settings,
        clientFactory: (url) =>
            TodoApiClient(baseUrl: url, transport: transport)).syncNow();
    expect(settings.lastSyncCursor, '501');
    expect(transport.requests.map((r) => r.uri.queryParameters['cursor']),
        ['0', '500']);
  });
}
