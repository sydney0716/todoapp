import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'app_strings.dart';
import 'date_formatting.dart';
import 'models.dart';
import 'settings_controller.dart';

class TaskNotificationService {
  static const _channel = MethodChannel(
    'com.example.personaltodo/task_notifications',
  );

  static Future<void> syncTasks({
    required Iterable<TodoTask> activeTasks,
    required Iterable<TodoTask> trashTasks,
    required AppLanguage language,
    required AppTimeFormat timeFormat,
  }) async {
    for (final task in activeTasks) {
      await syncTask(
        task: task,
        language: language,
        timeFormat: timeFormat,
      );
    }
    for (final task in trashTasks) {
      await cancelTask(task);
    }
  }

  static Future<void> syncTask({
    required TodoTask task,
    required AppLanguage language,
    required AppTimeFormat timeFormat,
  }) async {
    final triggerAt = reminderTriggerTime(task);
    if (triggerAt == null || task.isCompleted || task.deletedAt != null) {
      await cancelTask(task);
      return;
    }

    final strings = AppStrings.forLanguage(language);
    try {
      await _channel.invokeMethod<void>('scheduleTaskReminder', {
        'notificationId': notificationIdForTask(task),
        'title': strings.appTitle,
        'body': notificationBodyForTask(
          task,
          language: language,
          timeFormat: timeFormat,
        ),
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> cancelTask(TodoTask task) async {
    try {
      await _channel.invokeMethod<void>('cancelTaskReminder', {
        'notificationId': notificationIdForTask(task),
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
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
