import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import 'local_todo_repository.dart';
import 'native_widget_bridge.dart';
import 'settings_controller.dart';
import 'settings_store.dart';
import 'task_notification_service.dart';
import 'todo_sync_service.dart';

const backgroundRefreshInterval = Duration(hours: 2);
const widgetRefreshTaskName = 'com.example.personaltodo.widget_refresh';
const widgetActionTaskName = 'com.example.personaltodo.widget_action';

@pragma('vm:entry-point')
void widgetRefreshDispatcher() {
  Future<bool>? active;
  Workmanager().executeTask((task, _) async {
    if (task == widgetActionTaskName || task == widgetRefreshTaskName) {
      final running = MobileBackgroundSync.run();
      active = running;
      final result = await running;
      return task == widgetActionTaskName ? result : true;
    }
    // Failed changes remain in SQLite; avoid frequent background wake-ups.
    return true;
  }, onTaskStopped: (_, _) async {
    // WorkManager can stop a worker while its Dart callback is still running.
    // Let finally blocks release SQLite locks before destroying that engine;
    // sqflite's Android plugin keeps native connections after engine detach.
    await active;
  });
}

@pragma('vm:entry-point')
Future<void> phoneWidgetAction(Uri? action) async {
  await MobileBackgroundSync.run();
}

class MobileBackgroundSync {
  static Future<void> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    await Workmanager().initialize(widgetRefreshDispatcher);
    await Workmanager().registerPeriodicTask(
      widgetRefreshTaskName,
      widgetRefreshTaskName,
      frequency: backgroundRefreshInterval,
      initialDelay: backgroundRefreshInterval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(NativeWidgetBridge.phoneAppGroupId);
      try {
        await HomeWidget.registerInteractivityCallback(phoneWidgetAction);
      } on PlatformException catch (error) {
        if (error.code != '-5') rethrow; // iOS 15/16 widgets open the app.
      }
    }
  }

  static Future<bool> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    final settings =
        SettingsController(store: SettingsStore(singleInstance: false));
    LocalTodoRepository? repository;
    var settingsInitialized = false;
    var repositoryInitialized = false;
    try {
      await settings.init(legacyMigrationSucceeded: false);
      settingsInitialized = true;
      repository = LocalTodoRepository(
        currentUserId: settings.currentUserId,
        singleInstance: false,
      );
      await repository.init(refreshNativeWidget: false);
      repositoryInitialized = true;
      await consumePhoneWidgetActions(repository);
      // Show the saved completion before waiting for the server.
      await NativeWidgetBridge.refreshHomeWidget(
        tasks: repository.tasks,
        languageCode: settings.language.languageCode,
        themeMode: settings.themeMode.storedValue,
        currentUserId: settings.currentUserId,
      );
      if (settings.refreshToken.isNotEmpty) {
        try {
          await TodoSyncService(repository: repository, settings: settings)
              .syncNow();
        } on Object catch (error) {
          // The edit is already saved; network failures use the sync queue.
          debugPrint('Background sync deferred: $error');
        }
      }
      return true;
    } on Object catch (error) {
      debugPrint('Background widget save deferred: $error');
      return false;
    } finally {
      try {
        if (repositoryInitialized) {
          try {
            await repository!.reload(refreshNativeWidget: false);
            await TaskNotificationService.syncTasks(
              activeTasks: repository.tasks,
              trashTasks: repository.trashTasks,
              language: settings.language,
              timeFormat: settings.timeFormat,
            );
            await NativeWidgetBridge.refreshHomeWidget(
              tasks: repository.tasks,
              languageCode: settings.language.languageCode,
              themeMode: settings.themeMode.storedValue,
              currentUserId: settings.currentUserId,
            );
          } finally {
            await repository!.close();
          }
        }
      } finally {
        if (settingsInitialized) await settings.close();
      }
    }
  }

  static Future<void> consumePhoneWidgetActions(
      LocalTodoRepository repository) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    String? directoryPath;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(NativeWidgetBridge.phoneAppGroupId);
      }
      directoryPath = await HomeWidget.getWidgetData<String>(
          'todo_widget_action_directory');
    } on MissingPluginException {
      return;
    }
    if (directoryPath == null) return;
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return;
    final actions = <(File, Map<String, dynamic>)>[];
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        final action = jsonDecode(await file.readAsString());
        if (action is Map<String, dynamic> &&
            action['id'] is String &&
            (action['id'] as String).isNotEmpty &&
            action['taskId'] is int &&
            (action['taskId'] as int) > 0 &&
            action['completed'] is bool &&
            (action['subTaskId'] == null ||
                (action['subTaskId'] is int &&
                    (action['subTaskId'] as int) > 0 &&
                    action['completed'] == true)) &&
            (action['userId'] == null || action['userId'] is String) &&
            action['createdAtMillis'] is num) {
          actions.add((file, action));
        }
      } on FileSystemException {
        // Another engine may have consumed this file already.
      } on FormatException {
        // A damaged action must not prevent the app from opening.
      }
    }
    actions.sort((a, b) => (a.$2['createdAtMillis'] as num)
        .compareTo(b.$2['createdAtMillis'] as num));
    for (final (file, action) in actions) {
      if (action['userId'] != null &&
          action['userId'] != repository.currentUserId) {
        continue;
      }
      await repository.reload(refreshNativeWidget: false);
      final subTaskId = action['subTaskId'] as int?;
      if (subTaskId != null) {
        await repository.markSubTaskDoneById(action['taskId'] as int, subTaskId,
            actionId: action['id'] as String);
      } else {
        await repository.setTaskCompletionById(action['taskId'] as int,
            isCompleted: action['completed'] as bool,
            actionId: action['id'] as String);
      }
      try {
        await file.delete();
      } on FileSystemException {
        // Another engine may have acknowledged this same idempotent action.
      }
    }
  }
}
