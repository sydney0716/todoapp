import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personaltodo/api/todo_api_client.dart';
import 'package:personaltodo/api/todo_api_models.dart';
import 'package:personaltodo/api/todo_api_transport.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/settings_store.dart';
import 'package:personaltodo/todo_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/todo_api_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'syncNow pushes queued tasks and advances past server-filtered own events',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_sync_service_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 0,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.upsertTask(TodoTask(title: 'Sync me'));
    final queue = await repository.getPendingSyncQueue();
    final record =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '1',
        'accepted': [record],
        'rejected': <Object?>[],
      }),
      jsonResponse({
        'cursor': '1',
        'changes': <Object?>[],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pushedCount, 1);
    expect(result.pulledCount, 0);
    expect(result.failedCount, 0);
    expect(result.cursor, '1');
    expect(settings.lastSyncCursor, '1');
    expect(await _syncQueueCount(repository), 0);
    expect(repository.tasks.single.title, 'Sync me');
    expect(repository.tasks.single.syncStatus, SyncStatus.synced);
    expect(repository.tasks.single.lastSyncedAt, isNotNull);
    expect(transport.requests, hasLength(2));
    expect(transport.requests[0].method, 'POST');
    expect(transport.requests[0].uri.path, '/sync/tasks');
    expect(
        transport.requests[0].headers['Authorization'], 'Bearer access-token');
    expect(transport.requests[1].method, 'GET');
    expect(transport.requests[1].uri.queryParameters['cursor'], '0');
  });

  test('syncNow can reconcile a stale local snapshot after empty pull',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_sync_reconcile_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'hoyoung',
      cursor: '10',
      taskCount: 0,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    final remoteTask = TodoTask(
      syncId: '11111111-1111-4111-8111-111111111111',
      ownerUserId: defaultCurrentUserId,
      createdByUserId: defaultCurrentUserId,
      updatedByUserId: defaultCurrentUserId,
      title: 'Server only task',
      createdAt: DateTime.utc(2026, 8),
      updatedAt: DateTime.utc(2026, 8, 1),
      version: 1,
      syncStatus: SyncStatus.synced,
      deviceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '10',
        'changes': <Object?>[],
      }),
      jsonResponse({
        'cursor': '12',
        'tasks': [_taskRecord(remoteTask)],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow(reconcileSnapshot: true);

    expect(result.pushedCount, 0);
    expect(result.pulledCount, 0);
    expect(result.failedCount, 0);
    expect(result.snapshotReconciled, isTrue);
    expect(result.cursor, '12');
    expect(settings.lastSyncCursor, '12');
    expect(repository.tasks.single.title, 'Server only task');
    expect(transport.requests, hasLength(2));
    expect(transport.requests[0].uri.path, '/sync/tasks');
    expect(transport.requests[0].uri.queryParameters['cursor'], '10');
    expect(transport.requests[1].uri.path, '/sync/bootstrap');
  });

  test('syncNow does not share in-flight work across repositories', () async {
    final firstTempDir =
        await Directory.systemTemp.createTemp('personaltodo_sync_scope_1_');
    final secondTempDir =
        await Directory.systemTemp.createTemp('personaltodo_sync_scope_2_');
    final firstRepository = LocalTodoRepository(
      databasePath: path.join(firstTempDir.path, 'personal_todo.db'),
    );
    final secondRepository = LocalTodoRepository(
      databasePath: path.join(secondTempDir.path, 'personal_todo.db'),
    );
    final firstSettings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(firstTempDir.path, 'settings.db'),
      ),
    );
    final secondSettings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(secondTempDir.path, 'settings.db'),
      ),
    );

    await firstSettings.init();
    await secondSettings.init();
    await firstRepository.init();
    await secondRepository.init();
    addTearDown(() async {
      await firstSettings.close();
      await secondSettings.close();
      await firstRepository.close();
      await secondRepository.close();
      await firstTempDir.delete(recursive: true);
      await secondTempDir.delete(recursive: true);
    });

    await firstSettings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 0,
      session: AuthSession(
        accessToken: 'first-access-token',
        refreshToken: 'first-refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: firstRepository.deviceId,
      ),
    );
    await secondSettings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 0,
      session: AuthSession(
        accessToken: 'second-access-token',
        refreshToken: 'second-refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: secondRepository.deviceId,
      ),
    );

    final firstTransport = _PausingTodoApiTransport();
    final secondTransport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '2',
        'changes': <Object?>[],
      }),
    ]);
    final firstService = TodoSyncService(
      repository: firstRepository,
      settings: firstSettings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: firstTransport,
      ),
    );
    final secondService = TodoSyncService(
      repository: secondRepository,
      settings: secondSettings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: secondTransport,
      ),
    );

    final firstSync = firstService.syncNow();
    await firstTransport.sent.future;

    final secondResult = await secondService.syncNow();
    expect(secondResult.cursor, '2');
    expect(secondTransport.requests, hasLength(1));

    firstTransport.complete(
      jsonResponse({
        'cursor': '1',
        'changes': <Object?>[],
      }),
    );
    final firstResult = await firstSync;
    expect(firstResult.cursor, '1');
    expect(firstTransport.requests, hasLength(1));
  });

  test('syncNow batches queued task pushes into one request', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_sync_batch_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 0,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.upsertTask(TodoTask(title: 'First queued task'));
    await repository.upsertTask(TodoTask(title: 'Second queued task'));
    final queue = await repository.getPendingSyncQueue(entityTypes: {'task'});
    final records = queue
        .map((item) => jsonDecode(item.payloadJson!) as Map<String, Object?>)
        .toList(growable: false);
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '2',
        'accepted': records,
        'rejected': <Object?>[],
      }),
      jsonResponse({
        'cursor': '2',
        'changes': <Object?>[],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pushedCount, 2);
    expect(result.failedCount, 0);
    expect(await _syncQueueCount(repository), 0);
    expect(transport.requests, hasLength(2));
    expect(transport.requests[0].method, 'POST');
    final pushBody =
        jsonDecode(transport.requests[0].body!) as Map<String, Object?>;
    expect(pushBody['changes'], hasLength(2));
    expect(transport.requests[1].method, 'GET');
  });

  test('syncNow preserves subtask due dates from push acknowledgements',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_subtask_due_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 0,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    final dueAt = DateTime.utc(2026, 6, 10);
    await repository.upsertTask(
      TodoTask(
        title: 'Task with subtask due date',
        subTasks: [
          SubTask(title: 'Subtask with due date', dueDateTime: dueAt),
        ],
      ),
    );
    final queue = await repository.getPendingSyncQueue(entityTypes: {'task'});
    final record =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    final subtaskRecord =
        (record['subtasks'] as List<Object?>).single as Map<String, Object?>;
    expect(subtaskRecord['due_at'], dueAt.toIso8601String());
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '1',
        'accepted': [record],
        'rejected': <Object?>[],
      }),
      jsonResponse({
        'cursor': '1',
        'changes': <Object?>[],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    await service.syncNow();

    expect(
      repository
          .tasks.single.subTasks.single.dueDateTime?.millisecondsSinceEpoch,
      dueAt.millisecondsSinceEpoch,
    );
    expect(await _syncQueueCount(repository), 0);
  });

  test('syncNow does not prune subtasks from partial push acknowledgement',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_partial_ack_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 1,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.upsertTask(
      TodoTask(
        title: 'Pick up groceries',
        subTasks: [
          SubTask(title: 'Produce'),
          SubTask(title: 'Milk'),
          SubTask(title: 'Eggs'),
        ],
      ),
    );
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    final syncedTask = repository.tasks.single;
    await repository.upsertTask(
      syncedTask.copyWith(
        subTasks: [
          syncedTask.subTasks[0].copyWith(isCompleted: true),
          syncedTask.subTasks[1],
          syncedTask.subTasks[2],
        ],
      ),
    );
    queue = await repository.getPendingSyncQueue();
    final partialRecord =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    final partialSubTasks = partialRecord['subtasks'] as List<Object?>;
    expect(partialSubTasks, hasLength(1));

    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '1',
        'accepted': [partialRecord],
        'rejected': <Object?>[],
      }),
      jsonResponse({
        'cursor': '1',
        'changes': <Object?>[],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pushedCount, 1);
    expect(result.pulledCount, 0);
    expect(result.failedCount, 0);
    expect(repository.tasks.single.subTasks, hasLength(3));
    expect(repository.tasks.single.subTasks.map((subTask) => subTask.title),
        ['Produce', 'Milk', 'Eggs']);
    expect(repository.tasks.single.subTasks[0].isCompleted, isTrue);
    expect(repository.tasks.single.subTasks[1].isCompleted, isFalse);
    expect(repository.tasks.single.subTasks[2].isCompleted, isFalse);
    final pushBody =
        jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
    final changes = pushBody['changes'] as List<Object?>;
    expect(
      (changes.single as Map<String, Object?>)['changed_task_fields'],
      isEmpty,
    );
  });

  test('syncNow clears accepted no-op task queue rows', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_noop_queue_');
    final databasePath = path.join(tempDir.path, 'personal_todo.db');
    var repository = LocalTodoRepository(databasePath: databasePath);
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 1,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.upsertTask(TodoTask(title: 'Already synced'));
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);
    final syncedTask = repository.tasks.single;
    final noOpRecord = _taskRecord(syncedTask.copyWith(subTasks: const []));

    await repository.close();
    final db = await databaseFactory.openDatabase(databasePath);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('sync_queue', {
      'entityType': 'task',
      'entitySyncId': syncedTask.syncId,
      'operation': 'upsert',
      'payloadJson': jsonEncode(noOpRecord),
      'createdAt': now,
      'nextAttemptAt': now,
    });
    await db.close();

    repository = LocalTodoRepository(databasePath: databasePath);
    await repository.init();
    queue = await repository.getPendingSyncQueue();
    expect(queue, hasLength(1));

    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '0',
        'accepted': [noOpRecord],
        'rejected': <Object?>[],
      }),
      jsonResponse({
        'cursor': '0',
        'changes': <Object?>[],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pushedCount, 1);
    expect(result.failedCount, 0);
    expect(await _syncQueueCount(repository), 0);
    expect(repository.tasks.single.syncStatus, SyncStatus.synced);
  });

  test('syncNow merges pulled partial subtask changes without pruning siblings',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_partial_pull_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 1,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.reconcileBootstrapTasks([
      TodoTask(
        syncId: '11111111-1111-4111-8111-111111111111',
        ownerUserId: defaultCurrentUserId,
        createdByUserId: defaultCurrentUserId,
        updatedByUserId: defaultCurrentUserId,
        title: 'Pick up groceries',
        note: 'Restock basics for the week',
        category: 'Home',
        createdAt: DateTime.utc(2026, 6, 5),
        updatedAt: DateTime.utc(2026, 6, 5, 1),
        version: 1,
        syncStatus: SyncStatus.synced,
        deviceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        subTasks: [
          SubTask(
            syncId: '22222222-2222-4222-8222-222222222222',
            taskSyncId: '11111111-1111-4111-8111-111111111111',
            title: 'Buy fruit',
            createdAt: DateTime.utc(2026, 6, 5),
            updatedAt: DateTime.utc(2026, 6, 5, 1),
            version: 1,
            syncStatus: SyncStatus.synced,
          ),
          SubTask(
            syncId: '33333333-3333-4333-8333-333333333333',
            taskSyncId: '11111111-1111-4111-8111-111111111111',
            title: 'Buy milk',
            createdAt: DateTime.utc(2026, 6, 5),
            updatedAt: DateTime.utc(2026, 6, 5, 1),
            version: 1,
            syncStatus: SyncStatus.synced,
          ),
          SubTask(
            syncId: '44444444-4444-4444-8444-444444444444',
            taskSyncId: '11111111-1111-4111-8111-111111111111',
            title: 'Buy eggs',
            createdAt: DateTime.utc(2026, 6, 5),
            updatedAt: DateTime.utc(2026, 6, 5, 1),
            version: 1,
            syncStatus: SyncStatus.synced,
          ),
        ],
      ),
    ]);

    final partialRecord = _taskRecord(
      repository.tasks.single.copyWith(
        updatedAt: DateTime.utc(2026, 6, 5, 2),
        subTasks: [
          repository.tasks.single.subTasks.first.copyWith(
            isCompleted: true,
            updatedAt: DateTime.utc(2026, 6, 5, 2),
            version: 2,
          ),
        ],
      ),
    );
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '1',
        'changes': [
          {
            'operation': 'upsert',
            'event_id': 1,
            'origin_device_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'changed_task_fields': <Object?>[],
            'changed_subtask_ids': [
              repository.tasks.single.subTasks.first.syncId,
            ],
            'record': partialRecord,
          },
        ],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pushedCount, 0);
    expect(result.pulledCount, 1);
    expect(result.failedCount, 0);
    expect(repository.tasks, hasLength(1));
    expect(repository.tasks.single.subTasks, hasLength(3));
    expect(repository.tasks.single.subTasks.map((subTask) => subTask.title), [
      'Buy fruit',
      'Buy milk',
      'Buy eggs',
    ]);
    expect(repository.tasks.single.subTasks[0].isCompleted, isTrue);
    expect(repository.tasks.single.subTasks[1].isCompleted, isFalse);
    expect(repository.tasks.single.subTasks[2].isCompleted, isFalse);
  });

  test('syncNow applies pulled subtask while preserving pending parent edit',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_pending_merge_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 1,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.reconcileBootstrapTasks([
      TodoTask(
        syncId: '11111111-1111-4111-8111-111111111111',
        ownerUserId: defaultCurrentUserId,
        createdByUserId: defaultCurrentUserId,
        updatedByUserId: defaultCurrentUserId,
        title: 'Pick up groceries',
        note: 'Restock basics for the week',
        category: 'Home',
        createdAt: DateTime.utc(2026, 6, 5),
        updatedAt: DateTime.utc(2026, 6, 5, 1),
        version: 1,
        syncStatus: SyncStatus.synced,
        deviceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        subTasks: [
          SubTask(
            syncId: '22222222-2222-4222-8222-222222222222',
            taskSyncId: '11111111-1111-4111-8111-111111111111',
            title: 'Buy fruit',
            createdAt: DateTime.utc(2026, 6, 5),
            updatedAt: DateTime.utc(2026, 6, 5, 1),
            version: 1,
            syncStatus: SyncStatus.synced,
          ),
          SubTask(
            syncId: '33333333-3333-4333-8333-333333333333',
            taskSyncId: '11111111-1111-4111-8111-111111111111',
            title: 'Buy milk',
            createdAt: DateTime.utc(2026, 6, 5),
            updatedAt: DateTime.utc(2026, 6, 5, 1),
            version: 1,
            syncStatus: SyncStatus.synced,
          ),
          SubTask(
            syncId: '44444444-4444-4444-8444-444444444444',
            taskSyncId: '11111111-1111-4111-8111-111111111111',
            title: 'Buy eggs',
            createdAt: DateTime.utc(2026, 6, 5),
            updatedAt: DateTime.utc(2026, 6, 5, 1),
            version: 1,
            syncStatus: SyncStatus.synced,
          ),
        ],
      ),
    ]);

    final syncedTask = repository.tasks.single;
    await repository.upsertTask(
      syncedTask.copyWith(title: 'Local pending grocery title'),
    );
    final queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemFailed(
      queue.single.id,
      'retry later',
      nextAttemptAt: DateTime.now().add(const Duration(hours: 1)),
    );

    final remoteTask = syncedTask.copyWith(
      updatedAt: DateTime.utc(2026, 6, 5, 2),
      subTasks: [
        syncedTask.subTasks.first.copyWith(
          isCompleted: true,
          updatedAt: DateTime.utc(2026, 6, 5, 2),
          version: 2,
        ),
      ],
    );
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '1',
        'changes': [
          {
            'operation': 'upsert',
            'event_id': 1,
            'origin_device_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'changed_task_fields': <Object?>[],
            'changed_subtask_ids': [syncedTask.subTasks.first.syncId],
            'record': _taskRecord(remoteTask),
          },
        ],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pushedCount, 0);
    expect(result.pulledCount, 1);
    expect(repository.tasks, hasLength(1));
    expect(repository.tasks.single.title, 'Local pending grocery title');
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    expect(repository.tasks.single.subTasks, hasLength(3));
    expect(repository.tasks.single.subTasks[0].isCompleted, isTrue);
    expect(repository.tasks.single.subTasks[1].isCompleted, isFalse);
    expect(repository.tasks.single.subTasks[2].isCompleted, isFalse);
    expect(await _syncQueueCount(repository), 1);
  });

  test('syncNow pushes permanent delete purge changes', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_sync_purge_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 0,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.upsertTask(TodoTask(title: 'Delete everywhere'));
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);
    await repository.moveTaskToTrash(repository.tasks.single);
    queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    final deletedTask = repository.trashTasks.single;
    expect(await repository.permanentlyDeleteTask(deletedTask), isTrue);
    queue = await repository.getPendingSyncQueue();
    expect(queue.single.operation, 'purge');
    final record =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '2',
        'accepted': [record],
        'rejected': <Object?>[],
      }),
      jsonResponse({
        'cursor': '2',
        'changes': <Object?>[],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pushedCount, 1);
    expect(result.failedCount, 0);
    expect(await _syncQueueCount(repository), 0);
    final pushBody =
        jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
    final changes = pushBody['changes'] as List<Object?>;
    expect((changes.single as Map<String, Object?>)['operation'], 'purge');
  });

  test('syncNow applies pulled purge changes locally', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_pull_purge_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );
    final settings = SettingsController(
      store: SettingsStore(
        databasePath: path.join(tempDir.path, 'settings.db'),
      ),
    );

    await settings.init();
    await repository.init();
    addTearDown(() async {
      await settings.close();
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '0',
      taskCount: 1,
      session: AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: repository.deviceId,
      ),
    );
    await repository.reconcileBootstrapTasks([
      TodoTask(
        syncId: '44444444-4444-4444-8444-444444444444',
        ownerUserId: defaultCurrentUserId,
        createdByUserId: defaultCurrentUserId,
        updatedByUserId: defaultCurrentUserId,
        title: 'Removed somewhere else',
        createdAt: DateTime.utc(2026, 6, 5),
        updatedAt: DateTime.utc(2026, 6, 5, 1),
        version: 1,
        syncStatus: SyncStatus.synced,
        deviceId: repository.deviceId,
      ),
    ]);
    final record = {
      'id': '44444444-4444-4444-8444-444444444444',
      'owner_user_id': defaultCurrentUserId,
      'visibility': 'private',
      'workspace_id': null,
      'title': 'Removed somewhere else',
      'note': '',
      'category': '',
      'is_completed': false,
      'due_at': null,
      'reminder_option': 'none',
      'reminder_value': null,
      'created_at': DateTime.utc(2026, 6, 5).toIso8601String(),
      'updated_at': DateTime.utc(2026, 6, 5, 1).toIso8601String(),
      'version': 1,
      'deleted_at': null,
      'purge_after': null,
      'created_by_user_id': defaultCurrentUserId,
      'updated_by_user_id': defaultCurrentUserId,
      'device_id': repository.deviceId,
      'subtasks': <Object?>[],
    };
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '5',
        'changes': [
          {'operation': 'purge', 'record': record},
        ],
      }),
    ]);
    final service = TodoSyncService(
      repository: repository,
      settings: settings,
      clientFactory: (baseUrl) => TodoApiClient(
        baseUrl: baseUrl,
        transport: transport,
      ),
    );

    final result = await service.syncNow();

    expect(result.pulledCount, 1);
    expect(repository.tasks, isEmpty);
    expect(repository.trashTasks, isEmpty);
    expect(await _syncQueueCount(repository), 0);
    expect(settings.lastSyncCursor, '5');
  });
}

Future<int> _syncQueueCount(LocalTodoRepository repository) async {
  return (await repository.getPendingSyncSummary()).pendingCount;
}

Map<String, Object?> _taskRecord(TodoTask task) {
  return {
    'id': task.syncId,
    'owner_user_id': task.ownerUserId,
    'visibility': task.visibility.storedValue,
    'workspace_id': task.workspaceId,
    'title': task.title,
    'note': task.note,
    'category': task.category,
    'is_completed': task.isCompleted,
    'shared_completion_mode': task.sharedCompletionMode.storedValue,
    'completed_by_user_ids': task.completedByUserIds,
    'due_at': task.dueDateTime?.toIso8601String(),
    'reminder_option': task.reminderOption.storedValue,
    'reminder_value': task.reminderValue,
    'created_at': task.createdAt.toIso8601String(),
    'updated_at': task.updatedAt.toIso8601String(),
    'version': task.version,
    'deleted_at': task.deletedAt?.toIso8601String(),
    'purge_after': task.purgeAfter?.toIso8601String(),
    'created_by_user_id': task.createdByUserId,
    'updated_by_user_id': task.updatedByUserId,
    'device_id': task.deviceId,
    'subtasks': task.subTasks.map(_subTaskRecord).toList(),
  };
}

Map<String, Object?> _subTaskRecord(SubTask subTask) {
  return {
    'id': subTask.syncId,
    'task_id': subTask.taskSyncId,
    'title': subTask.title,
    'is_completed': subTask.isCompleted,
    'due_at': subTask.dueDateTime?.toIso8601String(),
    'position': 0,
    'updated_at': (subTask.updatedAt ?? subTask.createdAt).toIso8601String(),
    'version': subTask.version,
    'deleted_at': subTask.deletedAt?.toIso8601String(),
  };
}

class _PausingTodoApiTransport implements TodoApiTransport {
  final List<TodoApiRequest> requests = [];
  final Completer<void> sent = Completer<void>();
  final Completer<TodoApiResponse> _response = Completer<TodoApiResponse>();

  @override
  Future<TodoApiResponse> send(TodoApiRequest request) {
    requests.add(request);
    if (!sent.isCompleted) {
      sent.complete();
    }
    return _response.future;
  }

  void complete(TodoApiResponse response) {
    if (!_response.isCompleted) {
      _response.complete(response);
    }
  }

  @override
  void close() {}
}
