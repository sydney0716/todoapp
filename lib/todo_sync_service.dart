import 'api/todo_api_client.dart';
import 'api/todo_api_models.dart';
import 'local_todo_repository.dart';
import 'models.dart';
import 'settings_controller.dart';
import 'sync_contract.dart';

typedef TodoSyncRunner = Future<TodoSyncResult> Function();
typedef TodoApiClientFactory = TodoApiClient Function(String baseUrl);

const _taskPushBatchSize = 25;

class TodoSyncService {
  TodoSyncService({
    required this.repository,
    required this.settings,
    TodoApiClientFactory? clientFactory,
  }) : _clientFactory =
            clientFactory ?? ((baseUrl) => TodoApiClient(baseUrl: baseUrl));

  final LocalTodoRepository repository;
  final SettingsController settings;
  final TodoApiClientFactory _clientFactory;
  static final Map<_SyncScope, Future<TodoSyncResult>> _activeSyncs = {};

  Future<TodoSyncResult> syncNow({bool reconcileSnapshot = false}) async {
    final syncScope = _SyncScope(repository, settings);
    final activeSync = _activeSyncs[syncScope];
    if (activeSync != null) return activeSync;

    final sync = _syncWithLock(reconcileSnapshot: reconcileSnapshot);
    _activeSyncs[syncScope] = sync;
    return sync.whenComplete(() {
      if (identical(_activeSyncs[syncScope], sync)) {
        _activeSyncs.remove(syncScope);
      }
    });
  }

  Future<TodoSyncResult> _syncWithLock(
      {required bool reconcileSnapshot}) async {
    final result = await repository.withSyncLock(() async {
      // A background engine may have rotated tokens or advanced the cursor.
      await settings.reload();
      repository.currentUserId = settings.currentUserId;
      await repository.reload(refreshNativeWidget: false);
      return _syncNow(reconcileSnapshot: reconcileSnapshot);
    });
    if (result == null) {
      throw const TodoSyncBusyException();
    }
    return result;
  }

  Future<TodoSyncResult> _syncNow({required bool reconcileSnapshot}) async {
    if (settings.refreshToken.isEmpty) {
      throw const TodoSyncException('Connect to the server first.');
    }
    if (settings.authDeviceId.isNotEmpty &&
        settings.authDeviceId != repository.deviceId) {
      throw const TodoSyncException(
        'Reconnect this device before syncing.',
      );
    }

    final client = _clientFactory(settings.apiBaseUrl);
    var accessToken = settings.accessToken;
    var pushedCount = 0;
    var failedCount = 0;

    try {
      await repository.moveExpiredCompletedTasksToTrash(
        settings.completedTaskRetentionPolicy,
      );
      await repository.purgeExpiredTrash();

      final pendingTaskItems = await repository.getPendingSyncQueue(
        now: DateTime.now(),
        entityTypes: {'task'},
      );
      final pendingTaskPushes = <_PendingTaskPush>[];

      for (final item in pendingTaskItems) {
        final payload = decodeSyncPayload(item.payloadJson);
        if (payload == null) {
          await repository.markSyncQueueItemFailed(
            item.id,
            'Invalid task sync payload for operation: ${item.operation}',
          );
          failedCount += 1;
          continue;
        }
        final changedTaskFields = changedTaskFieldsFromPayload(payload);
        final changedSubtaskSyncIds = _changedSubtaskSyncIdsFor(payload);
        final record = Map<String, Object?>.of(payload)
          ..remove(changedTaskFieldsPayloadKey);

        pendingTaskPushes.add(
          _PendingTaskPush(
            queueItem: item,
            change: SyncTaskChange(
              operation: item.operation,
              record: record,
              changedTaskFields: changedTaskFields,
              changedSubtaskIds: changedSubtaskSyncIds,
            ),
            changedTaskFields: changedTaskFields,
            changedSubtaskSyncIds: changedSubtaskSyncIds,
          ),
        );
      }

      for (final batch in _taskPushBatches(pendingTaskPushes)) {
        try {
          final result = await _withFreshAccessToken(
            client,
            accessToken,
            (token) => client.pushTaskChanges(
              accessToken: token,
              deviceId: repository.deviceId,
              changes: batch.map((push) => push.change).toList(),
            ),
          );
          accessToken = result.accessToken;
          final push = result.value;
          final acceptedBySyncId = {
            for (final record in push.accepted) record.id: record,
          };
          final acceptedChanges = <SyncedTaskAcknowledgement>[];

          for (final pendingPush in batch) {
            final acceptedRecord =
                acceptedBySyncId[pendingPush.queueItem.entitySyncId];
            if (acceptedRecord == null) continue;

            pushedCount += 1;
            acceptedChanges.add(SyncedTaskAcknowledgement(
              queueItemId: pendingPush.queueItem.id,
              operation: pendingPush.queueItem.operation,
              task: acceptedRecord.toTodoTask(),
            ));
          }

          if (acceptedChanges.isNotEmpty) {
            await repository.acknowledgeTaskChanges(acceptedChanges);
          }

          await repository.applyPurgedTaskIds(push.purgedIds);
          if (acceptedBySyncId.length + push.purgedIds.length < batch.length ||
              push.rejected.isNotEmpty) {
            final message = push.rejected.isEmpty
                ? 'Server did not accept the task change.'
                : push.rejected.join(', ');
            for (final pendingPush in batch) {
              if (acceptedBySyncId
                      .containsKey(pendingPush.queueItem.entitySyncId) ||
                  push.purgedIds.contains(pendingPush.queueItem.entitySyncId)) {
                continue;
              }
              await repository.markSyncQueueItemFailed(
                pendingPush.queueItem.id,
                message,
              );
              failedCount += 1;
            }
          }
        } on Object catch (error) {
          for (final pendingPush in batch) {
            await repository.markSyncQueueItemFailed(
              pendingPush.queueItem.id,
              error.toString(),
            );
            failedCount += 1;
          }
        }
      }

      var cursor = settings.lastSyncCursor;
      var pulledCount = 0;
      // Bound each response and persist each successfully applied page. A later
      // failure can resume without losing progress or monopolizing foreground I/O.
      for (var page = 0; page < 20; page++) {
        final pullResult = await _withFreshAccessToken(
            client,
            accessToken,
            (token) =>
                client.pullTaskChanges(accessToken: token, cursor: cursor));
        accessToken = pullResult.accessToken;
        final pull = pullResult.value;
        pulledCount += await repository.applySyncedChanges(pull.changes
            .map(_syncedTaskChangeFromRemote)
            .toList(growable: false));
        if (pull.hasMore && pull.cursor == cursor) {
          throw const TodoSyncException(
              'Server returned a non-advancing sync cursor.');
        }
        cursor = pull.cursor;
        await settings.recordSyncSuccess(cursor: cursor);
        if (!pull.hasMore) break;
      }
      await repository.moveExpiredCompletedTasksToTrash(
        settings.completedTaskRetentionPolicy,
      );
      var snapshotReconciled = false;

      if (reconcileSnapshot && failedCount == 0) {
        final bootstrapResult = await _withFreshAccessToken(
          client,
          accessToken,
          (token) => client.bootstrap(accessToken: token),
        );
        accessToken = bootstrapResult.accessToken;
        final bootstrap = bootstrapResult.value;
        await repository.reconcileBootstrapTasks(
          bootstrap.tasks.map((task) => task.toTodoTask()).toList(),
        );
        await repository.moveExpiredCompletedTasksToTrash(
          settings.completedTaskRetentionPolicy,
        );
        cursor = bootstrap.cursor;
        snapshotReconciled = true;
      }

      await settings.recordSyncSuccess(cursor: cursor);

      return TodoSyncResult(
        pushedCount: pushedCount,
        pulledCount: pulledCount,
        failedCount: failedCount,
        cursor: cursor,
        snapshotReconciled: snapshotReconciled,
      );
    } finally {
      client.close();
    }
  }

  Iterable<List<_PendingTaskPush>> _taskPushBatches(
    List<_PendingTaskPush> pushes,
  ) sync* {
    for (var start = 0; start < pushes.length; start += _taskPushBatchSize) {
      final end = start + _taskPushBatchSize;
      yield pushes.sublist(
        start,
        end > pushes.length ? pushes.length : end,
      );
    }
  }

  List<String> _changedSubtaskSyncIdsFor(Map<String, Object?> payload) {
    final subtasks = payload['subtasks'];
    if (subtasks is! List) return const [];
    return subtasks
        .whereType<Map>()
        .map((subtask) => subtask['id'])
        .whereType<String>()
        .toList(growable: false);
  }

  SyncedTaskChange _syncedTaskChangeFromRemote(RemoteTaskChange change) {
    return SyncedTaskChange(
      operation: change.operation,
      task: change.record.toTodoTask(),
      changedTaskFields: change.changedTaskFields,
      changedSubtaskSyncIds: change.changedSubtaskIds,
    );
  }

  Future<_AuthorizedResult<T>> _withFreshAccessToken<T>(
    TodoApiClient client,
    String accessToken,
    Future<T> Function(String accessToken) request,
  ) async {
    if (accessToken.isNotEmpty) {
      try {
        final value = await request(accessToken);
        return _AuthorizedResult(value: value, accessToken: accessToken);
      } on TodoApiException catch (error) {
        if (error.statusCode != 401) rethrow;
      }
    }

    if (settings.refreshToken.isEmpty) {
      throw const TodoSyncException(
          'Sign in again to sync. Your tasks are available offline.');
    }
    late final AuthSession session;
    try {
      session = await client.refresh(
          refreshToken: settings.refreshToken, deviceId: repository.deviceId);
    } on TodoApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await settings.requireReauthentication();
        throw const TodoSyncException(
            'Sign in again to sync. Your tasks are available offline.');
      }
      rethrow;
    }
    await settings.recordAuthSession(session);
    final value = await request(session.accessToken);
    return _AuthorizedResult(value: value, accessToken: session.accessToken);
  }
}

class TodoSyncResult {
  const TodoSyncResult({
    required this.pushedCount,
    required this.pulledCount,
    required this.failedCount,
    required this.cursor,
    this.snapshotReconciled = false,
  });

  final int pushedCount;
  final int pulledCount;
  final int failedCount;
  final String cursor;
  final bool snapshotReconciled;
}

class _SyncScope {
  const _SyncScope(this.repository, this.settings);

  final LocalTodoRepository repository;
  final SettingsController settings;

  @override
  bool operator ==(Object other) {
    return other is _SyncScope &&
        identical(repository, other.repository) &&
        identical(settings, other.settings);
  }

  @override
  int get hashCode => Object.hash(
        identityHashCode(repository),
        identityHashCode(settings),
      );
}

class _PendingTaskPush {
  const _PendingTaskPush({
    required this.queueItem,
    required this.change,
    required this.changedTaskFields,
    required this.changedSubtaskSyncIds,
  });

  final SyncQueueItem queueItem;
  final SyncTaskChange change;
  final List<String> changedTaskFields;
  final List<String> changedSubtaskSyncIds;
}

class TodoSyncException implements Exception {
  const TodoSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TodoSyncBusyException extends TodoSyncException {
  const TodoSyncBusyException()
      : super('Sync is already running. Try again shortly.');
}

class _AuthorizedResult<T> {
  const _AuthorizedResult({
    required this.value,
    required this.accessToken,
  });

  final T value;
  final String accessToken;
}
