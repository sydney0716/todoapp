import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/mobile_background_sync.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/task_notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('phone widget action survives restart and replay without toggling back',
      () async {
    final directory = await Directory.systemTemp.createTemp('phone_widget_');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      if (call.method == 'getWidgetData') return directory.path;
      return true;
    });
    addTearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
      await directory.delete(recursive: true);
    });
    var repository =
        LocalTodoRepository(databasePath: '${directory.path}/tasks.db');
    await repository.init(refreshNativeWidget: false);
    await repository.upsertTask(TodoTask(title: 'From phone widget'));
    final taskId = repository.tasks.single.id;
    final action = jsonEncode({
      'id': 'durable-action',
      'taskId': taskId,
      'completed': true,
      'createdAtMillis': 1,
    });
    final pending = File('${directory.path}/action.json');
    await pending.writeAsString(action);
    await repository.close();
    repository =
        LocalTodoRepository(databasePath: '${directory.path}/tasks.db');
    await repository.init(refreshNativeWidget: false);
    await MobileBackgroundSync.consumePhoneWidgetActions(repository);
    expect(repository.tasks.single.isCompleted, isTrue);
    expect(await pending.exists(), isFalse);
    final count = (await repository.getPendingSyncQueue()).length;
    await pending.writeAsString(action);
    await File('${directory.path}/damaged.json').writeAsString('{bad');
    await MobileBackgroundSync.consumePhoneWidgetActions(repository);
    expect(repository.tasks.single.isCompleted, isTrue);
    expect((await repository.getPendingSyncQueue()).length, count);
    expect(await pending.exists(), isFalse);
    await repository.close();
  });

  group('Android background widget actions', () {
    late Directory directory;
    late Directory actions;
    late String previousDatabasePath;
    late LocalTodoRepository repository;
    final widgetCalls = <String>[];

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('android_widget_');
      actions =
          await Directory('${directory.path}/todo_widget_actions').create();
      previousDatabasePath = await getDatabasesPath();
      await databaseFactory.setDatabasesPath(directory.path);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      widgetCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'),
              (call) async {
        widgetCalls.add(call.method);
        if (call.method == 'getWidgetData') return actions.path;
        return true;
      });
      repository = LocalTodoRepository(singleInstance: false);
      await repository.init(refreshNativeWidget: false);
    });

    tearDown(() async {
      await repository.close();
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
      await databaseFactory.setDatabasesPath(previousDatabasePath);
      await directory.delete(recursive: true);
    });

    Future<File> enqueue(String id, int taskId,
        {bool completed = true,
        int? subTaskId,
        int createdAt = 1,
        String userId = defaultCurrentUserId}) async {
      return File('${actions.path}/$id.json').writeAsString(jsonEncode({
        'id': id,
        'taskId': taskId,
        'completed': completed,
        if (subTaskId != null) 'subTaskId': subTaskId,
        'userId': userId,
        'createdAtMillis': createdAt,
      }));
    }

    test('saves offline and refreshes the widget without the main activity',
        () async {
      await repository.upsertTask(TodoTask(title: 'Offline widget task'));
      final id = repository.tasks.single.id;
      final pending = await enqueue('complete', id);
      widgetCalls.clear();

      expect(await MobileBackgroundSync.run(), isTrue);
      await repository.reload(refreshNativeWidget: false);
      expect(repository.tasks.single.isCompleted, isTrue);
      expect((await repository.getPendingSyncQueue()).single.payloadJson,
          contains('"is_completed":true'));
      expect(await pending.exists(), isFalse);
      expect(widgetCalls, contains('updateWidget'));
    });

    test('background changes cancel old reminders and schedule new reminder times',
        () async {
      final calls = <MethodCall>[];
      const notifications = MethodChannel('com.example.personaltodo/task_notifications');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call);
        return call.method == 'getScheduledTaskReminderIds' ? <int>[] : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(notifications, null));
      final now = DateTime.now();
      await repository.upsertTask(TodoTask(title: 'Complete elsewhere',
          dueDateTime: now.add(const Duration(hours: 1)), reminderOption: TaskReminderOption.atStart));
      final completedId = repository.tasks.single.id;
      await TaskNotificationService.syncTasks(activeTasks: repository.tasks,
          trashTasks: [], language: AppLanguage.korean, timeFormat: AppTimeFormat.amPm);
      await enqueue('complete-reminder', completedId);
      calls.clear();
      expect(await MobileBackgroundSync.run(), isTrue);
      expect(calls.where((call) => call.method == 'cancelTaskReminder')
          .any((call) => (call.arguments as Map)['notificationId'] == completedId), isTrue);
      await repository.reload(refreshNativeWidget: false);
      final nextTime = now.add(const Duration(hours: 3));
      await repository.upsertTask(TodoTask(title: 'Rescheduled elsewhere',
          dueDateTime: nextTime, reminderOption: TaskReminderOption.atStart));
      calls.clear();
      expect(await MobileBackgroundSync.run(), isTrue);
      expect(calls.where((call) => call.method == 'scheduleTaskReminder')
          .any((call) => (call.arguments as Map)['triggerAtMillis'] == nextTime.millisecondsSinceEpoch), isTrue);
    });

    test('subtask completion survives restart and replay', () async {
      await repository.upsertTask(TodoTask(
        title: 'Parent',
        subTasks: [SubTask(title: 'Child')],
      ));
      final task = repository.tasks.single;
      final pending =
          await enqueue('child', task.id, subTaskId: task.subTasks.single.id);
      await repository.close();
      repository = LocalTodoRepository(singleInstance: false);
      await repository.init(refreshNativeWidget: false);
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      expect(repository.tasks.single.subTasks.single.isCompleted, isTrue);
      expect(repository.tasks.single.isCompleted, isFalse);
      expect(await pending.exists(), isFalse);
      final payload =
          (await repository.getPendingSyncQueue()).single.payloadJson;
      await enqueue('child', task.id, subTaskId: task.subTasks.single.id);
      await File('${actions.path}/bad.json').writeAsString('{bad');
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      expect(
          (await repository.getPendingSyncQueue()).single.payloadJson, payload);
      expect(await pending.exists(), isFalse);
    });

    test(
        'Both task taps set the requested state and preserve partner completion',
        () async {
      await repository.upsertTask(TodoTask(
        title: 'Both',
        note: 'Unsynced note',
        visibility: SyncVisibility.shared,
        sharedCompletionMode: SharedCompletionMode.both,
        completedByUserIds: [partnerUserId],
      ));
      final id = repository.tasks.single.id;
      await enqueue('check', id);
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      expect(repository.tasks.single.isCompleted, isTrue);
      // Reversed filenames still apply taps in time order.
      await enqueue('z-uncheck', id, completed: false, createdAt: 2);
      await enqueue('a-check', id, createdAt: 3);
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      expect(repository.tasks.single.isCompleted, isTrue);
      await enqueue('uncheck-final', id, completed: false, createdAt: 4);
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      await enqueue('a-check', id, createdAt: 3);
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      expect(repository.tasks.single.isCompleted, isFalse);
      expect(repository.tasks.single.completedByUserIds, [partnerUserId]);
      final payload = jsonDecode(
          (await repository.getPendingSyncQueue()).single.payloadJson!);
      expect(payload['note'], 'Unsynced note');
      expect(payload['completed_by_user_ids'], [partnerUserId]);
    });

    test('queued tap stays with its original account after switching users',
        () async {
      await repository.upsertTask(TodoTask(
        title: 'Both',
        visibility: SyncVisibility.shared,
        sharedCompletionMode: SharedCompletionMode.both,
      ));
      final pending = await enqueue('partner', repository.tasks.single.id,
          userId: partnerUserId);
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      expect(await pending.exists(), isTrue);
      expect(repository.tasks.single.completedByUserIds, isEmpty);
      repository.currentUserId = partnerUserId;
      await MobileBackgroundSync.consumePhoneWidgetActions(repository);
      expect(repository.tasks.single.completedByUserIds, [partnerUserId]);
      expect(repository.tasks.single.isCompleted, isFalse);
      expect(await pending.exists(), isFalse);
    });
  });
}
