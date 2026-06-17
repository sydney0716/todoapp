import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'native_widget_bridge.dart';

const _changedTaskFieldsPayloadKey = '_changed_task_fields';
const _syncMetadataBackfilledKey = 'sync_metadata_backfilled';
const _initialSyncRetryDelay = Duration(minutes: 5);
const _maxSyncRetryDelay = Duration(hours: 1);
const _trashPurgeDelay = Duration(days: 30);

class LocalTodoRepository extends ChangeNotifier {
  static const databaseName = 'personal_todo.db';

  LocalTodoRepository({
    String? databasePath,
    this.currentUserId = defaultCurrentUserId,
    this.sharedWorkspaceId = defaultSharedWorkspaceId,
  }) : _databasePath = databasePath;

  final String? _databasePath;
  String currentUserId;
  final String sharedWorkspaceId;
  late final Database _database;
  late String _deviceId;
  List<TodoTask> _tasks = [];
  List<TodoTask> _trashTasks = [];

  List<TodoTask> get tasks => List.unmodifiable(_tasks);
  List<TodoTask> get trashTasks => List.unmodifiable(_trashTasks);
  String get deviceId => _deviceId;

  Future<void> init({bool refreshNativeWidget = true}) async {
    final databasePath =
        _databasePath ?? path.join(await getDatabasesPath(), databaseName);

    _database = await openDatabase(
      databasePath,
      version: 10,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion, newVersion);
      },
    );

    _deviceId = await _loadOrCreateDeviceId();
    await _backfillSyncMetadata();
    await reload(refreshNativeWidget: refreshNativeWidget);
  }

  Future<void> close() async {
    await _database.close();
  }

  Future<void> reload({bool refreshNativeWidget = true}) async {
    _tasks = await _readTasks();
    _trashTasks = await _readTrashTasks();
    notifyListeners();
    if (refreshNativeWidget) {
      unawaited(NativeWidgetBridge.refreshHomeWidget(
        tasks: _tasks,
        currentUserId: currentUserId,
      ));
    }
  }

  Future<List<SyncQueueItem>> getPendingSyncQueue({
    int? limit,
    DateTime? now,
    Set<String>? entityTypes,
  }) async {
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (now != null) {
      whereParts.add('nextAttemptAt <= ?');
      whereArgs.add(now.millisecondsSinceEpoch);
    }
    if (entityTypes != null && entityTypes.isNotEmpty) {
      whereParts.add(
        'entityType IN (${List.filled(entityTypes.length, '?').join(', ')})',
      );
      whereArgs.addAll(entityTypes);
    }

    final rows = await _database.query(
      'sync_queue',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(_syncQueueItemFromMap).toList(growable: false);
  }

  Future<SyncQueueSummary> getPendingSyncSummary() async {
    final pending = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_queue',
    );
    final failed = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_queue WHERE lastError IS NOT NULL',
    );
    return SyncQueueSummary(
      pendingCount: Sqflite.firstIntValue(pending) ?? 0,
      failedCount: Sqflite.firstIntValue(failed) ?? 0,
    );
  }

  Future<void> markSyncQueueItemSucceeded(int id) async {
    final syncedAt = DateTime.now().millisecondsSinceEpoch;
    await _database.transaction((transaction) async {
      final rows = await transaction.query(
        'sync_queue',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final item = rows.single;
      final operation = item['operation'] as String;
      if (operation != 'purge') {
        final entityType = item['entityType'] as String;
        final entitySyncId = item['entitySyncId'] as String;
        await _markEntitySynced(
          transaction,
          entityType: entityType,
          entitySyncId: entitySyncId,
          syncedAt: syncedAt,
        );
        if (entityType == 'task') {
          final changedSubtaskSyncIds =
              _subTaskSyncIdsFromPayloadJson(item['payloadJson'] as String?);
          if (changedSubtaskSyncIds.isNotEmpty) {
            await _markSubTasksSynced(
              transaction,
              subTaskSyncIds: changedSubtaskSyncIds,
              syncedAt: syncedAt,
            );
          }
        }
      }

      await transaction.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
    });
    await reload();
  }

  Future<void> markSyncQueueItemFailed(
    int id,
    String error, {
    DateTime? nextAttemptAt,
  }) async {
    final retryAt = nextAttemptAt ?? await _nextSyncRetryAt(id);
    await _database.rawUpdate(
      '''
      UPDATE sync_queue
      SET attemptCount = attemptCount + 1,
          lastError = ?,
          nextAttemptAt = ?
      WHERE id = ?
      ''',
      [error, retryAt.millisecondsSinceEpoch, id],
    );
  }

  Future<DateTime> _nextSyncRetryAt(int id) async {
    final rows = await _database.query(
      'sync_queue',
      columns: ['attemptCount'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final attemptCount =
        rows.isEmpty ? 0 : rows.single['attemptCount'] as int? ?? 0;
    final multiplier = 1 << min(attemptCount, 4);
    final retryDelay = _initialSyncRetryDelay * multiplier;
    final cappedDelay =
        retryDelay > _maxSyncRetryDelay ? _maxSyncRetryDelay : retryDelay;
    return DateTime.now().add(cappedDelay);
  }

  Future<void> removeSyncQueueItem(int id) async {
    await _database.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> syncQueueItemExists(int id) async {
    final rows = await _database.query(
      'sync_queue',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> applySyncedChanges(List<SyncedTaskChange> changes) async {
    if (changes.isEmpty) return 0;
    final now = DateTime.now();
    var appliedCount = 0;
    await _database.transaction((transaction) async {
      for (final change in changes) {
        final applied = change.operation == 'purge'
            ? await _purgeSyncedTaskBySyncId(transaction, change.task.syncId)
            : await _applySyncedTaskChange(transaction, change, now);
        if (applied) appliedCount += 1;
      }
    });
    await reload();
    return appliedCount;
  }

  Future<int> reconcileBootstrapTasks(List<TodoTask> tasks) async {
    final remoteSyncIds = tasks
        .map((task) => task.syncId)
        .where((syncId) => syncId.isNotEmpty)
        .toSet();
    final now = DateTime.now();
    await _database.transaction((transaction) async {
      await _removeSyncedTasksAbsentFromSnapshot(transaction, remoteSyncIds);
      for (final task in tasks) {
        await _applySyncedTask(transaction, task, now);
      }
    });
    await reload();
    return tasks.length;
  }



  Future<bool> _purgeSyncedTaskBySyncId(
    DatabaseExecutor db,
    String syncId,
  ) async {
    if (syncId.isEmpty) return false;
    final rows = await db.query(
      'tasks',
      columns: ['id', 'syncId'],
      where: 'syncId = ?',
      whereArgs: [syncId],
    );
    return await _deleteTaskRows(db, rows) > 0;
  }


  Future<int> _removeSyncedTasksAbsentFromSnapshot(
    DatabaseExecutor db,
    Set<String> remoteSyncIds,
  ) async {
    final whereArgs = <Object?>[];
    var where =
        "lastSyncedAt IS NOT NULL AND syncId IS NOT NULL AND syncId != ''";
    if (remoteSyncIds.isNotEmpty) {
      where +=
          ' AND syncId NOT IN (${List.filled(remoteSyncIds.length, '?').join(', ')})';
      whereArgs.addAll(remoteSyncIds);
    }

    final rows = await db.query(
      'tasks',
      columns: ['id', 'syncId'],
      where: where,
      whereArgs: whereArgs,
    );
    return _deleteTaskRows(db, rows);
  }

  Future<int> _deleteTaskRows(
    DatabaseExecutor db,
    List<Map<String, Object?>> rows,
  ) async {
    var removedCount = 0;
    for (final row in rows) {
      final taskId = row['id'] as int;
      final taskSyncId = row['syncId'] as String? ?? '';
      final subTaskRows = await db.query(
        'subtasks',
        columns: ['syncId'],
        where: 'taskId = ?',
        whereArgs: [taskId],
      );
      for (final subTaskRow in subTaskRows) {
        await _deleteSyncQueueEntity(
          db,
          entityType: 'subtask',
          entitySyncId: subTaskRow['syncId'] as String? ?? '',
        );
      }
      await _deleteSyncQueueEntity(
        db,
        entityType: 'task',
        entitySyncId: taskSyncId,
      );
      await db.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
      removedCount += 1;
    }
    return removedCount;
  }

  Future<void> _deleteSyncQueueEntity(
    DatabaseExecutor db, {
    required String entityType,
    required String entitySyncId,
  }) async {
    if (entitySyncId.isEmpty) return;
    await db.delete(
      'sync_queue',
      where: 'entityType = ? AND entitySyncId = ?',
      whereArgs: [entityType, entitySyncId],
    );
  }

  TodoTask? getTask(int id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Future<bool> markTaskDoneById(int taskId) async {
    final task = getTask(taskId);
    if (task == null) return false;
    if (task.requiresBothSharedCompletion &&
        task.isCompletedByUser(currentUserId)) {
      return false;
    }
    if (!task.requiresBothSharedCompletion && task.isCompleted) return false;

    await upsertTask(
      task.toggledCompletionForUser(currentUserId),
    );
    return true;
  }

  Future<bool> toggleSharedTaskCompletionById(int taskId) async {
    final task = getTask(taskId);
    if (task == null || !task.requiresBothSharedCompletion) return false;

    await upsertTask(
      task.toggledCompletionForUser(currentUserId),
    );
    return true;
  }

  Future<bool> markSubTaskDoneById(int taskId, int subTaskId) async {
    final task = getTask(taskId);
    if (task == null || task.isCompleted) return false;

    var didChange = false;
    final now = DateTime.now();
    final updatedSubTasks = [
      for (final subTask in task.subTasks)
        if (subTask.id == subTaskId && !subTask.isCompleted)
          subTask.copyWith(
            isCompleted: true,
            updatedAt: now,
          )
        else
          subTask,
    ];

    for (final subTask in task.subTasks) {
      if (subTask.id == subTaskId && !subTask.isCompleted) {
        didChange = true;
        break;
      }
    }
    if (!didChange) return false;

    await upsertTask(
      task.copyWith(
        updatedAt: now,
        subTasks: updatedSubTasks,
      ),
    );
    return true;
  }

  Future<void> upsertTask(TodoTask task) async {
    await _database.transaction((transaction) async {
      final now = DateTime.now();
      final existingTaskRow = await _existingTaskRow(transaction, task.id);
      final taskWithExistingMetadata =
          await _taskWithExistingSyncMetadata(transaction, task);
      final changedTaskFields = _changedTaskFields(
        taskWithExistingMetadata,
        existingTaskRow,
      );
      final normalizedTask =
          _taskWithSyncDefaults(taskWithExistingMetadata, now);
      final isKnownExistingTask = existingTaskRow != null && task.id != 0;
      var taskId = task.id;
      if (isKnownExistingTask) {
        taskId = existingTaskRow['id'] as int;
      } else if (task.id != 0) {
        final updatedRows = await transaction.update(
          'tasks',
          _taskToMap(normalizedTask),
          where: 'id = ?',
          whereArgs: [task.id],
        );
        if (updatedRows == 0) {
          taskId =
              await transaction.insert('tasks', _taskToMap(normalizedTask));
        }
      } else {
        taskId = await transaction.insert('tasks', _taskToMap(normalizedTask));
      }

      final existingSubTaskRows = {
        for (final row in await transaction.query(
          'subtasks',
          where: 'taskId = ?',
          whereArgs: [taskId],
        ))
          row['id'] as int: row,
      };
      final retainedSubTaskIds = <int>{};
      final retainedSubTaskSyncIds = <String>{};
      final payloadSubTasks = <SubTask>[];

      for (final subTask in task.subTasks) {
        final title = subTask.title.trim();
        if (title.isEmpty) continue;
        final existingRow =
            subTask.id == 0 ? null : existingSubTaskRows[subTask.id];
        final shouldSyncSubTask = _shouldSyncSubTask(
          subTask,
          existingRow,
          title: title,
        );
        final subTaskWithExistingMetadata =
            _subTaskWithExistingSyncMetadata(subTask, existingSubTaskRows);
        final preparedSubTask = subTaskWithExistingMetadata.copyWith(
          taskId: taskId,
          taskSyncId: normalizedTask.syncId,
          title: title,
          ownerUserId: normalizedTask.ownerUserId,
          visibility: normalizedTask.visibility,
          workspaceId: normalizedTask.workspaceId,
          deviceId: normalizedTask.deviceId,
        );
        final normalizedSubTask = shouldSyncSubTask
            ? _subTaskWithSyncDefaults(preparedSubTask, now)
            : preparedSubTask;
        retainedSubTaskSyncIds.add(normalizedSubTask.syncId);
        if (normalizedSubTask.id != 0) {
          retainedSubTaskIds.add(normalizedSubTask.id);
        }

        if (normalizedSubTask.id != 0 &&
            existingSubTaskRows.containsKey(normalizedSubTask.id)) {
          await transaction.update(
            'subtasks',
            _subTaskToMap(normalizedSubTask),
            where: 'id = ?',
            whereArgs: [normalizedSubTask.id],
          );
        } else {
          final insertedId = await transaction.insert(
            'subtasks',
            _subTaskToMap(normalizedSubTask),
          );
          retainedSubTaskIds.add(insertedId);
          if (shouldSyncSubTask) {
            payloadSubTasks.add(normalizedSubTask.copyWith(id: insertedId));
          }
          continue;
        }
        if (shouldSyncSubTask) {
          payloadSubTasks.add(normalizedSubTask);
        }
      }

      for (final row in existingSubTaskRows.values) {
        final id = row['id'] as int;
        final syncId = row['syncId'] as String? ?? '';
        final alreadyDeleted = row['deletedAt'] != null;
        final stillPresent = retainedSubTaskIds.contains(id) ||
            retainedSubTaskSyncIds.contains(syncId);
        if (alreadyDeleted || stillPresent) continue;

        final deletedSubTask = _subTaskFromMap(row).copyWith(
          updatedAt: now,
          deletedAt: now,
          purgeAfter: normalizedTask.purgeAfter,
          syncStatus: SyncStatus.pending,
          version: ((row['version'] as int?) ?? 1) + 1,
          deviceId: _deviceId,
        );
        await transaction.update(
          'subtasks',
          _subTaskToMap(deletedSubTask),
          where: 'id = ?',
          whereArgs: [id],
        );
        payloadSubTasks.add(deletedSubTask);
      }

      if (isKnownExistingTask &&
          changedTaskFields.isEmpty &&
          payloadSubTasks.isEmpty) {
        return;
      }

      if (isKnownExistingTask) {
        await transaction.update(
          'tasks',
          _taskToMap(normalizedTask),
          where: 'id = ?',
          whereArgs: [taskId],
        );
      }

      await _enqueueSync(
        transaction,
        entityType: 'task',
        entitySyncId: normalizedTask.syncId,
        operation: 'upsert',
        payloadJson: _encodeTaskPayload(
          normalizedTask.copyWith(subTasks: payloadSubTasks),
          changedTaskFields: changedTaskFields,
        ),
        createdAt: now,
      );
    });

    await reload();
  }

  Future<void> upsertTasks(List<TodoTask> tasks) async {
    for (final task in tasks) {
      await upsertTask(task);
    }
  }

  Future<void> moveTaskToTrash(
    TodoTask task, {
    bool refreshNativeWidget = true,
  }) async {
    final now = DateTime.now();
    final deletedTask = _taskWithSyncDefaults(
      task.copyWith(
        updatedAt: now,
        deletedAt: now,
        purgeAfter: now.add(_trashPurgeDelay),
        syncStatus: SyncStatus.pending,
      ),
      now,
    );

    await _database.transaction((transaction) async {
      await transaction.update(
        'tasks',
        _taskToMap(deletedTask),
        where: 'id = ?',
        whereArgs: [deletedTask.id],
      );
      await _enqueueSync(
        transaction,
        entityType: 'task',
        entitySyncId: deletedTask.syncId,
        operation: 'delete',
        payloadJson: _encodeTaskPayload(
          deletedTask,
          changedTaskFields: const {'deleted_at'},
        ),
        createdAt: now,
      );
    });
    await reload(refreshNativeWidget: refreshNativeWidget);
  }

  Future<void> restoreTaskFromTrash(TodoTask task) async {
    final now = DateTime.now();

    await _database.transaction((transaction) async {
      final taskWithCurrentMetadata =
          await _taskWithExistingSyncMetadata(transaction, task);
      final restoredTask = _taskWithSyncDefaults(
        taskWithCurrentMetadata.copyWith(
          updatedAt: now,
          deletedAt: null,
          purgeAfter: null,
          syncStatus: SyncStatus.pending,
        ),
        now,
      );
      await transaction.update(
        'tasks',
        _taskToMap(restoredTask),
        where: 'id = ?',
        whereArgs: [restoredTask.id],
      );
      await _enqueueSync(
        transaction,
        entityType: 'task',
        entitySyncId: restoredTask.syncId,
        operation: 'upsert',
        payloadJson: _encodeTaskPayload(
          restoredTask,
          changedTaskFields: const {'deleted_at'},
        ),
        createdAt: now,
      );
    });
    await reload();
  }

  bool canPermanentlyDeleteTask(TodoTask task) {
    return task.deletedAt != null && task.syncStatus == SyncStatus.synced;
  }

  Future<bool> permanentlyDeleteTask(
    TodoTask task, {
    bool refreshNativeWidget = true,
  }) async {
    if (!canPermanentlyDeleteTask(task)) return false;

    final now = DateTime.now();
    await _database.transaction((transaction) async {
      await _enqueueSync(
        transaction,
        entityType: 'task',
        entitySyncId: task.syncId,
        operation: 'purge',
        payloadJson: _encodeTaskPayload(task),
        createdAt: now,
      );
      await transaction.delete('tasks', where: 'id = ?', whereArgs: [task.id]);
    });
    await reload(refreshNativeWidget: refreshNativeWidget);
    return true;
  }

  Future<void> emptyTrash() async {
    final trashTasks =
        _trashTasks.where(canPermanentlyDeleteTask).toList(growable: false);
    if (trashTasks.isEmpty) return;

    final now = DateTime.now();
    await _database.transaction((transaction) async {
      for (final task in trashTasks) {
        await _enqueueSync(
          transaction,
          entityType: 'task',
          entitySyncId: task.syncId,
          operation: 'purge',
          payloadJson: _encodeTaskPayload(task),
          createdAt: now,
        );
        await transaction.delete(
          'tasks',
          where: 'id = ?',
          whereArgs: [task.id],
        );
      }
    });
    await reload();
  }

  Future<int> moveExpiredCompletedTasksToTrash(
    CompletedTaskRetentionPolicy retentionPolicy, {
    DateTime? now,
    bool refreshNativeWidget = true,
  }) async {
    final cutoff = now ?? DateTime.now();
    final expiredTasks = _tasks.where((task) {
      if (!task.isCompleted || task.deletedAt != null) return false;
      return !retentionPolicy.trashAfter(task.updatedAt).isAfter(cutoff);
    }).toList();

    for (final task in expiredTasks) {
      await moveTaskToTrash(
        task,
        refreshNativeWidget: refreshNativeWidget,
      );
    }
    return expiredTasks.length;
  }

  Future<void> purgeExpiredTrash({
    DateTime? now,
    bool refreshNativeWidget = true,
  }) async {
    final cutoff = now ?? DateTime.now();
    final expiredTasks = _trashTasks.where((task) {
      final purgeAfter = task.purgeAfter;
      return purgeAfter != null &&
          !purgeAfter.isAfter(cutoff) &&
          task.syncStatus == SyncStatus.synced;
    }).toList();

    for (final task in expiredTasks) {
      await permanentlyDeleteTask(
        task,
        refreshNativeWidget: refreshNativeWidget,
      );
    }
  }

  Future<List<TodoTask>> _readTasks() async {
    return _readTaskRows(
      where: 'deletedAt IS NULL',
      subTaskWhere: 'deletedAt IS NULL',
    );
  }

  Future<List<TodoTask>> _readTrashTasks() async {
    return _readTaskRows(where: 'deletedAt IS NOT NULL');
  }

  Future<List<TodoTask>> _readTaskRows({
    String? where,
    String? subTaskWhere,
  }) async {
    final taskRows = await _database.query('tasks', where: where);
    if (taskRows.isEmpty) return const [];

    final taskIds = taskRows.map((row) => row['id'] as int).toList();
    final taskIdFilter =
        'taskId IN (${List.filled(taskIds.length, '?').join(', ')})';
    final subTaskRows = await _database.query(
      'subtasks',
      where: [
        taskIdFilter,
        if (subTaskWhere != null) '($subTaskWhere)',
      ].join(' AND '),
      whereArgs: taskIds,
    );
    final subTasksByTaskId = <int, List<SubTask>>{};

    for (final row in subTaskRows) {
      final subTask = _subTaskFromMap(row);
      subTasksByTaskId.putIfAbsent(subTask.taskId, () => []).add(subTask);
    }

    return taskRows.map((row) {
      final id = row['id'] as int;
      final subTasks = subTasksByTaskId[id] ?? [];
      subTasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return _taskFromMap(row, subTasks);
    }).toList(growable: false);
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        syncId TEXT,
        ownerUserId TEXT NOT NULL DEFAULT '',
        visibility TEXT NOT NULL DEFAULT 'private',
        workspaceId TEXT,
        createdByUserId TEXT NOT NULL DEFAULT '',
        updatedByUserId TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL,
        note TEXT NOT NULL,
        category TEXT NOT NULL,
        isCompleted INTEGER NOT NULL,
        sharedCompletionMode TEXT NOT NULL DEFAULT 'single',
        completedByUserIds TEXT NOT NULL DEFAULT '[]',
        dueDateTime INTEGER,
        reminderOption TEXT NOT NULL DEFAULT 'none',
        reminderValue INTEGER,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        deletedAt INTEGER,
        purgeAfter INTEGER,
        lastSyncedAt INTEGER,
        deviceId TEXT NOT NULL DEFAULT '',
        isStarterContent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS subtasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        taskId INTEGER NOT NULL,
        syncId TEXT,
        taskSyncId TEXT NOT NULL DEFAULT '',
        ownerUserId TEXT NOT NULL DEFAULT '',
        visibility TEXT NOT NULL DEFAULT 'private',
        workspaceId TEXT,
        title TEXT NOT NULL,
        isCompleted INTEGER NOT NULL,
        dueDateTime INTEGER,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        deletedAt INTEGER,
        purgeAfter INTEGER,
        lastSyncedAt INTEGER,
        deviceId TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(taskId) REFERENCES tasks(id) ON UPDATE NO ACTION ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS index_subtasks_taskId ON subtasks (taskId)',
    );

    await _createLocalMetadata(db);
    await _createSyncQueue(db);
    await _createSyncIndexes(db);
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN category TEXT NOT NULL DEFAULT ''");
      await db.execute('''
        CREATE TABLE IF NOT EXISTS subtasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          taskId INTEGER NOT NULL,
          title TEXT NOT NULL,
          isCompleted INTEGER NOT NULL,
          createdAt INTEGER NOT NULL,
          FOREIGN KEY(taskId) REFERENCES tasks(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS index_subtasks_taskId ON subtasks (taskId)',
      );
    }

    if (oldVersion < 3) {
      await db.execute('ALTER TABLE subtasks RENAME TO subtasks_old');
      await db.execute('ALTER TABLE tasks RENAME TO tasks_old');
      await _createSchema(db);
      await db.execute('''
        INSERT INTO tasks (
          id, title, note, category, isCompleted, dueDateTime, createdAt, updatedAt
        )
        SELECT id, title, note, category, isCompleted, dueDateTime, createdAt, updatedAt
        FROM tasks_old
      ''');
      await db.execute('''
        INSERT INTO subtasks (id, taskId, title, isCompleted, createdAt)
        SELECT id, taskId, title, isCompleted, createdAt
        FROM subtasks_old
      ''');
      await db.execute('DROP TABLE subtasks_old');
      await db.execute('DROP TABLE tasks_old');
    }

    if (oldVersion < 4) {
      await _addSyncSchema(db);
    }

    if (oldVersion < 6) {
      await _addTaskReminderSchema(db);
    }

    if (oldVersion < 7) {
      await _addTaskReminderValueSchema(db);
    }

    if (oldVersion < 8) {
      await _addSubTaskDueDateSchema(db);
    }

    if (oldVersion < 9) {
      await _addStarterContentSchema(db);
    }

    if (oldVersion < 10) {
      await _addSharedCompletionSchema(db);
    }

    await _createLocalMetadata(db);
    await _createSyncIndexes(db);
  }

  TodoTask _taskFromMap(Map<String, Object?> row, List<SubTask> subTasks) {
    final storedReminderOption = row['reminderOption'] as String?;
    return TodoTask(
      id: row['id'] as int,
      syncId: row['syncId'] as String? ?? '',
      ownerUserId: row['ownerUserId'] as String? ?? '',
      visibility: SyncVisibility.fromStoredValue(row['visibility'] as String?),
      workspaceId: row['workspaceId'] as String?,
      createdByUserId: row['createdByUserId'] as String? ?? '',
      updatedByUserId: row['updatedByUserId'] as String? ?? '',
      title: row['title'] as String,
      note: row['note'] as String,
      category: row['category'] as String,
      isCompleted: (row['isCompleted'] as int) == 1,
      sharedCompletionMode: SharedCompletionMode.fromStoredValue(
        row['sharedCompletionMode'] as String?,
      ),
      completedByUserIds: _completedByUserIdsFromJson(
        row['completedByUserIds'] as String?,
      ),
      dueDateTime: _dateFromMillis(row['dueDateTime'] as int?),
      reminderOption: TaskReminderOption.fromStoredValue(storedReminderOption),
      reminderValue: row['reminderValue'] as int? ??
          TaskReminderOption.valueFromStoredValue(storedReminderOption),
      createdAt: _dateFromMillis(row['createdAt'] as int)!,
      updatedAt: _dateFromMillis(row['updatedAt'] as int)!,
      version: row['version'] as int? ?? 1,
      syncStatus: SyncStatus.fromStoredValue(row['syncStatus'] as String?),
      deletedAt: _dateFromMillis(row['deletedAt'] as int?),
      purgeAfter: _dateFromMillis(row['purgeAfter'] as int?),
      lastSyncedAt: _dateFromMillis(row['lastSyncedAt'] as int?),
      deviceId: row['deviceId'] as String? ?? '',
      isStarterContent: (row['isStarterContent'] as int? ?? 0) == 1,
      subTasks: subTasks,
    );
  }

  SubTask _subTaskFromMap(Map<String, Object?> row) {
    return SubTask(
      id: row['id'] as int,
      taskId: row['taskId'] as int,
      syncId: row['syncId'] as String? ?? '',
      taskSyncId: row['taskSyncId'] as String? ?? '',
      ownerUserId: row['ownerUserId'] as String? ?? '',
      visibility: SyncVisibility.fromStoredValue(row['visibility'] as String?),
      workspaceId: row['workspaceId'] as String?,
      title: row['title'] as String,
      isCompleted: (row['isCompleted'] as int) == 1,
      dueDateTime: _dateFromMillis(row['dueDateTime'] as int?),
      createdAt: _dateFromMillis(row['createdAt'] as int)!,
      updatedAt: _dateFromMillis(row['updatedAt'] as int?),
      version: row['version'] as int? ?? 1,
      syncStatus: SyncStatus.fromStoredValue(row['syncStatus'] as String?),
      deletedAt: _dateFromMillis(row['deletedAt'] as int?),
      purgeAfter: _dateFromMillis(row['purgeAfter'] as int?),
      lastSyncedAt: _dateFromMillis(row['lastSyncedAt'] as int?),
      deviceId: row['deviceId'] as String? ?? '',
    );
  }

  Map<String, Object?> _taskToMap(TodoTask task) {
    return {
      if (task.id != 0) 'id': task.id,
      'syncId': task.syncId,
      'ownerUserId': task.ownerUserId,
      'visibility': task.visibility.storedValue,
      'workspaceId': task.workspaceId,
      'createdByUserId': task.createdByUserId,
      'updatedByUserId': task.updatedByUserId,
      'title': task.title,
      'note': task.note,
      'category': task.category,
      'isCompleted': task.isCompleted ? 1 : 0,
      'sharedCompletionMode': task.sharedCompletionMode.storedValue,
      'completedByUserIds': jsonEncode(task.completedByUserIds),
      'dueDateTime': task.dueDateTime?.millisecondsSinceEpoch,
      'reminderOption': task.reminderOption.storedValue,
      'reminderValue': task.reminderValue,
      'createdAt': task.createdAt.millisecondsSinceEpoch,
      'updatedAt': task.updatedAt.millisecondsSinceEpoch,
      'version': task.version,
      'syncStatus': task.syncStatus.storedValue,
      'deletedAt': task.deletedAt?.millisecondsSinceEpoch,
      'purgeAfter': task.purgeAfter?.millisecondsSinceEpoch,
      'lastSyncedAt': task.lastSyncedAt?.millisecondsSinceEpoch,
      'deviceId': task.deviceId,
      'isStarterContent': task.isStarterContent ? 1 : 0,
    };
  }

  Map<String, Object?> _subTaskToMap(SubTask subTask) {
    return {
      if (subTask.id != 0) 'id': subTask.id,
      'taskId': subTask.taskId,
      'syncId': subTask.syncId,
      'taskSyncId': subTask.taskSyncId,
      'ownerUserId': subTask.ownerUserId,
      'visibility': subTask.visibility.storedValue,
      'workspaceId': subTask.workspaceId,
      'title': subTask.title,
      'isCompleted': subTask.isCompleted ? 1 : 0,
      'dueDateTime': subTask.dueDateTime?.millisecondsSinceEpoch,
      'createdAt': subTask.createdAt.millisecondsSinceEpoch,
      'updatedAt': subTask.updatedAt?.millisecondsSinceEpoch,
      'version': subTask.version,
      'syncStatus': subTask.syncStatus.storedValue,
      'deletedAt': subTask.deletedAt?.millisecondsSinceEpoch,
      'purgeAfter': subTask.purgeAfter?.millisecondsSinceEpoch,
      'lastSyncedAt': subTask.lastSyncedAt?.millisecondsSinceEpoch,
      'deviceId': subTask.deviceId,
    };
  }

  TodoTask _taskWithSyncDefaults(TodoTask task, DateTime now) {
    final visibility = task.visibility;
    final isNewLocalRecord = task.id == 0 && task.syncId.isEmpty;
    final ownerUserId = _normalizeUserId(
      task.ownerUserId.isEmpty ? currentUserId : task.ownerUserId,
    );
    return task.copyWith(
      syncId: task.syncId.isEmpty ? _newSyncId() : task.syncId,
      ownerUserId: ownerUserId,
      visibility: visibility,
      workspaceId: _normalizeWorkspaceId(task.workspaceId, visibility),
      createdByUserId: _normalizeUserId(
        task.createdByUserId.isEmpty ? currentUserId : task.createdByUserId,
      ),
      updatedByUserId: _normalizeUserId(currentUserId),
      syncStatus: SyncStatus.pending,
      updatedAt: now,
      version:
          isNewLocalRecord ? 1 : (task.version <= 0 ? 1 : task.version + 1),
      deviceId: _deviceId,
    );
  }

  List<String> _completedByUserIdsFromJson(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded.whereType<String>().toList();
    } on FormatException {
      return const [];
    }
    return const [];
  }

  Future<Map<String, Object?>?> _existingTaskRow(
    DatabaseExecutor db,
    int taskId,
  ) async {
    if (taskId == 0) return null;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<TodoTask> _taskWithExistingSyncMetadata(
    DatabaseExecutor db,
    TodoTask task,
  ) async {
    if (task.id == 0) return task;

    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [task.id],
      limit: 1,
    );
    if (rows.isEmpty) return task;

    final existing = rows.single;
    return task.copyWith(
      syncId: existing['syncId'] as String? ?? task.syncId,
      ownerUserId: task.ownerUserId.isEmpty
          ? existing['ownerUserId'] as String? ?? task.ownerUserId
          : task.ownerUserId,
      visibility: task.ownerUserId.isEmpty
          ? SyncVisibility.fromStoredValue(existing['visibility'] as String?)
          : task.visibility,
      workspaceId: task.ownerUserId.isEmpty
          ? existing['workspaceId'] as String?
          : task.workspaceId,
      createdByUserId: task.createdByUserId.isEmpty
          ? existing['createdByUserId'] as String? ?? task.createdByUserId
          : task.createdByUserId,
      sharedCompletionMode: task.ownerUserId.isEmpty
          ? SharedCompletionMode.fromStoredValue(
              existing['sharedCompletionMode'] as String?,
            )
          : task.sharedCompletionMode,
      completedByUserIds: task.ownerUserId.isEmpty
          ? _completedByUserIdsFromJson(
              existing['completedByUserIds'] as String?)
          : task.completedByUserIds,
      updatedByUserId:
          existing['updatedByUserId'] as String? ?? task.updatedByUserId,
      version: existing['version'] as int? ?? 1,
      syncStatus: SyncStatus.fromStoredValue(existing['syncStatus'] as String?),
      deletedAt: _dateFromMillis(existing['deletedAt'] as int?),
      purgeAfter: _dateFromMillis(existing['purgeAfter'] as int?),
      lastSyncedAt: _dateFromMillis(existing['lastSyncedAt'] as int?),
      deviceId: existing['deviceId'] as String? ?? '',
      isStarterContent: (existing['isStarterContent'] as int? ?? 0) == 1,
    );
  }

  Set<String> _changedTaskFields(
    TodoTask task,
    Map<String, Object?>? existingRow,
  ) {
    if (existingRow == null) {
      return const {
        'owner_user_id',
        'visibility',
        'workspace_id',
        'created_by_user_id',
        'title',
        'note',
        'category',
        'is_completed',
        'shared_completion_mode',
        'completed_by_user_ids',
        'due_at',
        'reminder_option',
        'reminder_value',
        'deleted_at',
      };
    }

    final fields = <String>{};
    if ((existingRow['ownerUserId'] as String? ?? '') != task.ownerUserId) {
      fields.add('owner_user_id');
    }
    if (SyncVisibility.fromStoredValue(existingRow['visibility'] as String?) !=
        task.visibility) {
      fields.add('visibility');
    }
    if (existingRow['workspaceId'] != task.workspaceId) {
      fields.add('workspace_id');
    }
    if ((existingRow['createdByUserId'] as String? ?? '') !=
        task.createdByUserId) {
      fields.add('created_by_user_id');
    }
    if (existingRow['title'] != task.title) fields.add('title');
    if (existingRow['note'] != task.note) fields.add('note');
    if (existingRow['category'] != task.category) fields.add('category');
    if (((existingRow['isCompleted'] as int? ?? 0) == 1) != task.isCompleted) {
      fields.add('is_completed');
    }
    if (SharedCompletionMode.fromStoredValue(
          existingRow['sharedCompletionMode'] as String?,
        ) !=
        task.sharedCompletionMode) {
      fields.add('shared_completion_mode');
    }
    if (!_sameStringList(
      _completedByUserIdsFromJson(existingRow['completedByUserIds'] as String?),
      task.completedByUserIds,
    )) {
      fields.add('completed_by_user_ids');
    }
    if (!_sameDateTime(
      _dateFromMillis(existingRow['dueDateTime'] as int?),
      task.dueDateTime,
    )) {
      fields.add('due_at');
    }
    if (TaskReminderOption.fromStoredValue(
          existingRow['reminderOption'] as String?,
        ) !=
        task.reminderOption) {
      fields.add('reminder_option');
    }
    if (existingRow['reminderValue'] != task.reminderValue) {
      fields.add('reminder_value');
    }
    if (!_sameDateTime(
      _dateFromMillis(existingRow['deletedAt'] as int?),
      task.deletedAt,
    )) {
      fields.add('deleted_at');
    }
    return fields;
  }

  SubTask _subTaskWithSyncDefaults(SubTask subTask, DateTime now) {
    final visibility = subTask.visibility;
    final isNewLocalRecord = subTask.id == 0 && subTask.syncId.isEmpty;
    final ownerUserId = _normalizeUserId(
      subTask.ownerUserId.isEmpty ? currentUserId : subTask.ownerUserId,
    );
    return subTask.copyWith(
      syncId: subTask.syncId.isEmpty ? _newSyncId() : subTask.syncId,
      ownerUserId: ownerUserId,
      visibility: visibility,
      workspaceId: _normalizeWorkspaceId(subTask.workspaceId, visibility),
      syncStatus: SyncStatus.pending,
      updatedAt: now,
      version: isNewLocalRecord
          ? 1
          : (subTask.version <= 0 ? 1 : subTask.version + 1),
      deviceId: _deviceId,
    );
  }

  SubTask _subTaskWithExistingSyncMetadata(
    SubTask subTask,
    Map<int, Map<String, Object?>> existingRows,
  ) {
    if (subTask.id == 0) return subTask;

    final existing = existingRows[subTask.id];
    if (existing == null) return subTask;

    return subTask.copyWith(
      syncId: existing['syncId'] as String? ?? subTask.syncId,
      taskSyncId: existing['taskSyncId'] as String? ?? subTask.taskSyncId,
      ownerUserId: existing['ownerUserId'] as String? ?? subTask.ownerUserId,
      visibility:
          SyncVisibility.fromStoredValue(existing['visibility'] as String?),
      workspaceId: existing['workspaceId'] as String?,
      updatedAt: _dateFromMillis(existing['updatedAt'] as int?),
      version: existing['version'] as int? ?? 1,
      syncStatus: SyncStatus.fromStoredValue(existing['syncStatus'] as String?),
      deletedAt: _dateFromMillis(existing['deletedAt'] as int?),
      purgeAfter: _dateFromMillis(existing['purgeAfter'] as int?),
      lastSyncedAt: _dateFromMillis(existing['lastSyncedAt'] as int?),
      deviceId: existing['deviceId'] as String? ?? '',
    );
  }

  bool _shouldSyncSubTask(
    SubTask subTask,
    Map<String, Object?>? existingRow, {
    required String title,
  }) {
    if (existingRow == null) return true;
    final existingStatus = SyncStatus.fromStoredValue(
      existingRow['syncStatus'] as String?,
    );
    if (existingStatus == SyncStatus.pending) return true;

    return (existingRow['title'] as String) != title ||
        ((existingRow['isCompleted'] as int) == 1) != subTask.isCompleted ||
        !_sameDateTime(
          _dateFromMillis(existingRow['dueDateTime'] as int?),
          subTask.dueDateTime,
        ) ||
        !_sameDateTime(
          _dateFromMillis(existingRow['deletedAt'] as int?),
          subTask.deletedAt,
        );
  }

  Future<void> _createSyncQueue(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        entityType TEXT NOT NULL,
        entitySyncId TEXT NOT NULL,
        operation TEXT NOT NULL,
        payloadJson TEXT,
        attemptCount INTEGER NOT NULL DEFAULT 0,
        lastError TEXT,
        createdAt INTEGER NOT NULL,
        nextAttemptAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS index_sync_queue_nextAttemptAt '
      'ON sync_queue (nextAttemptAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS index_sync_queue_entity '
      'ON sync_queue (entityType, entitySyncId)',
    );
  }

  Future<void> _createLocalMetadata(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSyncIndexes(DatabaseExecutor db) async {
    await db.execute('DROP INDEX IF EXISTS index_tasks_syncId');
    await db.execute('DROP INDEX IF EXISTS index_subtasks_syncId');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_tasks_syncId '
      "ON tasks (syncId) WHERE syncId IS NOT NULL AND syncId != ''",
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_subtasks_syncId '
      "ON subtasks (syncId) WHERE syncId IS NOT NULL AND syncId != ''",
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS index_tasks_syncStatus '
      'ON tasks (syncStatus)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS index_tasks_deletedAt '
      'ON tasks (deletedAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS index_subtasks_syncStatus '
      'ON subtasks (syncStatus)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS index_subtasks_deletedAt '
      'ON subtasks (deletedAt)',
    );
  }

  Future<void> _addSyncSchema(Database db) async {
    await _addColumnIfMissing(db, 'tasks', 'syncId', 'TEXT');
    await _addColumnIfMissing(
      db,
      'tasks',
      'ownerUserId',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'tasks',
      'visibility',
      "TEXT NOT NULL DEFAULT 'private'",
    );
    await _addColumnIfMissing(db, 'tasks', 'workspaceId', 'TEXT');
    await _addColumnIfMissing(
      db,
      'tasks',
      'createdByUserId',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'tasks',
      'updatedByUserId',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'tasks',
      'version',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      'tasks',
      'syncStatus',
      "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _addColumnIfMissing(db, 'tasks', 'deletedAt', 'INTEGER');
    await _addColumnIfMissing(db, 'tasks', 'purgeAfter', 'INTEGER');
    await _addColumnIfMissing(db, 'tasks', 'lastSyncedAt', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'tasks',
      'deviceId',
      "TEXT NOT NULL DEFAULT ''",
    );

    await _addColumnIfMissing(db, 'subtasks', 'syncId', 'TEXT');
    await _addColumnIfMissing(
      db,
      'subtasks',
      'taskSyncId',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'subtasks',
      'ownerUserId',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'subtasks',
      'visibility',
      "TEXT NOT NULL DEFAULT 'private'",
    );
    await _addColumnIfMissing(db, 'subtasks', 'workspaceId', 'TEXT');
    await _addColumnIfMissing(db, 'subtasks', 'updatedAt', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'subtasks',
      'version',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      'subtasks',
      'syncStatus',
      "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _addColumnIfMissing(db, 'subtasks', 'deletedAt', 'INTEGER');
    await _addColumnIfMissing(db, 'subtasks', 'purgeAfter', 'INTEGER');
    await _addColumnIfMissing(db, 'subtasks', 'lastSyncedAt', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'subtasks',
      'deviceId',
      "TEXT NOT NULL DEFAULT ''",
    );

    await _createSyncQueue(db);
  }

  Future<void> _addTaskReminderSchema(Database db) async {
    await _addColumnIfMissing(
      db,
      'tasks',
      'reminderOption',
      "TEXT NOT NULL DEFAULT 'none'",
    );
  }

  Future<void> _addTaskReminderValueSchema(Database db) async {
    await _addColumnIfMissing(db, 'tasks', 'reminderValue', 'INTEGER');
  }

  Future<void> _addSubTaskDueDateSchema(Database db) async {
    await _addColumnIfMissing(db, 'subtasks', 'dueDateTime', 'INTEGER');
  }

  Future<void> _addStarterContentSchema(Database db) async {
    await _addColumnIfMissing(
      db,
      'tasks',
      'isStarterContent',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _addSharedCompletionSchema(Database db) async {
    await _addColumnIfMissing(
      db,
      'tasks',
      'sharedCompletionMode',
      "TEXT NOT NULL DEFAULT 'single'",
    );
    await _addColumnIfMissing(
      db,
      'tasks',
      'completedByUserIds',
      "TEXT NOT NULL DEFAULT '[]'",
    );
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    String columnName,
    String columnDefinition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = columns.any((column) => column['name'] == columnName);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
      );
    }
  }

  Future<String> _loadOrCreateDeviceId() async {
    final rows = await _database.query(
      'local_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['device_id'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final storedDeviceId = rows.single['value'] as String;
      final deviceId = _normalizeDeviceId(
        storedDeviceId,
        fallback: _newSyncId(),
      );
      if (deviceId != storedDeviceId) {
        await _database.insert(
          'local_metadata',
          {'key': 'device_id', 'value': deviceId},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return deviceId;
    }

    final deviceId = _newSyncId();
    await _database.insert(
      'local_metadata',
      {'key': 'device_id', 'value': deviceId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return deviceId;
  }

  Future<void> _markEntitySynced(
    DatabaseExecutor db, {
    required String entityType,
    required String entitySyncId,
    required int syncedAt,
  }) async {
    final values = {
      'syncStatus': SyncStatus.synced.storedValue,
      'lastSyncedAt': syncedAt,
    };
    switch (entityType) {
      case 'task':
        await db.update(
          'tasks',
          values,
          where: 'syncId = ?',
          whereArgs: [entitySyncId],
        );
      case 'subtask':
        await db.update(
          'subtasks',
          values,
          where: 'syncId = ?',
          whereArgs: [entitySyncId],
        );
    }
  }

  String _encodeTaskPayload(
    TodoTask task, {
    Set<String> changedTaskFields = const {},
  }) {
    return jsonEncode({
      if (changedTaskFields.isNotEmpty)
        _changedTaskFieldsPayloadKey: changedTaskFields.toList()..sort(),
      'id': task.syncId,
      'owner_user_id': _normalizeUserId(task.ownerUserId),
      'visibility': task.visibility.storedValue,
      'title': task.title,
      'note': task.note,
      'category': task.category,
      'is_completed': task.isCompleted,
      'shared_completion_mode': task.sharedCompletionMode.storedValue,
      'completed_by_user_ids': task.completedByUserIds,
      'workspace_id': _normalizeWorkspaceId(task.workspaceId, task.visibility),
      'due_at': _dateToServerString(task.dueDateTime),
      'reminder_option': task.reminderOption.storedValue,
      'reminder_value': task.reminderValue,
      'created_at': _dateToServerString(task.createdAt),
      'updated_at': _dateToServerString(task.updatedAt),
      'version': task.version,
      'deleted_at': _dateToServerString(task.deletedAt),
      'purge_after': _dateToServerString(task.purgeAfter),
      'created_by_user_id': _normalizeUserId(task.createdByUserId),
      'updated_by_user_id': _normalizeUserId(task.updatedByUserId),
      'device_id': _normalizeDeviceId(task.deviceId),
      'subtasks': task.subTasks.map(_subTaskPayloadMap).toList(),
    });
  }

  Map<String, Object?> _subTaskPayloadMap(SubTask subTask) {
    return {
      'id': subTask.syncId,
      'task_id': subTask.taskSyncId,
      'title': subTask.title,
      'is_completed': subTask.isCompleted,
      'due_at': _dateToServerString(subTask.dueDateTime),
      'position': 0,
      'updated_at': _dateToServerString(subTask.updatedAt ?? subTask.createdAt),
      'version': subTask.version,
      'deleted_at': _dateToServerString(subTask.deletedAt),
    };
  }

  Future<void> _backfillSyncMetadata() async {
    await _database.transaction((transaction) async {
      final metadataRows = await transaction.query(
        'local_metadata',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [_syncMetadataBackfilledKey],
        limit: 1,
      );
      if (metadataRows.isNotEmpty && metadataRows.single['value'] == '1') {
        return;
      }

      final taskRows = await transaction.query('tasks');
      final taskSyncIds = <int, String>{};
      final taskBackfillIds = <int>{};
      final now = DateTime.now();

      for (final row in taskRows) {
        final id = row['id'] as int;
        final existingSyncId = row['syncId'] as String?;
        final syncId =
            existingSyncId?.isNotEmpty == true ? existingSyncId! : _newSyncId();
        final visibility = SyncVisibility.fromStoredValue(
          row['visibility'] as String?,
        );
        taskSyncIds[id] = syncId;
        final values = {
          'syncId': syncId,
          'ownerUserId': _normalizeUserId(
            (row['ownerUserId'] as String?)?.isNotEmpty == true
                ? row['ownerUserId'] as String
                : currentUserId,
          ),
          'visibility': row['visibility'] as String? ?? 'private',
          'workspaceId': _normalizeWorkspaceId(
            row['workspaceId'] as String?,
            visibility,
          ),
          'createdByUserId': _normalizeUserId(
            (row['createdByUserId'] as String?)?.isNotEmpty == true
                ? row['createdByUserId'] as String
                : currentUserId,
          ),
          'updatedByUserId': _normalizeUserId(
            (row['updatedByUserId'] as String?)?.isNotEmpty == true
                ? row['updatedByUserId'] as String
                : currentUserId,
          ),
          'version': row['version'] as int? ?? 1,
          'syncStatus': row['syncStatus'] as String? ?? 'pending',
          'deviceId': _normalizeDeviceId(row['deviceId'] as String?),
        };
        final changedValues = Map<String, Object?>.fromEntries(
          values.entries.where((entry) => row[entry.key] != entry.value),
        );
        if (changedValues.isNotEmpty) {
          await transaction.update(
            'tasks',
            changedValues,
            where: 'id = ?',
            whereArgs: [id],
          );
        }

        if (existingSyncId?.isNotEmpty != true) {
          taskBackfillIds.add(id);
        }
      }

      final subTaskRows = await transaction.query('subtasks');
      for (final row in subTaskRows) {
        final id = row['id'] as int;
        final taskId = row['taskId'] as int;
        final existingSyncId = row['syncId'] as String?;
        final syncId =
            existingSyncId?.isNotEmpty == true ? existingSyncId! : _newSyncId();
        final taskSyncId = (row['taskSyncId'] as String?)?.isNotEmpty == true
            ? row['taskSyncId'] as String
            : taskSyncIds[taskId] ?? '';
        final visibility = SyncVisibility.fromStoredValue(
          row['visibility'] as String?,
        );
        final values = {
          'syncId': syncId,
          'taskSyncId': taskSyncId,
          'ownerUserId': _normalizeUserId(
            (row['ownerUserId'] as String?)?.isNotEmpty == true
                ? row['ownerUserId'] as String
                : currentUserId,
          ),
          'visibility': row['visibility'] as String? ?? 'private',
          'workspaceId': _normalizeWorkspaceId(
            row['workspaceId'] as String?,
            visibility,
          ),
          'version': row['version'] as int? ?? 1,
          'syncStatus': row['syncStatus'] as String? ?? 'pending',
          'deviceId': _normalizeDeviceId(row['deviceId'] as String?),
        };
        final changedValues = Map<String, Object?>.fromEntries(
          values.entries.where((entry) => row[entry.key] != entry.value),
        );
        if (changedValues.isNotEmpty) {
          await transaction.update(
            'subtasks',
            changedValues,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      for (final taskId in taskBackfillIds) {
        final rows = await transaction.query(
          'tasks',
          where: 'id = ?',
          whereArgs: [taskId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final subTaskRows = await transaction.query(
          'subtasks',
          where: 'taskId = ? AND deletedAt IS NULL',
          whereArgs: [taskId],
        );
        final subTasks = subTaskRows.map(_subTaskFromMap).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final task = _taskFromMap(rows.single, subTasks);
        await _enqueueSync(
          transaction,
          entityType: 'task',
          entitySyncId: task.syncId,
          operation: 'upsert',
          payloadJson: _encodeTaskPayload(task),
          createdAt: now,
        );
      }

      await transaction.insert(
        'local_metadata',
        {'key': _syncMetadataBackfilledKey, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> _enqueueSync(
    DatabaseExecutor db, {
    required String entityType,
    required String entitySyncId,
    required String operation,
    String? payloadJson,
    required DateTime createdAt,
  }) async {
    if (entitySyncId.isEmpty) return;
    if (operation == 'purge') {
      await db.delete(
        'sync_queue',
        where: 'entityType = ? AND entitySyncId = ?',
        whereArgs: [entityType, entitySyncId],
      );
    } else if (operation == 'delete') {
      await db.delete(
        'sync_queue',
        where: 'entityType = ? AND entitySyncId = ? AND operation IN (?, ?)',
        whereArgs: [entityType, entitySyncId, 'upsert', 'delete'],
      );
    } else if (operation == 'upsert') {
      final existingUpsertRows = entityType == 'task'
          ? await db.query(
              'sync_queue',
              where: 'entityType = ? AND entitySyncId = ? AND operation = ?',
              whereArgs: [entityType, entitySyncId, 'upsert'],
              orderBy: 'id DESC',
              limit: 1,
            )
          : const <Map<String, Object?>>[];
      if (payloadJson != null && existingUpsertRows.isNotEmpty) {
        payloadJson = _mergeTaskPayloadJson(
          existingUpsertRows.single['payloadJson'] as String?,
          payloadJson,
        );
      }
      await db.delete(
        'sync_queue',
        where: 'entityType = ? AND entitySyncId = ? AND operation IN (?, ?)',
        whereArgs: [entityType, entitySyncId, 'upsert', 'delete'],
      );
    }
    await db.insert('sync_queue', {
      'entityType': entityType,
      'entitySyncId': entitySyncId,
      'operation': operation,
      'payloadJson': payloadJson,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'nextAttemptAt': createdAt.millisecondsSinceEpoch,
    });
  }

  String _mergeTaskPayloadJson(String? existingJson, String incomingJson) {
    final existing = _payloadMapFromJson(existingJson);
    final incoming = _payloadMapFromJson(incomingJson);
    if (existing == null || incoming == null) return incomingJson;

    final changedTaskFields = {
      ..._changedTaskFieldsFromPayload(existing),
      ..._changedTaskFieldsFromPayload(incoming),
    }.toList()
      ..sort();

    final subTasksBySyncId = <String, Map<String, Object?>>{};
    for (final subTask in _subtaskPayloadsFromPayload(existing)) {
      final syncId = subTask['id'] as String? ?? '';
      if (syncId.isNotEmpty) subTasksBySyncId[syncId] = subTask;
    }
    for (final subTask in _subtaskPayloadsFromPayload(incoming)) {
      final syncId = subTask['id'] as String? ?? '';
      if (syncId.isNotEmpty) subTasksBySyncId[syncId] = subTask;
    }

    final merged = Map<String, Object?>.from(incoming);
    if (changedTaskFields.isEmpty) {
      merged.remove(_changedTaskFieldsPayloadKey);
    } else {
      merged[_changedTaskFieldsPayloadKey] = changedTaskFields;
    }
    merged['subtasks'] = subTasksBySyncId.values.toList(growable: false);
    return jsonEncode(merged);
  }

  SyncQueueItem _syncQueueItemFromMap(Map<String, Object?> row) {
    return SyncQueueItem(
      id: row['id'] as int,
      entityType: row['entityType'] as String,
      entitySyncId: row['entitySyncId'] as String,
      operation: row['operation'] as String,
      payloadJson: row['payloadJson'] as String?,
      attemptCount: row['attemptCount'] as int,
      lastError: row['lastError'] as String?,
      createdAt: _dateFromMillis(row['createdAt'] as int)!,
      nextAttemptAt: _dateFromMillis(row['nextAttemptAt'] as int)!,
    );
  }

  Future<bool> _applySyncedTaskChange(
    DatabaseExecutor db,
    SyncedTaskChange change,
    DateTime syncedAt,
  ) async {
    final task = change.task;
    if (task.syncId.isEmpty) return false;

    final existingRows = await db.query(
      'tasks',
      where: 'syncId = ?',
      whereArgs: [task.syncId],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      return _applySyncedTask(
        db,
        task,
        syncedAt,
        pruneMissingSubtasks: false,
      );
    }

    final changedTaskFields = change.changedTaskFields.toSet();
    final changedSubtaskSyncIds = _effectiveChangedSubtaskSyncIds(change);
    await _removeOverlappingPendingTaskChanges(
      db,
      taskSyncId: task.syncId,
      changedTaskFields: changedTaskFields,
      changedSubtaskSyncIds: changedSubtaskSyncIds,
    );
    final hasPendingTaskQueue =
        await _hasPendingTaskQueue(db, taskSyncId: task.syncId);

    final existingTask = _taskFromMap(existingRows.single, const []);
    final mergedTask = _mergeSyncedTaskFields(
      existingTask,
      task,
      changedTaskFields: changedTaskFields,
      syncedAt: syncedAt,
      hasPendingTaskQueue: hasPendingTaskQueue,
    );
    await db.update(
      'tasks',
      _taskToMap(mergedTask),
      where: 'id = ?',
      whereArgs: [existingTask.id],
    );

    final existingSubTaskRows = await db.query(
      'subtasks',
      where: 'taskId = ?',
      whereArgs: [existingTask.id],
    );
    final existingSubTasksBySyncId = {
      for (final row in existingSubTaskRows)
        row['syncId'] as String? ?? '': row,
    };
    for (final subTask in task.subTasks) {
      if (!changedSubtaskSyncIds.contains(subTask.syncId)) continue;
      final existingSubTaskRow = existingSubTasksBySyncId[subTask.syncId];
      final syncedSubTask = subTask.copyWith(
        id: existingSubTaskRow == null ? 0 : existingSubTaskRow['id'] as int,
        taskId: existingTask.id,
        taskSyncId: task.syncId,
        ownerUserId: mergedTask.ownerUserId,
        visibility: mergedTask.visibility,
        workspaceId: mergedTask.workspaceId,
        createdAt: existingSubTaskRow == null
            ? subTask.createdAt
            : _dateFromMillis(existingSubTaskRow['createdAt'] as int?) ??
                subTask.createdAt,
        syncStatus: SyncStatus.synced,
        lastSyncedAt: syncedAt,
        deviceId: mergedTask.deviceId,
      );
      if (existingSubTaskRow == null) {
        await db.insert('subtasks', _subTaskToMap(syncedSubTask));
      } else {
        await db.update(
          'subtasks',
          _subTaskToMap(syncedSubTask),
          where: 'id = ?',
          whereArgs: [syncedSubTask.id],
        );
      }
    }

    return true;
  }

  Set<String> _effectiveChangedSubtaskSyncIds(SyncedTaskChange change) {
    return change.changedSubtaskSyncIds.toSet();
  }

  TodoTask _mergeSyncedTaskFields(
    TodoTask existing,
    TodoTask remote, {
    required Set<String> changedTaskFields,
    required DateTime syncedAt,
    required bool hasPendingTaskQueue,
  }) {
    var merged = existing.copyWith(
      syncStatus: hasPendingTaskQueue ? SyncStatus.pending : SyncStatus.synced,
      lastSyncedAt: syncedAt,
      isStarterContent: false,
    );
    for (final fieldName in changedTaskFields) {
      merged = _copySyncedTaskField(merged, remote, fieldName);
    }
    if (!hasPendingTaskQueue) {
      merged = merged.copyWith(
        version: remote.version,
        updatedAt: remote.updatedAt,
        updatedByUserId: remote.updatedByUserId,
        deviceId: remote.deviceId,
      );
    }
    return merged;
  }

  TodoTask _copySyncedTaskField(
    TodoTask target,
    TodoTask source,
    String fieldName,
  ) {
    switch (fieldName) {
      case 'owner_user_id':
        return target.copyWith(ownerUserId: source.ownerUserId);
      case 'visibility':
        return target.copyWith(visibility: source.visibility);
      case 'workspace_id':
        return target.copyWith(workspaceId: source.workspaceId);
      case 'created_by_user_id':
        return target.copyWith(createdByUserId: source.createdByUserId);
      case 'title':
        return target.copyWith(title: source.title);
      case 'note':
        return target.copyWith(note: source.note);
      case 'category':
        return target.copyWith(category: source.category);
      case 'is_completed':
        return target.copyWith(isCompleted: source.isCompleted);
      case 'shared_completion_mode':
        return target.copyWith(
          sharedCompletionMode: source.sharedCompletionMode,
        );
      case 'completed_by_user_ids':
        return target.copyWith(
          completedByUserIds: source.completedByUserIds,
        );
      case 'due_at':
        return target.copyWith(dueDateTime: source.dueDateTime);
      case 'reminder_option':
        return target.copyWith(reminderOption: source.reminderOption);
      case 'reminder_value':
        return target.copyWith(reminderValue: source.reminderValue);
      case 'deleted_at':
        return target.copyWith(
          deletedAt: source.deletedAt,
          purgeAfter: source.purgeAfter,
        );
    }
    return target;
  }

  Future<void> _removeOverlappingPendingTaskChanges(
    DatabaseExecutor db, {
    required String taskSyncId,
    required Set<String> changedTaskFields,
    required Set<String> changedSubtaskSyncIds,
  }) async {
    if (changedTaskFields.isEmpty && changedSubtaskSyncIds.isEmpty) return;
    final rows = await db.query(
      'sync_queue',
      where: 'entityType = ? AND entitySyncId = ?',
      whereArgs: ['task', taskSyncId],
    );
    for (final row in rows) {
      final payload = _payloadMapFromJson(row['payloadJson'] as String?);
      if (payload == null) continue;

      final pendingTaskFields = _changedTaskFieldsFromPayload(payload)
          .where((field) => !changedTaskFields.contains(field))
          .toList(growable: false);
      final pendingSubtasks =
          _subtaskPayloadsFromPayload(payload).where((subtask) {
        final syncId = subtask['id'] as String? ?? '';
        return !changedSubtaskSyncIds.contains(syncId);
      }).toList(growable: false);

      if (pendingTaskFields.isEmpty && pendingSubtasks.isEmpty) {
        await db.delete(
          'sync_queue',
          where: 'id = ?',
          whereArgs: [row['id'] as int],
        );
        continue;
      }

      if (pendingTaskFields.isEmpty) {
        payload.remove(_changedTaskFieldsPayloadKey);
      } else {
        payload[_changedTaskFieldsPayloadKey] = pendingTaskFields;
      }
      payload['subtasks'] = pendingSubtasks;
      await db.update(
        'sync_queue',
        {'payloadJson': jsonEncode(payload)},
        where: 'id = ?',
        whereArgs: [row['id'] as int],
      );
    }
  }

  Future<bool> _hasPendingTaskQueue(
    DatabaseExecutor db, {
    required String taskSyncId,
  }) async {
    final rows = await db.query(
      'sync_queue',
      columns: ['id'],
      where: 'entityType = ? AND entitySyncId = ?',
      whereArgs: ['task', taskSyncId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _applySyncedTask(
    DatabaseExecutor db,
    TodoTask task,
    DateTime syncedAt, {
    bool pruneMissingSubtasks = true,
  }) async {
    if (task.syncId.isEmpty) return false;

    final existingRows = await db.query(
      'tasks',
      where: 'syncId = ?',
      whereArgs: [task.syncId],
      limit: 1,
    );
    final existingRow = existingRows.isEmpty ? null : existingRows.single;

    final visibility = task.visibility;
    var syncedTask = task.copyWith(
      id: existingRow == null ? 0 : existingRow['id'] as int,
      ownerUserId: _normalizeUserId(task.ownerUserId),
      visibility: visibility,
      workspaceId: _normalizeWorkspaceId(task.workspaceId, visibility),
      createdByUserId: _normalizeUserId(task.createdByUserId),
      updatedByUserId: _normalizeUserId(task.updatedByUserId),
      syncStatus: SyncStatus.synced,
      lastSyncedAt: syncedAt,
      deviceId: _normalizeDeviceId(task.deviceId),
      isStarterContent: false,
    );

    final taskId = existingRow == null
        ? await db.insert('tasks', _taskToMap(syncedTask))
        : existingRow['id'] as int;
    if (existingRow != null) {
      await db.update(
        'tasks',
        _taskToMap(syncedTask),
        where: 'id = ?',
        whereArgs: [taskId],
      );
    }
    syncedTask = syncedTask.copyWith(id: taskId);

    final existingSubTaskRows = await db.query(
      'subtasks',
      where: 'taskId = ?',
      whereArgs: [taskId],
    );
    final existingSubTasksBySyncId = {
      for (final row in existingSubTaskRows)
        row['syncId'] as String? ?? '': row,
    };
    final retainedSubTaskSyncIds = <String>{};

    for (final subTask in task.subTasks) {
      if (subTask.syncId.isEmpty) continue;
      retainedSubTaskSyncIds.add(subTask.syncId);
      final existingSubTaskRow = existingSubTasksBySyncId[subTask.syncId];

      final syncedSubTask = subTask.copyWith(
        id: existingSubTaskRow == null ? 0 : existingSubTaskRow['id'] as int,
        taskId: taskId,
        taskSyncId: syncedTask.syncId,
        ownerUserId: syncedTask.ownerUserId,
        visibility: syncedTask.visibility,
        workspaceId: syncedTask.workspaceId,
        createdAt: existingSubTaskRow == null
            ? subTask.createdAt
            : _dateFromMillis(existingSubTaskRow['createdAt'] as int?) ??
                subTask.createdAt,
        syncStatus: SyncStatus.synced,
        lastSyncedAt: syncedAt,
        deviceId: syncedTask.deviceId,
      );
      if (existingSubTaskRow == null) {
        await db.insert('subtasks', _subTaskToMap(syncedSubTask));
      } else {
        await db.update(
          'subtasks',
          _subTaskToMap(syncedSubTask),
          where: 'id = ?',
          whereArgs: [syncedSubTask.id],
        );
      }
    }

    if (pruneMissingSubtasks) {
      for (final row in existingSubTaskRows) {
        final syncId = row['syncId'] as String? ?? '';
        if (retainedSubTaskSyncIds.contains(syncId)) continue;
        await db.delete(
          'subtasks',
          where: 'id = ?',
          whereArgs: [row['id'] as int],
        );
      }
    }

    return true;
  }

  Future<void> _markSubTasksSynced(
    DatabaseExecutor db, {
    required Set<String> subTaskSyncIds,
    required int syncedAt,
  }) async {
    if (subTaskSyncIds.isEmpty) return;
    await db.update(
      'subtasks',
      {
        'syncStatus': SyncStatus.synced.storedValue,
        'lastSyncedAt': syncedAt,
      },
      where:
          "syncId IN (${List.filled(subTaskSyncIds.length, '?').join(', ')})",
      whereArgs: subTaskSyncIds.toList(growable: false),
    );
  }

  Set<String> _subTaskSyncIdsFromPayloadJson(String? payloadJson) {
    final payload = _payloadMapFromJson(payloadJson);
    if (payload == null) return const {};
    return _subtaskPayloadsFromPayload(payload)
        .map((subtask) => subtask['id'] as String? ?? '')
        .where((syncId) => syncId.isNotEmpty)
        .toSet();
  }

  Map<String, Object?>? _payloadMapFromJson(String? payloadJson) {
    if (payloadJson == null) return null;
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return null;
  }

  List<String> _changedTaskFieldsFromPayload(Map<String, Object?> payload) {
    final value = payload[_changedTaskFieldsPayloadKey];
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  List<Map<String, Object?>> _subtaskPayloadsFromPayload(
    Map<String, Object?> payload,
  ) {
    final value = payload['subtasks'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  String _normalizeUserId(String? value) {
    final appUserId = normalizeAppUserId(value);
    if (appUserId == defaultCurrentUserId || appUserId == partnerUserId) {
      return appUserId;
    }
    if (isUuidLike(value)) return value!;
    return defaultCurrentUserId;
  }

  String? _normalizeWorkspaceId(String? value, SyncVisibility visibility) {
    if (visibility == SyncVisibility.privateItem) return null;
    if (value == defaultSharedWorkspaceId || value == 'personal_shared') {
      return defaultSharedWorkspaceId;
    }
    if (isUuidLike(value)) return value;
    return isUuidLike(sharedWorkspaceId)
        ? sharedWorkspaceId
        : defaultSharedWorkspaceId;
  }

  String _normalizeDeviceId(String? value, {String? fallback}) {
    if (isUuidLike(value)) return value!;
    const legacyPrefix = 'device-';
    if (value != null && value.startsWith(legacyPrefix)) {
      final withoutPrefix = value.substring(legacyPrefix.length);
      if (isUuidLike(withoutPrefix)) return withoutPrefix;
    }
    return fallback ?? _deviceId;
  }

  String? _dateToServerString(DateTime? value) {
    return value?.toUtc().toIso8601String();
  }

  bool _sameDateTime(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  String _newSyncId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hexByte(int value) => value.toRadixString(16).padLeft(2, '0');
    final hex = bytes.map(hexByte).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  DateTime? _dateFromMillis(int? value) {
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
