import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temporary;
  late LocalTodoRepository repository;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('todo_audit_');
    repository = LocalTodoRepository(databasePath: '${temporary.path}/todo.db');
    await repository.init(refreshNativeWidget: false);
  });
  tearDown(() async {
    await repository.close();
    await temporary.delete(recursive: true);
  });
  TodoTask remote(String title,
          {int version = 1, List<SubTask> subTasks = const []}) =>
      TodoTask(
        syncId: '20000000-0000-4000-8000-000000000001',
        ownerUserId: defaultCurrentUserId,
        createdByUserId: defaultCurrentUserId,
        updatedByUserId: defaultCurrentUserId,
        deviceId: repository.deviceId,
        title: title,
        version: version,
        syncStatus: SyncStatus.synced,
        subTasks: subTasks,
      );
  test(
      'failed uploads retry after 30 seconds and back off to at most five minutes',
      () async {
    await repository.upsertTask(TodoTask(title: 'Offline task'));
    for (final seconds in [30, 60, 120, 240, 300, 300]) {
      final id = (await repository.getPendingSyncQueue()).single.id;
      final before = DateTime.now().millisecondsSinceEpoch;
      await repository.markSyncQueueItemFailed(id, 'offline');
      final after = DateTime.now().millisecondsSinceEpoch;
      final pending = (await repository.getPendingSyncQueue()).single;
      expect(pending.nextAttemptAt.millisecondsSinceEpoch,
          inInclusiveRange(before + seconds * 1000, after + seconds * 1000));
      expect(repository.tasks.single.title, 'Offline task');
    }
    await repository.close();
    repository = LocalTodoRepository(databasePath: '${temporary.path}/todo.db');
    await repository.init(refreshNativeWidget: false);
    expect((await repository.getPendingSyncQueue()).single.attemptCount, 6);
    expect(await repository.retryFailedSyncQueueNow(), 1);
    expect(await repository.getPendingSyncQueue(now: DateTime.now()),
        hasLength(1));
  });
  test('snapshot preserves pending field edits and status', () async {
    final baseline = remote('Server original');
    await repository.reconcileBootstrapTasks([baseline]);
    await repository
        .upsertTask(repository.tasks.single.copyWith(title: 'My offline edit'));
    await repository.reconcileBootstrapTasks([baseline]);
    final pending = await repository.getPendingSyncQueue();
    expect(repository.tasks.single.title, 'My offline edit');
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    expect(jsonDecode(pending.single.payloadJson!)['title'], 'My offline edit');
  });
  test('old pull cannot roll back an acknowledged server version', () async {
    await repository
        .reconcileBootstrapTasks([remote('Latest accepted title', version: 3)]);
    await repository.applySyncedChanges([
      SyncedTaskChange(
          operation: 'upsert',
          task: remote('Earlier partner title', version: 2),
          changedTaskFields: ['title']),
    ]);
    expect(repository.tasks.single.title, 'Latest accepted title');
    expect(repository.tasks.single.version, 3);
  });
  test('version 10 upgrade preserves identities, children, and offline queue',
      () async {
    final children = [
      SubTask(
          syncId: '30000000-0000-4000-8000-000000000001',
          title: 'First child',
          createdAt: DateTime.utc(2026, 1, 1)),
      SubTask(
          syncId: '30000000-0000-4000-8000-000000000002',
          title: 'Second child',
          createdAt: DateTime.utc(2026, 1, 2)),
    ];
    final completed = remote('Completed task', version: 3).copyWith(
      syncId: '20000000-0000-4000-8000-000000000002',
      isCompleted: true,
      updatedAt: DateTime.utc(2026, 1, 3),
    );
    await repository.reconcileBootstrapTasks([
      remote('Pending task', version: 2, subTasks: children),
      completed,
    ]);
    final pendingTask =
        repository.tasks.firstWhere((task) => task.title == 'Pending task');
    await repository.upsertTask(pendingTask.copyWith(note: 'Offline note'),
        baseline: pendingTask);
    final queueBefore = (await repository.getPendingSyncQueue()).single;
    final taskIds = repository.tasks.map((task) => task.id).toSet();
    final childIds = pendingTask.subTasks.map((task) => task.id).toSet();
    await repository.close();
    final database = await openDatabase('${temporary.path}/todo.db');
    // Recreate the installed v10 shape, removing only the four v11 columns.
    await database.execute('ALTER TABLE tasks DROP COLUMN serverVersion');
    await database.execute('ALTER TABLE tasks DROP COLUMN completedAt');
    await database.execute('ALTER TABLE subtasks DROP COLUMN serverVersion');
    await database.execute('ALTER TABLE subtasks DROP COLUMN position');
    await database.setVersion(10);
    await database.close();
    repository = LocalTodoRepository(databasePath: '${temporary.path}/todo.db');
    await repository.init(refreshNativeWidget: false);
    expect(repository.tasks.map((task) => task.id).toSet(), taskIds);
    final migrated = repository.tasks
        .firstWhere((task) => task.syncId == pendingTask.syncId);
    expect(migrated.note, 'Offline note');
    expect(migrated.subTasks.map((child) => child.id).toSet(), childIds);
    expect(migrated.subTasks.map((child) => child.title),
        ['First child', 'Second child']);
    expect(migrated.subTasks.map((child) => child.position), [0, 1]);
    final queueAfter = (await repository.getPendingSyncQueue()).single;
    expect(queueAfter.id, queueBefore.id);
    expect(queueAfter.payloadJson, queueBefore.payloadJson);
    expect(
        repository.tasks
            .firstWhere((task) => task.isCompleted)
            .completedAt
            ?.toUtc(),
        completed.updatedAt.toUtc());
    await repository.applySyncedChanges([
      SyncedTaskChange(
          operation: 'upsert',
          task: completed.copyWith(title: 'Obsolete title', version: 2)),
    ]);
    expect(repository.tasks.firstWhere((task) => task.isCompleted).title,
        'Completed task');
  });
  test('stale editor changes only its own fields and preserves new children',
      () async {
    await repository.reconcileBootstrapTasks([remote('Task')]);
    final editorSnapshot = repository.tasks.single;
    await repository.reconcileBootstrapTasks([
      remote('Task', version: 2, subTasks: [
        SubTask(
            syncId: '30000000-0000-4000-8000-000000000001',
            title: 'Partner new subtask')
      ]).copyWith(note: 'Partner new note'),
    ]);
    await repository.upsertTask(
        editorSnapshot.copyWith(title: 'My edited title'),
        baseline: editorSnapshot);
    expect(repository.tasks.single.note, 'Partner new note');
    expect(
        repository.tasks.single.subTasks.single.title, 'Partner new subtask');
    final pending = jsonDecode(
        (await repository.getPendingSyncQueue()).single.payloadJson!);
    expect(pending['_changed_task_fields'], ['title']);
    expect(pending['subtasks'], isEmpty);
  });
  test('delete and undo before first sync preserves queued new child',
      () async {
    await repository.upsertTask(TodoTask(
        title: 'New offline task',
        subTasks: [SubTask(title: 'New offline child')]));
    await repository.moveTaskToTrash(repository.tasks.single);
    await repository.restoreTaskFromTrash(repository.trashTasks.single);
    final pending = jsonDecode(
        (await repository.getPendingSyncQueue()).single.payloadJson!);
    expect(repository.tasks.single.subTasks.length, 1);
    expect(pending['subtasks'].single['title'], 'New offline child');
    expect(
        pending['_changed_task_fields'], containsAll(['title', 'deleted_at']));
  });
  test('partner cannot purge owner shared trash', () async {
    repository.currentUserId = partnerUserId;
    final expired = remote('Shared trash').copyWith(
      visibility: SyncVisibility.shared,
      workspaceId: defaultSharedWorkspaceId,
      deletedAt: DateTime.now().subtract(const Duration(days: 31)),
      purgeAfter: DateTime.now().subtract(const Duration(days: 1)),
    );
    await repository.reconcileBootstrapTasks([expired]);
    expect(repository.canPermanentlyDeleteTask(repository.trashTasks.single),
        isFalse);
    await repository.purgeExpiredTrash();
    expect(repository.trashTasks, hasLength(1));
    expect(await repository.getPendingSyncQueue(), isEmpty);
  });
  test(
      'acknowledgement preserves newer edits and merges unrelated canonical fields',
      () async {
    await repository.reconcileBootstrapTasks([remote('Original')]);
    await repository
        .upsertTask(repository.tasks.single.copyWith(title: 'First edit'));
    final sent = (await repository.getPendingSyncQueue()).single;
    await repository
        .upsertTask(repository.tasks.single.copyWith(title: 'Second edit'));
    await repository.acknowledgeTaskChanges([
      SyncedTaskAcknowledgement(
          queueItemId: sent.id,
          operation: 'upsert',
          task:
              remote('First edit', version: 2).copyWith(note: 'Partner note')),
    ]);
    expect(repository.tasks.single.title, 'Second edit');
    expect(repository.tasks.single.note, 'Partner note');
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    final queue = await repository.getPendingSyncQueue();
    expect(queue, hasLength(1));
    expect(queue.single.id, isNot(sent.id));
  });
  test('stale editor cannot recreate a purged task', () async {
    await repository.reconcileBootstrapTasks([remote('Original')]);
    final baseline = repository.tasks.single;
    await repository.applyPurgedTaskIds([baseline.syncId]);
    await expectLater(
        repository.upsertTask(baseline.copyWith(title: 'Stale edit'),
            baseline: baseline),
        throwsStateError);
    expect(repository.tasks, isEmpty);
    expect(await repository.getPendingSyncQueue(), isEmpty);
  });
  test(
      'widget action replay remains idempotent after restarting the repository',
      () async {
    await repository.reconcileBootstrapTasks([
      remote('Both task').copyWith(
          visibility: SyncVisibility.shared,
          workspaceId: defaultSharedWorkspaceId,
          sharedCompletionMode: SharedCompletionMode.both)
    ]);
    final taskId = repository.tasks.single.id;
    await repository.toggleSharedTaskCompletionById(taskId,
        actionId: 'action-one');
    await repository.toggleSharedTaskCompletionById(taskId,
        actionId: 'action-one');
    expect(repository.tasks.single.completedByUserIds, [defaultCurrentUserId]);
    await repository.close();
    repository = LocalTodoRepository(databasePath: '${temporary.path}/todo.db');
    await repository.init(refreshNativeWidget: false);
    await repository.toggleSharedTaskCompletionById(taskId,
        actionId: 'action-one');
    expect(repository.tasks.single.completedByUserIds, [defaultCurrentUserId]);
    await repository.toggleSharedTaskCompletionById(taskId,
        actionId: 'action-two');
    expect(repository.tasks.single.completedByUserIds, isEmpty);
  });
  test('widget completion state survives repeated checks and old action replay',
      () async {
    await repository.reconcileBootstrapTasks([remote('Widget task')]);
    final taskId = repository.tasks.single.id;
    await repository.setTaskCompletionById(taskId,
        isCompleted: true, actionId: 'check-one');
    await repository.setTaskCompletionById(taskId,
        isCompleted: true, actionId: 'check-two');
    expect(repository.tasks.single.isCompleted, isTrue);
    await repository.setTaskCompletionById(taskId,
        isCompleted: false, actionId: 'uncheck');
    await repository.setTaskCompletionById(taskId,
        isCompleted: true, actionId: 'check-two');
    expect(repository.tasks.single.isCompleted, isFalse);
    expect(await repository.getPendingSyncQueue(), hasLength(1));
  });
  test('widget check preserves the partner completion and pending edits',
      () async {
    await repository.reconcileBootstrapTasks([
      remote('Both task').copyWith(
        visibility: SyncVisibility.shared,
        workspaceId: defaultSharedWorkspaceId,
        sharedCompletionMode: SharedCompletionMode.both,
        completedByUserIds: [partnerUserId],
      )
    ]);
    final task = repository.tasks.single;
    await repository.upsertTask(task.copyWith(note: 'Offline note'),
        baseline: task);
    await repository.setTaskCompletionById(task.id,
        isCompleted: true, actionId: 'check');
    expect(repository.tasks.single.isCompleted, isTrue);
    expect(repository.tasks.single.completedByUserIds,
        [defaultCurrentUserId, partnerUserId]);
    expect(repository.tasks.single.note, 'Offline note');
    await repository.setTaskCompletionById(task.id,
        isCompleted: false, actionId: 'uncheck');
    expect(repository.tasks.single.isCompleted, isFalse);
    expect(repository.tasks.single.completedByUserIds, [partnerUserId]);
    final payload = jsonDecode(
        (await repository.getPendingSyncQueue()).single.payloadJson!);
    expect(payload['note'], 'Offline note');
    expect(payload['completed_by_user_ids'], [partnerUserId]);
  });
  test('editing a completed task does not reset its retention clock', () async {
    final completedAt = DateTime.now().subtract(const Duration(days: 10));
    await repository.reconcileBootstrapTasks(
        [remote('Done').copyWith(isCompleted: true, completedAt: completedAt)]);
    final baseline = repository.tasks.single;
    await repository.upsertTask(baseline.copyWith(note: 'Added note'),
        baseline: baseline);
    expect(repository.tasks.single.completedAt?.millisecondsSinceEpoch,
        completedAt.millisecondsSinceEpoch);
  });
  test('subtask order survives updates and bootstrap on another device',
      () async {
    await repository.upsertTask(TodoTask(
        title: 'Ordered task',
        subTasks: [SubTask(title: 'One'), SubTask(title: 'Two')]));
    final baseline = repository.tasks.single;
    await repository.upsertTask(
        baseline.copyWith(subTasks: baseline.subTasks.reversed.toList()),
        baseline: baseline);
    final pending = jsonDecode(
        (await repository.getPendingSyncQueue()).single.payloadJson!);
    final children = pending['subtasks'] as List;
    expect(children.map((child) => child['position']).toSet(), {0, 1});
    expect(repository.tasks.single.subTasks.map((child) => child.title),
        ['Two', 'One']);
  });
  test('changing server preserves tasks and requeues canonical records',
      () async {
    await repository.reconcileBootstrapTasks([
      remote('Keep me', subTasks: [
        SubTask(syncId: '30000000-0000-4000-8000-000000000001', title: 'Child')
      ])
    ]);
    await repository.prepareForServerChange();
    expect(repository.tasks.single.title, 'Keep me');
    expect(repository.tasks.single.syncStatus, SyncStatus.pending);
    final pending = jsonDecode(
        (await repository.getPendingSyncQueue()).single.payloadJson!);
    expect(pending['subtasks'].single['title'], 'Child');
    await repository.reconcileBootstrapTasks([]);
    expect(repository.tasks.single.title, 'Keep me');
  });
}
