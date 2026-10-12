import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/todo_sync_coordinator.dart';
import 'package:personaltodo/todo_sync_service.dart';

const result =
    TodoSyncResult(pushedCount: 0, pulledCount: 0, failedCount: 0, cursor: '1');

void main() {
  testWidgets('Mac background waits two hours but sends new edits promptly',
      (tester) async {
    final repository = _QueueRepository();
    var calls = 0;
    final sync = TodoSyncCoordinator(
      repository: repository,
      settings: SettingsController()..refreshToken = 'refresh',
      backgroundPollInterval: const Duration(hours: 2),
      runner: (_) async {
        calls++;
        repository.queue = [];
        return result;
      },
    )..start();
    await tester.pump(const Duration(milliseconds: 600));
    sync.setForeground(false);
    await tester.pump(const Duration(minutes: 119));
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 2);
    repository.queue = [_item(DateTime.now())];
    repository.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 3);
    expect(repository.queue, isEmpty);
    sync.dispose();
  });

  testWidgets('network hints do not cause idle Mac background pulls',
      (tester) async {
    final connection = StreamController<bool>();
    addTearDown(connection.close);
    var calls = 0;
    final sync = TodoSyncCoordinator(
      repository: _QueueRepository(),
      settings: SettingsController()..refreshToken = 'refresh',
      connectivityChanges: connection.stream,
      backgroundPollInterval: const Duration(hours: 2),
      runner: (_) async {
        calls++;
        return result;
      },
    )..start();
    await tester.pump(const Duration(milliseconds: 600));
    sync.setForeground(false);
    connection.add(true);
    await tester.pump();
    expect(calls, 1);
    sync.dispose();
  });

  testWidgets('polls every 30 seconds while active and stops in the background',
      (tester) async {
    var calls = 0;
    final sync = TodoSyncCoordinator(
      repository: _QueueRepository(),
      settings: SettingsController()..refreshToken = 'refresh',
      runner: (_) async {
        calls++;
        return result;
      },
    )..start();
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 29400));
    expect(calls, 2);
    sync.setForeground(false);
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 2);
    sync.dispose();
  });

  testWidgets(
      'connection recovery releases failed uploads without another edit',
      (tester) async {
    final connection = StreamController<bool>();
    addTearDown(connection.close);
    final repository = _QueueRepository()
      ..queue = [_item(DateTime.now().add(const Duration(hours: 1)))];
    var calls = 0;
    final sync = TodoSyncCoordinator(
      repository: repository,
      settings: SettingsController()..refreshToken = 'refresh',
      connectivityChanges: connection.stream,
      runner: (_) async {
        calls++;
        if (calls > 1) repository.queue = [];
        return result;
      },
    )..start();
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 1);
    connection.add(false);
    await tester.pump();
    expect(calls, 1);
    connection.add(true);
    await tester.pump();
    expect(repository.retryCount, 1);
    expect(calls, 2);
    expect(repository.queue, isEmpty);
    connection.add(true);
    await tester.pump();
    expect(calls, 2);
    sync.dispose();
  });

  testWidgets(
      'a paused phone waits for resume before retrying recovered network',
      (tester) async {
    final connection = StreamController<bool>();
    addTearDown(connection.close);
    var calls = 0;
    final sync = TodoSyncCoordinator(
      repository: _QueueRepository(),
      settings: SettingsController()..refreshToken = 'refresh',
      connectivityChanges: connection.stream,
      runner: (_) async {
        calls++;
        return result;
      },
    )..start();
    sync.setForeground(false);
    connection.add(true);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 0);
    sync.setForeground(true);
    await tester.pump();
    expect(calls, 1);
    sync.dispose();
  });

  test('a full refresh requested during an edit sync runs before it resolves',
      () async {
    final first = Completer<TodoSyncResult>();
    final calls = <bool>[];
    final repository = _QueueRepository();
    final sync = TodoSyncCoordinator(
        repository: repository,
        settings: SettingsController()..refreshToken = 'refresh',
        runner: (snapshot) {
          calls.add(snapshot);
          return calls.length == 1 ? first.future : Future.value(result);
        });
    addTearDown(sync.dispose);
    final editSync = sync.syncNow();
    final refresh = sync.syncNow(reconcileSnapshot: true);
    first.complete(result);
    await refresh;
    await editSync;
    expect(calls, [false, true]);
  });

  test('a failed queued change retries without another edit', () async {
    final repository = _QueueRepository();
    final retried = Completer<void>();
    var calls = 0;
    final sync = TodoSyncCoordinator(
        repository: repository,
        settings: SettingsController()..refreshToken = 'refresh',
        editDelay: const Duration(milliseconds: 10),
        runner: (_) async {
          calls++;
          if (calls == 1) {
            repository.queue = [
              _item(DateTime.now().add(const Duration(milliseconds: 60)))
            ];
            repository.notifyListeners();
            return const TodoSyncResult(
                pushedCount: 0, pulledCount: 0, failedCount: 1, cursor: '1');
          }
          repository.queue = [];
          repository.notifyListeners();
          retried.complete();
          return result;
        })
      ..start();
    addTearDown(sync.dispose);
    await sync.syncNow();
    await retried.future.timeout(const Duration(seconds: 2));
    expect(calls, 2);
  });
}

SyncQueueItem _item(DateTime attempt) => SyncQueueItem(
    id: 1,
    entityType: 'task',
    entitySyncId: 'task',
    operation: 'upsert',
    payloadJson: '{}',
    attemptCount: 1,
    lastError: 'offline',
    createdAt: DateTime.now(),
    nextAttemptAt: attempt);

class _QueueRepository extends LocalTodoRepository {
  List<SyncQueueItem> queue = [];
  int retryCount = 0;
  @override
  Future<int> retryFailedSyncQueueNow() async {
    retryCount++;
    final count = queue.length;
    queue = queue.map((item) => _item(DateTime.now())).toList();
    return count;
  }

  @override
  String get deviceId => 'test-device';
  @override
  Future<List<SyncQueueItem>> getPendingSyncQueue(
          {int? limit, DateTime? now, Set<String>? entityTypes}) async =>
      queue;
}
