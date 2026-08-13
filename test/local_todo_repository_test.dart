import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('writes, reads, updates, and deletes tasks with subtasks', () async {
    final tempDir = await Directory.systemTemp.createTemp('personaltodo_test_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(
        title: 'Smoke test task',
        dueDateTime: DateTime(2026, 5, 30, 9, 15),
        reminderOption: TaskReminderOption.beforeMinutes,
        reminderValue: 30,
        subTasks: [
          SubTask(
            title: 'First step',
            dueDateTime: DateTime(2026, 5, 30),
          ),
          SubTask(title: 'Second step', isCompleted: true),
        ],
      ),
    );

    expect(repository.tasks.length, 1);
    expect(repository.tasks.single.title, 'Smoke test task');
    expect(repository.tasks.single.subTasks, hasLength(2));
    expect(repository.tasks.single.syncId, isNotEmpty);
    expect(repository.tasks.single.ownerUserId, defaultCurrentUserId);
    expect(repository.tasks.single.visibility, SyncVisibility.privateItem);
    expect(
      repository.tasks.single.reminderOption,
      TaskReminderOption.beforeMinutes,
    );
    expect(repository.tasks.single.reminderValue, 30);
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    expect(repository.tasks.single.deviceId, repository.deviceId);
    expect(repository.tasks.single.subTasks.first.syncId, isNotEmpty);
    expect(repository.tasks.single.subTasks.first.taskSyncId,
        repository.tasks.single.syncId);
    expect(
      repository.tasks.single.subTasks.first.dueDateTime,
      DateTime(2026, 5, 30),
    );
    expect(await _syncQueueCount(repository), 1);
    final initialQueue = await repository.getPendingSyncQueue();
    final initialPayload =
        jsonDecode(initialQueue.single.payloadJson!) as Map<String, Object?>;
    expect(initialPayload['id'], repository.tasks.single.syncId);
    expect(initialPayload.containsKey('sync_id'), isFalse);
    expect(initialPayload.containsKey('due_date_time'), isFalse);
    expect(initialPayload['due_at'], isA<String>());
    expect(initialPayload['reminder_option'], 'before_minutes');
    expect(initialPayload['reminder_value'], 30);
    expect(initialPayload['owner_user_id'], defaultCurrentUserId);
    expect(initialPayload['device_id'], repository.deviceId);
    final subTaskPayloads = initialPayload['subtasks'] as List<Object?>;
    expect(subTaskPayloads, hasLength(2));
    final firstSubTaskPayload = subTaskPayloads.first as Map<String, Object?>;
    expect(firstSubTaskPayload['id'],
        repository.tasks.single.subTasks.first.syncId);
    expect(firstSubTaskPayload['task_id'], repository.tasks.single.syncId);
    expect(firstSubTaskPayload['due_at'], isA<String>());
    expect(firstSubTaskPayload.containsKey('sync_id'), isFalse);

    final savedTask = repository.tasks.single;
    final originalTaskSyncId = savedTask.syncId;
    final originalSubTaskSyncId = savedTask.subTasks.first.syncId;
    final originalVersion = savedTask.version;
    await repository.upsertTask(
      savedTask.copyWith(
        title: 'Updated task',
        isCompleted: true,
        updatedAt: DateTime.now(),
      ),
    );

    expect(repository.tasks.single.title, 'Updated task');
    expect(repository.tasks.single.isCompleted, isTrue);
    expect(repository.tasks.single.version, originalVersion + 1);
    expect(await _syncQueueCount(repository), 1);

    await repository.upsertTask(
      TodoTask(
        id: repository.tasks.single.id,
        title: 'Defensive metadata update',
        subTasks: [
          SubTask(
            id: repository.tasks.single.subTasks.first.id,
            title: 'First step carried forward',
          ),
        ],
      ),
    );

    expect(repository.tasks.single.syncId, originalTaskSyncId);
    expect(
        repository.tasks.single.subTasks.single.syncId, originalSubTaskSyncId);
    expect(await _syncQueueCount(repository), 1);
    final queueAfterSubtaskDelete = await repository.getPendingSyncQueue();
    expect(queueAfterSubtaskDelete.single.entityType, 'task');
    final taskPayloadAfterSubtaskDelete =
        jsonDecode(queueAfterSubtaskDelete.single.payloadJson!)
            as Map<String, Object?>;
    final changedSubTasks =
        taskPayloadAfterSubtaskDelete['subtasks'] as List<Object?>;
    expect(
      changedSubTasks.any(
        (subTask) => (subTask as Map<String, Object?>)['deleted_at'] != null,
      ),
      isTrue,
    );

    await repository.moveTaskToTrash(repository.tasks.single);
    expect(repository.tasks.length, 0);
    expect(repository.tasks, isEmpty);
    expect(repository.trashTasks.single.title, 'Defensive metadata update');
    expect(repository.trashTasks.single.deletedAt, isNotNull);
    expect(repository.trashTasks.single.purgeAfter, isNotNull);
    expect(await _syncQueueCount(repository), 1);

    await repository.restoreTaskFromTrash(repository.trashTasks.single);
    expect(repository.tasks.length, 1);
    expect(repository.trashTasks, isEmpty);
    expect(repository.tasks.single.deletedAt, isNull);
    expect(await _syncQueueCount(repository), 1);
  });

  test('sync acknowledgements gate permanent delete', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_sync_ack_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(TodoTask(title: 'Synced task'));
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    expect(repository.tasks.single.syncStatus, SyncStatus.synced);
    expect(repository.tasks.single.lastSyncedAt, isNotNull);
    expect(await _syncQueueCount(repository), 0);

    await repository.moveTaskToTrash(repository.tasks.single);
    expect(repository.trashTasks.single.syncStatus, SyncStatus.pending);
    expect(
      repository.canPermanentlyDeleteTask(repository.trashTasks.single),
      isFalse,
    );
    expect(
      await repository.permanentlyDeleteTask(repository.trashTasks.single),
      isFalse,
    );
    expect(repository.trashTasks, isNotEmpty);

    queue = await repository.getPendingSyncQueue();
    expect(queue.single.operation, 'delete');
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    expect(repository.trashTasks.single.syncStatus, SyncStatus.synced);
    expect(
      repository.canPermanentlyDeleteTask(repository.trashTasks.single),
      isFalse,
    );
    expect(
      repository.canPermanentlyDeleteTask(
        repository.trashTasks.single,
        now: repository.trashTasks.single.purgeAfter!.add(
          const Duration(milliseconds: 1),
        ),
      ),
      isTrue,
    );
    expect(
      await repository.permanentlyDeleteTask(
        repository.trashTasks.single,
        now: repository.trashTasks.single.purgeAfter!.add(
          const Duration(milliseconds: 1),
        ),
      ),
      isTrue,
    );

    expect(repository.trashTasks, isEmpty);
    queue = await repository.getPendingSyncQueue();
    expect(queue.single.operation, 'purge');
    final payload =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    expect(payload['title'], 'Synced task');
    expect(payload['deleted_at'], isA<String>());
    expect(payload['owner_user_id'], defaultCurrentUserId);
    expect(payload['device_id'], repository.deviceId);
  });

  test('shared both completion waits for both users', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_shared_both_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(
        title: 'Shared both task',
        visibility: SyncVisibility.shared,
        workspaceId: defaultSharedWorkspaceId,
        sharedCompletionMode: SharedCompletionMode.both,
      ),
    );
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    expect(
        await repository.markTaskDoneById(repository.tasks.single.id), isTrue);
    expect(repository.tasks.single.isCompleted, isFalse);
    expect(repository.tasks.single.isPartiallyCompleted, isTrue);
    expect(repository.tasks.single.completedByUserIds, [defaultCurrentUserId]);

    queue = await repository.getPendingSyncQueue();
    var payload = jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    expect(payload['_changed_task_fields'], ['completed_by_user_ids']);
    expect(payload['shared_completion_mode'], 'both');
    expect(payload['completed_by_user_ids'], [defaultCurrentUserId]);
    expect(payload['is_completed'], isFalse);
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    repository.currentUserId = partnerUserId;
    expect(
        await repository.markTaskDoneById(repository.tasks.single.id), isTrue);
    expect(repository.tasks.single.isCompleted, isTrue);
    expect(repository.tasks.single.isPartiallyCompleted, isFalse);
    expect(repository.tasks.single.completedByUserIds, [
      defaultCurrentUserId,
      partnerUserId,
    ]);

    queue = await repository.getPendingSyncQueue();
    payload = jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    expect(payload['_changed_task_fields'], [
      'completed_by_user_ids',
      'is_completed',
    ]);
    expect(payload['completed_by_user_ids'], [
      defaultCurrentUserId,
      partnerUserId,
    ]);
    expect(payload['is_completed'], isTrue);
  });

  test('filters private tasks by active local user', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_owner_filter_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.reconcileBootstrapTasks([
      _remoteTask(
        syncId: '11111111-1111-4111-8111-111111111111',
        ownerUserId: defaultCurrentUserId,
        title: 'Mine',
      ),
      _remoteTask(
        syncId: '22222222-2222-4222-8222-222222222222',
        ownerUserId: partnerUserId,
        title: 'Partner private',
      ),
      _remoteTask(
        syncId: '33333333-3333-4333-8333-333333333333',
        ownerUserId: partnerUserId,
        title: 'Shared',
        visibility: SyncVisibility.shared,
        workspaceId: defaultSharedWorkspaceId,
      ),
    ]);

    expect(repository.tasks.map((task) => task.title), ['Mine', 'Shared']);

    repository.currentUserId = partnerUserId;
    await repository.reload();

    expect(
      repository.tasks.map((task) => task.title),
      ['Partner private', 'Shared'],
    );
  });

  test('shared both completion can be toggled back by same user', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_shared_toggle_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(
        title: 'Shared both task',
        visibility: SyncVisibility.shared,
        workspaceId: defaultSharedWorkspaceId,
        sharedCompletionMode: SharedCompletionMode.both,
      ),
    );
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    final taskId = repository.tasks.single.id;
    expect(await repository.markTaskDoneById(taskId), isTrue);
    expect(repository.tasks.single.isPartiallyCompleted, isTrue);
    expect(repository.tasks.single.completedByUserIds, [defaultCurrentUserId]);
    queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    expect(await repository.toggleSharedTaskCompletionById(taskId), isTrue);
    expect(repository.tasks.single.isCompleted, isFalse);
    expect(repository.tasks.single.isPartiallyCompleted, isFalse);
    expect(repository.tasks.single.completedByUserIds, isEmpty);

    queue = await repository.getPendingSyncQueue();
    final payload =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    expect(payload['_changed_task_fields'], ['completed_by_user_ids']);
    expect(payload['completed_by_user_ids'], isEmpty);
    expect(payload['is_completed'], isFalse);
  });

  test('moves expired completed tasks to trash using completed retention',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_completed_ttl_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.reconcileBootstrapTasks([
      TodoTask(
        syncId: '11111111-1111-4111-8111-111111111111',
        ownerUserId: defaultCurrentUserId,
        createdByUserId: defaultCurrentUserId,
        updatedByUserId: defaultCurrentUserId,
        title: 'Old completed task',
        isCompleted: true,
        createdAt: DateTime.utc(2026, 4),
        updatedAt: DateTime.utc(2026, 4),
        version: 1,
        syncStatus: SyncStatus.synced,
        deviceId: repository.deviceId,
      ),
      TodoTask(
        syncId: '22222222-2222-4222-8222-222222222222',
        ownerUserId: defaultCurrentUserId,
        createdByUserId: defaultCurrentUserId,
        updatedByUserId: defaultCurrentUserId,
        title: 'Recent completed task',
        isCompleted: true,
        createdAt: DateTime.utc(2026, 6),
        updatedAt: DateTime.utc(2026, 6),
        version: 1,
        syncStatus: SyncStatus.synced,
        deviceId: repository.deviceId,
      ),
    ]);

    final movedCount = await repository.moveExpiredCompletedTasksToTrash(
      CompletedTaskRetentionPolicy.oneMonth,
      now: DateTime.utc(2026, 6, 8),
    );

    expect(movedCount, 1);
    expect(repository.tasks.map((task) => task.title),
        contains('Recent completed task'));
    expect(repository.tasks.map((task) => task.title),
        isNot(contains('Old completed task')));
    expect(repository.trashTasks.single.title, 'Old completed task');
    expect(repository.trashTasks.single.purgeAfter, isNotNull);
    expect(await _syncQueueCount(repository), 1);
  });

  test('queues only changed subtasks for synced task edits', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_subtask_delta_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(
        title: 'Pick up groceries',
        subTasks: [
          SubTask(title: 'Produce'),
          SubTask(title: 'Milk'),
        ],
      ),
    );
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);
    final syncedTask = repository.tasks.single;
    final produce = syncedTask.subTasks[0];
    final milk = syncedTask.subTasks[1];

    await repository.upsertTask(
      syncedTask.copyWith(
        subTasks: [
          produce.copyWith(
            isCompleted: true,
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.pending,
          ),
          milk,
        ],
      ),
    );

    queue = await repository.getPendingSyncQueue(entityTypes: {'task'});
    final payload =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    final subtaskPayloads = payload['subtasks'] as List<Object?>;

    expect(payload['_changed_task_fields'], isNull);
    expect(subtaskPayloads, hasLength(1));
    final changedSubtask = subtaskPayloads.single as Map<String, Object?>;
    expect(changedSubtask['id'], produce.syncId);
    expect(changedSubtask['is_completed'], isTrue);
    expect(repository.tasks.single.subTasks[0].version, produce.version + 1);
    expect(repository.tasks.single.subTasks[1].version, milk.version);
  });

  test('queues changed task fields for parent task edits', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_task_delta_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(TodoTask(title: 'Original title'));
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    await repository.upsertTask(
      repository.tasks.single.copyWith(title: 'Renamed title'),
    );
    queue = await repository.getPendingSyncQueue(entityTypes: {'task'});
    final payload =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;

    expect(payload['_changed_task_fields'], ['title']);
  });

  test('does not queue unchanged saves for synced tasks', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_noop_save_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(TodoTask(title: 'Already synced'));
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);
    final syncedTask = repository.tasks.single;

    await repository.upsertTask(syncedTask.copyWith());

    expect(await _syncQueueCount(repository), 0);
    expect(repository.tasks.single.syncStatus, SyncStatus.synced);
    expect(repository.tasks.single.version, syncedTask.version);
    expect(repository.tasks.single.updatedAt, syncedTask.updatedAt);
  });

  test('merges repeated local edits into one pending task queue payload',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_queue_merge_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(title: 'Original title', note: 'Original note'),
    );
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    await repository.upsertTask(
      repository.tasks.single.copyWith(note: 'Pending note'),
    );
    await repository.upsertTask(
      repository.tasks.single.copyWith(title: 'Pending title'),
    );

    queue = await repository.getPendingSyncQueue(entityTypes: {'task'});
    expect(queue, hasLength(1));
    final payload =
        jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    expect(payload['_changed_task_fields'], ['note', 'title']);
    expect(payload['title'], 'Pending title');
    expect(payload['note'], 'Pending note');
  });

  test('remote subtask event overwrites same pending subtask and clears queue',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_subtask_win_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(
        title: 'Pick up groceries',
        subTasks: [
          SubTask(title: 'Produce'),
          SubTask(title: 'Milk'),
        ],
      ),
    );
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);
    final syncedTask = repository.tasks.single;
    final produce = syncedTask.subTasks[0];

    await repository.upsertTask(
      syncedTask.copyWith(
        subTasks: [
          produce.copyWith(isCompleted: true),
          syncedTask.subTasks[1],
        ],
      ),
    );
    expect(await _syncQueueCount(repository), 1);

    await repository.applySyncedChanges([
      SyncedTaskChange(
        operation: 'upsert',
        changedSubtaskSyncIds: [produce.syncId],
        task: syncedTask.copyWith(
          subTasks: [
            produce.copyWith(
              isCompleted: false,
              updatedAt: DateTime.utc(2026, 6, 5, 2),
              version: produce.version + 1,
            ),
          ],
        ),
      ),
    ]);

    expect(await _syncQueueCount(repository), 0);
    expect(repository.tasks.single.subTasks[0].isCompleted, isFalse);
    expect(repository.tasks.single.subTasks[0].syncStatus, SyncStatus.synced);
    expect(repository.tasks.single.subTasks[1].title, 'Milk');
  });

  test('remote parent field event removes only overlapping pending field',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_field_win_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(title: 'Server title', note: 'Server note'),
    );
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);
    final syncedTask = repository.tasks.single;

    await repository.upsertTask(
      syncedTask.copyWith(
        title: 'Local pending title',
        note: 'Local pending note',
      ),
    );
    queue = await repository.getPendingSyncQueue();
    var payload = jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    expect(payload['_changed_task_fields'], containsAll(['title', 'note']));

    await repository.applySyncedChanges([
      SyncedTaskChange(
        operation: 'upsert',
        changedTaskFields: const ['title'],
        task: syncedTask.copyWith(
          title: 'Remote accepted title',
          updatedAt: DateTime.utc(2026, 6, 5, 2),
          version: syncedTask.version + 1,
        ),
      ),
    ]);

    expect(repository.tasks.single.title, 'Remote accepted title');
    expect(repository.tasks.single.note, 'Local pending note');
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    queue = await repository.getPendingSyncQueue();
    expect(queue, hasLength(1));
    payload = jsonDecode(queue.single.payloadJson!) as Map<String, Object?>;
    expect(payload['_changed_task_fields'], ['note']);
  });

  test('incremental pull matches tasks only by syncId, not title', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_identity_sync_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(
      TodoTask(
        title: 'Pick up groceries',
        note: 'Restock basics for the week',
        category: 'Home',
      ),
    );
    final localSyncId = repository.tasks.single.syncId;
    expect(await _syncQueueCount(repository), 1);

    await repository.applySyncedChanges([
      SyncedTaskChange(
        operation: 'upsert',
        changedTaskFields: const ['title', 'note', 'category'],
        changedSubtaskSyncIds: const ['33333333-3333-4333-8333-333333333333'],
        task: TodoTask(
          syncId: '22222222-2222-4222-8222-222222222222',
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
              syncId: '33333333-3333-4333-8333-333333333333',
              taskSyncId: '22222222-2222-4222-8222-222222222222',
              title: 'Buy fruit',
              isCompleted: true,
              createdAt: DateTime.utc(2026, 6, 5),
              updatedAt: DateTime.utc(2026, 6, 5, 1),
              version: 1,
              syncStatus: SyncStatus.synced,
            ),
          ],
        ),
      ),
    ]);

    final matchingTasks =
        repository.tasks.where((task) => task.title == 'Pick up groceries');
    expect(matchingTasks, hasLength(2));
    expect(repository.tasks.map((task) => task.syncId), contains(localSyncId));
    expect(
      repository.tasks.map((task) => task.syncId),
      contains('22222222-2222-4222-8222-222222222222'),
    );
    expect(await _syncQueueCount(repository), 1);
  });

  test('applies synced remote task aggregates without queueing them', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_remote_apply_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    final remoteTask = TodoTask(
      syncId: '22222222-2222-4222-8222-222222222222',
      ownerUserId: defaultCurrentUserId,
      createdByUserId: defaultCurrentUserId,
      updatedByUserId: defaultCurrentUserId,
      title: 'Remote task',
      createdAt: DateTime.utc(2026, 6, 5, 1),
      updatedAt: DateTime.utc(2026, 6, 5, 2),
      version: 2,
      syncStatus: SyncStatus.synced,
      deviceId: repository.deviceId,
      subTasks: [
        SubTask(
          syncId: '33333333-3333-4333-8333-333333333333',
          taskSyncId: '22222222-2222-4222-8222-222222222222',
          title: 'Remote subtask',
          isCompleted: true,
          createdAt: DateTime.utc(2026, 6, 5, 1, 30),
          updatedAt: DateTime.utc(2026, 6, 5, 2, 30),
          version: 1,
          syncStatus: SyncStatus.synced,
        ),
      ],
    );

    final appliedCount = await repository.reconcileBootstrapTasks([remoteTask]);

    expect(appliedCount, 1);
    expect(await _syncQueueCount(repository), 0);
    expect(repository.tasks.single.title, 'Remote task');
    expect(repository.tasks.single.syncStatus, SyncStatus.synced);
    expect(repository.tasks.single.lastSyncedAt, isNotNull);
    expect(repository.tasks.single.subTasks.single.title, 'Remote subtask');
    expect(
        repository.tasks.single.subTasks.single.syncStatus, SyncStatus.synced);

    await repository.reconcileBootstrapTasks([
      remoteTask.copyWith(
        title: 'Remote task renamed',
        version: 3,
        subTasks: const [],
      ),
    ]);

    expect(await _syncQueueCount(repository), 0);
    expect(repository.tasks.single.title, 'Remote task renamed');
    expect(repository.tasks.single.subTasks, isEmpty);
  });

  test('reconcile snapshot preserves pending local task changes', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_pending_snapshot_');
    final repository = LocalTodoRepository(
      databasePath: path.join(tempDir.path, 'personal_todo.db'),
    );

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    await repository.upsertTask(TodoTask(title: 'Synced task'));
    var queue = await repository.getPendingSyncQueue();
    await repository.markSyncQueueItemSucceeded(queue.single.id);

    await repository.upsertTask(
      repository.tasks.single.copyWith(title: 'Pending local title'),
    );

    await repository.reconcileBootstrapTasks([]);

    expect(repository.tasks.single.title, 'Pending local title');
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    expect(await _syncQueueCount(repository), 1);
  });

  test('opens an existing Room v3 database without duplicating starter content',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_room_v3_');
    final databasePath = path.join(tempDir.path, 'personal_todo.db');

    final legacyDatabase = await openDatabase(
      databasePath,
      version: 3,
      onCreate: (database, version) async {
        await _createRoomV3Schema(database);
        await database.insert('tasks', {
          'id': 42,
          'title': 'Legacy task',
          'note': 'Created by Room',
          'category': 'Migration',
          'isCompleted': 0,
          'dueDateTime': null,
          'createdAt': 1710000000000,
          'updatedAt': 1710000000000,
        });
        await database.insert('subtasks', {
          'id': 7,
          'taskId': 42,
          'title': 'Legacy subtask',
          'isCompleted': 1,
          'createdAt': 1710000000000,
        });
      },
    );
    await legacyDatabase.close();

    final repository = LocalTodoRepository(databasePath: databasePath);

    await repository.init();
    addTearDown(() async {
      await repository.close();
      await tempDir.delete(recursive: true);
    });

    expect(repository.tasks.length, 1);
    expect(repository.tasks.single.title, 'Legacy task');
    expect(repository.tasks.single.subTasks.single.title, 'Legacy subtask');
    expect(repository.tasks.single.syncId, isNotEmpty);
    expect(repository.tasks.single.visibility, SyncVisibility.privateItem);
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    expect(repository.tasks.single.subTasks.single.syncId, isNotEmpty);
    expect(
      repository.tasks.single.subTasks.single.taskSyncId,
      repository.tasks.single.syncId,
    );
    expect(await _syncQueueCount(repository), greaterThanOrEqualTo(1));
    final pendingQueue = await repository.getPendingSyncQueue();
    final taskBackfill = pendingQueue.firstWhere(
      (item) => item.entityType == 'task',
    );
    final taskPayload =
        jsonDecode(taskBackfill.payloadJson!) as Map<String, Object?>;
    expect(taskPayload['id'], repository.tasks.single.syncId);
    expect(taskPayload['title'], 'Legacy task');
    expect(taskPayload['reminder_option'], 'none');
    expect(taskPayload['reminder_value'], isNull);
    expect(taskPayload.containsKey('sync_id'), isFalse);
    expect(taskPayload.containsKey('due_date_time'), isFalse);
    final backfilledSubTasks = taskPayload['subtasks'] as List<Object?>;
    expect(backfilledSubTasks, hasLength(1));
    expect(
      (backfilledSubTasks.single as Map<String, Object?>)['task_id'],
      repository.tasks.single.syncId,
    );

    expect(repository.tasks.length, 1);
  });
}

Future<int> _syncQueueCount(LocalTodoRepository repository) async {
  return (await repository.getPendingSyncSummary()).pendingCount;
}

TodoTask _remoteTask({
  required String syncId,
  required String ownerUserId,
  required String title,
  SyncVisibility visibility = SyncVisibility.privateItem,
  String? workspaceId,
}) {
  return TodoTask(
    syncId: syncId,
    ownerUserId: ownerUserId,
    visibility: visibility,
    workspaceId: workspaceId,
    createdByUserId: ownerUserId,
    updatedByUserId: ownerUserId,
    title: title,
    createdAt: DateTime.utc(2026, 6, 5),
    updatedAt: DateTime.utc(2026, 6, 5, 1),
    version: 1,
    syncStatus: SyncStatus.synced,
    deviceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  );
}

Future<void> _createRoomV3Schema(DatabaseExecutor database) async {
  await database.execute('''
    CREATE TABLE tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
      title TEXT NOT NULL,
      note TEXT NOT NULL,
      category TEXT NOT NULL,
      isCompleted INTEGER NOT NULL,
      dueDateTime INTEGER,
      createdAt INTEGER NOT NULL,
      updatedAt INTEGER NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE subtasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
      taskId INTEGER NOT NULL,
      title TEXT NOT NULL,
      isCompleted INTEGER NOT NULL,
      createdAt INTEGER NOT NULL,
      FOREIGN KEY(taskId) REFERENCES tasks(id) ON UPDATE NO ACTION ON DELETE CASCADE
    )
  ''');
  await database.execute(
    'CREATE INDEX index_subtasks_taskId ON subtasks (taskId)',
  );
}
