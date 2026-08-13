import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class NativeWidgetBridge {
  static const openNewTaskAction = 'open_new_task';
  static const completeTaskAction = 'complete_task';
  static const toggleTaskCompletionAction = 'toggle_task_completion';
  static const completeSubTaskAction = 'complete_subtask';

  static const _channel = MethodChannel(
    'com.example.personaltodo/widget_actions',
  );

  static Timer? _macActionPoller;
  static bool _isConsumingMacActions = false;
  static List<TodoTask>? _lastMacWidgetTasks;
  static String _macWidgetLanguageCode = 'ko';
  static String _macWidgetThemeMode = 'LIGHT';
  static String _macWidgetCurrentUserId = defaultCurrentUserId;
  static Future<void> Function(String, Map<String, Object?>)? _actionHandler;

  static Future<String?> consumeInitialAction() async {
    if (!_isAndroid) return null;

    try {
      final action = await _channel.invokeMethod<Object?>(
        'consumeInitialAction',
      );
      if (action is String) return action;

      final handler = _actionHandler;
      if (handler == null) return null;
      final arguments = _mapFromAction(action);
      final type = arguments['type'] as String?;
      if (type != null) {
        await handler(type, arguments);
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static void setActionHandler(
    FutureOr<void> Function(String action, Map<String, Object?> arguments)
        onAction,
  ) {
    _actionHandler = (action, arguments) async {
      await onAction(action, arguments);
    };

    if (_isMacOS) {
      _startMacActionPolling();
      return;
    }

    if (!_isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openNewTask':
          await onAction(openNewTaskAction, const {});
          return null;
        case 'widgetAction':
          final arguments = _mapFromAction(call.arguments);
          final type = arguments['type'] as String?;
          if (type != null) {
            await onAction(type, arguments);
          }
          return null;
        default:
          throw MissingPluginException(
            'No handler for native widget method ${call.method}',
          );
      }
    });
  }

  static Future<void> refreshHomeWidget({
    List<TodoTask>? tasks,
    String? languageCode,
    String? themeMode,
    String? currentUserId,
  }) async {
    if (!_isAndroid && !_isMacOS) return;

    if (languageCode != null) {
      _macWidgetLanguageCode = languageCode;
    }
    if (themeMode != null) {
      _macWidgetThemeMode = themeMode;
    }
    if (currentUserId != null) {
      _macWidgetCurrentUserId = normalizeAppUserId(currentUserId);
    }

    try {
      if (_isAndroid) {
        await _channel.invokeMethod<void>('refreshWidget');
      } else {
        if (tasks != null) {
          _lastMacWidgetTasks = List<TodoTask>.of(tasks);
        }

        final snapshotTasks = tasks ?? _lastMacWidgetTasks;
        if (snapshotTasks == null) {
          await _channel.invokeMethod<void>('reloadWidget');
          return;
        }

        await _channel.invokeMethod<void>(
          'updateWidgetSnapshot',
          _macWidgetSnapshotJson(snapshotTasks),
        );
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static String _macWidgetSnapshotJson(List<TodoTask> tasks) {
    final openTasks = tasks.where((task) => !task.isCompleted).toList()
      ..sort(_compareTasksForWidget);
    final calendarDueDates = _calendarDueDateMillis(openTasks);

    return jsonEncode({
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
      'languageCode': _macWidgetLanguageCode,
      'themeMode': _macWidgetThemeMode,
      'openTaskCount': openTasks.length,
      'calendarDueDates': calendarDueDates,
      'tasks': [
        for (final task in openTasks.take(8))
          {
            'id': task.syncId.isNotEmpty ? task.syncId : task.id.toString(),
            'databaseId': task.id,
            'title': task.title,
            'requiresBothSharedCompletion': task.requiresBothSharedCompletion,
            'isPartiallyCompleted': task.isPartiallyCompleted,
            'isCompletedByCurrentUser':
                task.isCompletedByUser(_macWidgetCurrentUserId),
            'dueAtMillis': task.dueDateTime?.millisecondsSinceEpoch,
            'subTasks': [
              for (final subTask in task.subTasks
                  .where((subTask) => !subTask.isCompleted)
                  .take(2))
                {
                  'id': subTask.syncId.isNotEmpty
                      ? subTask.syncId
                      : subTask.id.toString(),
                  'databaseId': subTask.id,
                  'title': subTask.title,
                  'dueAtMillis': subTask.dueDateTime?.millisecondsSinceEpoch,
                },
            ],
          },
      ],
    });
  }

  static List<int> _calendarDueDateMillis(Iterable<TodoTask> tasks) {
    final dates = <int>{};

    for (final task in tasks) {
      final taskDueDate = task.dueDateTime;
      if (taskDueDate != null) {
        dates.add(_startOfDayMillis(taskDueDate));
      }

      for (final subTask in task.subTasks) {
        final subTaskDueDate = subTask.dueDateTime;
        if (!subTask.isCompleted && subTaskDueDate != null) {
          dates.add(_startOfDayMillis(subTaskDueDate));
        }
      }
    }

    return dates.toList()..sort();
  }

  static int _startOfDayMillis(DateTime date) {
    return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
  }

  static void _startMacActionPolling() {
    _macActionPoller ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_consumePendingMacWidgetActions()),
    );
  }

  static Future<void> consumePendingWidgetActions() async {
    if (_isAndroid) {
      await _consumePendingPlatformWidgetActions();
    } else if (_isMacOS) {
      await _consumePendingMacWidgetActions();
    }
  }

  static Future<void> _consumePendingPlatformWidgetActions() async {
    final handler = _actionHandler;
    if (handler == null) return;

    try {
      final actions = await _channel.invokeMethod<List<dynamic>>(
            'consumePendingWidgetActions',
          ) ??
          const <dynamic>[];

      for (final action in actions) {
        final arguments = _mapFromAction(action);
        final type = arguments['type'] as String?;
        if (type == null) continue;
        await handler(type, arguments);
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> _consumePendingMacWidgetActions() async {
    if (!_isMacOS || _isConsumingMacActions) return;
    final handler = _actionHandler;
    if (handler == null) return;

    _isConsumingMacActions = true;
    try {
      final actions = await _channel.invokeMethod<List<dynamic>>(
            'consumePendingWidgetActions',
          ) ??
          const <dynamic>[];

      for (final action in actions) {
        final arguments = _mapFromAction(action);
        final type = arguments['type'] as String?;
        if (type == null) continue;
        await handler(type, arguments);
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } finally {
      _isConsumingMacActions = false;
    }
  }

  static Map<String, Object?> _mapFromAction(Object? action) {
    if (action is! Map) return const {};
    return {
      for (final entry in action.entries) entry.key.toString(): entry.value,
    };
  }

  static int _compareTasksForWidget(TodoTask first, TodoTask second) {
    final firstDue = first.dueDateTime;
    final secondDue = second.dueDateTime;
    if (firstDue != null && secondDue != null) {
      final dueComparison = firstDue.compareTo(secondDue);
      if (dueComparison != 0) return dueComparison;
    } else if (firstDue != null) {
      return -1;
    } else if (secondDue != null) {
      return 1;
    }

    return first.title.toLowerCase().compareTo(second.title.toLowerCase());
  }

  static bool get _isAndroid {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  static bool get _isMacOS {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  }
}
