import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/task_notification_service.dart';
import 'package:personaltodo/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('computes at-start reminder trigger', () {
    final dueAt = DateTime(2026, 6, 8, 13, 30);

    expect(
      TaskNotificationService.reminderTriggerTime(
        TodoTask(
          id: 1,
          title: 'Task',
          dueDateTime: dueAt,
          reminderOption: TaskReminderOption.atStart,
        ),
        now: DateTime(2026, 6, 8, 12),
      ),
      dueAt,
    );
  });

  test('computes before-time reminder triggers', () {
    final dueAt = DateTime(2026, 6, 8, 13, 30);

    expect(
      TaskNotificationService.reminderTriggerTime(
        TodoTask(
          id: 1,
          title: 'Task',
          dueDateTime: dueAt,
          reminderOption: TaskReminderOption.beforeMinutes,
          reminderValue: 15,
        ),
        now: DateTime(2026, 6, 8, 12),
      ),
      DateTime(2026, 6, 8, 13, 15),
    );
    expect(
      TaskNotificationService.reminderTriggerTime(
        TodoTask(
          id: 1,
          title: 'Task',
          dueDateTime: dueAt,
          reminderOption: TaskReminderOption.beforeHours,
          reminderValue: 2,
        ),
        now: DateTime(2026, 6, 8, 10),
      ),
      DateTime(2026, 6, 8, 11, 30),
    );
  });

  test('computes start-of-day reminder trigger', () {
    expect(
      TaskNotificationService.reminderTriggerTime(
        TodoTask(
          id: 1,
          title: 'Task',
          dueDateTime: DateTime(2026, 6, 8, 13, 30),
          reminderOption: TaskReminderOption.startOfDay,
          reminderValue: 8 * 60 + 15,
        ),
        now: DateTime(2026, 6, 8, 8),
      ),
      DateTime(2026, 6, 8, 8, 15),
    );
  });

  test('does not schedule missing, disabled, or past reminders', () {
    final now = DateTime(2026, 6, 8, 12);

    expect(
      TaskNotificationService.reminderTriggerTime(
        TodoTask(
          id: 1,
          title: 'Task',
          reminderOption: TaskReminderOption.atStart,
        ),
        now: now,
      ),
      isNull,
    );
    expect(
      TaskNotificationService.reminderTriggerTime(
        TodoTask(
          id: 1,
          title: 'Task',
          dueDateTime: DateTime(2026, 6, 8, 13),
          reminderOption: TaskReminderOption.none,
        ),
        now: now,
      ),
      isNull,
    );
    expect(
      TaskNotificationService.reminderTriggerTime(
        TodoTask(
          id: 1,
          title: 'Task',
          dueDateTime: DateTime(2026, 6, 8, 11),
          reminderOption: TaskReminderOption.atStart,
        ),
        now: now,
      ),
      isNull,
    );
  });

  test('schedules active reminders and cancels completed reminders', () async {
    const channel = MethodChannel(
      'com.example.personaltodo/task_notifications',
    );
    final calls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final dueAt = DateTime.now().add(const Duration(hours: 1));
    final activeTask = TodoTask(
      id: 7,
      title: 'Review alarm',
      dueDateTime: dueAt,
      reminderOption: TaskReminderOption.atStart,
    );
    await TaskNotificationService.syncTask(
      language: AppLanguage.english,
      timeFormat: AppTimeFormat.amPm,
      task: activeTask,
    );
    await TaskNotificationService.syncTask(
      language: AppLanguage.english,
      timeFormat: AppTimeFormat.amPm,
      task: TodoTask(
        id: 8,
        title: 'Completed alarm',
        isCompleted: true,
        dueDateTime: dueAt,
        reminderOption: TaskReminderOption.atStart,
      ),
    );

    expect(calls, hasLength(2));
    expect(calls[0].method, 'scheduleTaskReminder');
    expect(calls[0].arguments, containsPair('notificationId', 7));
    expect(
      calls[0].arguments,
      containsPair(
        'body',
        TaskNotificationService.notificationBodyForTask(
          activeTask,
          language: AppLanguage.english,
          timeFormat: AppTimeFormat.amPm,
        ),
      ),
    );
    expect(calls[1].method, 'cancelTaskReminder');
    expect(calls[1].arguments, containsPair('notificationId', 8));
  });

  test('formats reminder body with task title and due detail', () {
    expect(
      TaskNotificationService.notificationBodyForTask(
        TodoTask(
          id: 1,
          title: 'Review alarm',
          dueDateTime: DateTime(2026, 6, 8, 13, 30),
        ),
        language: AppLanguage.english,
        timeFormat: AppTimeFormat.twentyFourHour,
      ),
      'Review alarm\n13:30',
    );
    expect(
      TaskNotificationService.notificationBodyForTask(
        TodoTask(
          id: 2,
          title: '마감 확인',
          dueDateTime: DateTime(2026, 6, 8),
        ),
        language: AppLanguage.korean,
        timeFormat: AppTimeFormat.amPm,
      ),
      '마감 확인\n6월 8일',
    );
  });
}
