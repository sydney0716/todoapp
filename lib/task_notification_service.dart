import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_strings.dart';
import 'date_formatting.dart';
import 'models.dart';
import 'settings_controller.dart';

class TaskNotificationService {
  static const _channel = MethodChannel(
    'com.example.personaltodo/task_notifications',
  );

  static final lastError = ValueNotifier<String?>(null);
  static final _knownIds = <int>{};
  static final _scheduledContents = <int, List<Object>>{};
  static Future<void> _reconciliation = Future.value();

  static Future<void> syncTasks({
    required Iterable<TodoTask> activeTasks,
    required Iterable<TodoTask> trashTasks,
    required AppLanguage language,
    required AppTimeFormat timeFormat,
    bool force = false,
  }) {
    if (kIsWeb) return Future.value();
    final active = activeTasks.toList();
    final trash = trashTasks.toList();
    _reconciliation = _reconciliation.catchError((Object _) {}).then((_) async {
      lastError.value = null;
      final desiredIds = active
          .where((task) =>
              !task.isCompleted &&
              task.deletedAt == null &&
              reminderTriggerTime(task) != null)
          .map(notificationIdForTask)
          .toSet();
      try {
        final persisted =
            await _channel.invokeListMethod<int>('getScheduledTaskReminderIds');
        if (persisted != null) {
          _scheduledContents.removeWhere((id, _) => !persisted.contains(id));
          _knownIds.addAll(persisted);
        }
        for (final id in _knownIds.difference(desiredIds).toList()) {
          await _cancelId(id);
        }
      } on MissingPluginException {
        // Unsupported platforms can still use the app without reminders.
      } on PlatformException catch (error) {
        lastError.value = error.message ?? error.code;
      }
      for (final task in active) {
        await syncTask(
            task: task,
            language: language,
            timeFormat: timeFormat,
            force: force);
      }
      for (final task in trash) {
        await cancelTask(task);
      }
    });
    return _reconciliation;
  }

  static Future<void> syncTask({
    required TodoTask task,
    required AppLanguage language,
    required AppTimeFormat timeFormat,
    bool force = false,
  }) async {
    if (kIsWeb) return;
    final triggerAt = reminderTriggerTime(task);
    if (triggerAt == null || task.isCompleted || task.deletedAt != null) {
      await cancelTask(task);
      return;
    }

    final strings = AppStrings.forLanguage(language);
    final id = notificationIdForTask(task);
    final body = notificationBodyForTask(
      task,
      language: language,
      timeFormat: timeFormat,
    );
    final contents = <Object>[
      strings.appTitle,
      body,
      triggerAt.millisecondsSinceEpoch,
    ];
    if (!force && listEquals(_scheduledContents[id], contents)) return;
    try {
      await _channel.invokeMethod<void>('scheduleTaskReminder', {
        'notificationId': id,
        'title': strings.appTitle,
        'body': body,
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
      });
      _knownIds.add(id);
      _scheduledContents[id] = contents;
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      lastError.value = error.message ?? error.code;
    }
  }

  static Future<void> cancelTask(TodoTask task) =>
      _cancelId(notificationIdForTask(task));

  static Future<void> _cancelId(int id) async {
    if (kIsWeb) return;
    try {
      await _channel
          .invokeMethod<void>('cancelTaskReminder', {'notificationId': id});
      _knownIds.remove(id);
      _scheduledContents.remove(id);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      lastError.value = error.message ?? error.code;
    }
  }

  static int notificationIdForTask(TodoTask task) {
    if (task.id > 0) return task.id;
    final source = task.syncId.isEmpty ? task.title : task.syncId;
    return max(1, source.hashCode & 0x7fffffff);
  }

  static String notificationBodyForTask(
    TodoTask task, {
    required AppLanguage language,
    required AppTimeFormat timeFormat,
  }) {
    final dueAt = task.dueDateTime;
    if (dueAt == null) return task.title;

    final dueText = _hasExplicitDueTime(dueAt)
        ? formatTimeOfDay(dueAt, timeFormat, language: language)
        : formatListDueDate(dueAt, language: language);
    return '${task.title}\n$dueText';
  }

  static DateTime? reminderTriggerTime(TodoTask task, {DateTime? now}) {
    final dueAt = task.dueDateTime;
    if (dueAt == null || task.reminderOption == TaskReminderOption.none) {
      return null;
    }

    final triggerAt = switch (task.reminderOption) {
      TaskReminderOption.none => null,
      TaskReminderOption.atStart => dueAt,
      TaskReminderOption.beforeMinutes => dueAt.subtract(
          Duration(minutes: task.reminderValue ?? 5),
        ),
      TaskReminderOption.beforeHours => dueAt.subtract(
          Duration(hours: task.reminderValue ?? 1),
        ),
      TaskReminderOption.startOfDay => _startOfDayTriggerTime(
          dueAt,
          task.reminderValue,
        ),
    };

    final resolvedTriggerAt = triggerAt;
    if (resolvedTriggerAt == null) return null;
    if (!resolvedTriggerAt.isAfter(now ?? DateTime.now())) return null;
    return resolvedTriggerAt;
  }

  static DateTime _startOfDayTriggerTime(DateTime dueAt, int? value) {
    final minutesAfterMidnight = (value ?? (9 * 60)).clamp(0, 1439).toInt();
    return DateTime(
      dueAt.year,
      dueAt.month,
      dueAt.day,
      minutesAfterMidnight ~/ 60,
      minutesAfterMidnight % 60,
    );
  }

  static bool _hasExplicitDueTime(DateTime dueAt) {
    return dueAt.hour != 0 ||
        dueAt.minute != 0 ||
        dueAt.second != 0 ||
        dueAt.millisecond != 0 ||
        dueAt.microsecond != 0;
  }
}
