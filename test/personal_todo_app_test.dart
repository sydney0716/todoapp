import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/main.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/todo_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs periodic sync on resume after six hours', (tester) async {
    final repository = _FakeAppRepository();
    final settings = _connectedSettings()
      ..lastSyncAt = DateTime.now().subtract(const Duration(hours: 7));
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

  testWidgets('skips periodic sync on resume before six hours', (tester) async {
    final repository = _FakeAppRepository();
    final settings = _connectedSettings()
      ..lastSyncAt = DateTime.now().subtract(const Duration(hours: 1));
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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(repository.reloadCount, 1);
    expect(syncCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

SettingsController _connectedSettings() {
  return SettingsController()
    ..initialLoginCompleted = true
    ..serverConnectionStatus = ServerConnectionStatus.connected
    ..refreshToken = 'refresh-token';
}

class _FakeAppRepository extends LocalTodoRepository {
  _FakeAppRepository();

  int reloadCount = 0;

  @override
  String get deviceId => 'test-device';

  @override
  List<TodoTask> get tasks => const [];

  @override
  List<TodoTask> get trashTasks => const [];

  @override
  Future<void> reload({bool refreshNativeWidget = true}) async {
    reloadCount += 1;
    notifyListeners();
  }
}
