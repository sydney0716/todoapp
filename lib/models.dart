enum SyncVisibility {
  privateItem('private'),
  shared('shared');

  const SyncVisibility(this.storedValue);

  final String storedValue;

  static SyncVisibility fromStoredValue(String? value) {
    return SyncVisibility.values.firstWhere(
      (visibility) => visibility.storedValue == value,
      orElse: () => SyncVisibility.privateItem,
    );
  }
}

enum SharedCompletionMode {
  single('single'),
  both('both');

  const SharedCompletionMode(this.storedValue);

  final String storedValue;

  static SharedCompletionMode fromStoredValue(String? value) {
    return SharedCompletionMode.values.firstWhere(
      (mode) => mode.storedValue == value,
      orElse: () => SharedCompletionMode.single,
    );
  }
}

const defaultCurrentUserId = '00000000-0000-4000-8000-000000000001';
const partnerUserId = '00000000-0000-4000-8000-000000000002';
const defaultSharedWorkspaceId = '00000000-0000-4000-8000-000000000100';
const sharedCompletionUserIds = [defaultCurrentUserId, partnerUserId];

final RegExp _uuidLikePattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
  r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

bool isUuidLike(String? value) {
  if (value == null) return false;
  return _uuidLikePattern.hasMatch(value);
}

String normalizeAppUserId(String? value) {
  if (value == partnerUserId || value == 'user2' || value == 'partner') {
    return partnerUserId;
  }
  if (value == defaultCurrentUserId || value == 'user1' || value == 'user') {
    return defaultCurrentUserId;
  }
  if (isUuidLike(value)) return value!;
  return defaultCurrentUserId;
}

List<String> _normalizedCompletionUserIds(Iterable<String> userIds) {
  final normalized = userIds.map(normalizeAppUserId).toSet();
  return [
    for (final userId in sharedCompletionUserIds)
      if (normalized.remove(userId)) userId,
    ...normalized.toList()..sort(),
  ];
}

class AppAccount {
  const AppAccount({
    required this.id,
    required this.label,
    required this.username,
  });

  final String id;
  final String label;
  final String username;
}

const appAccounts = [
  AppAccount(
    id: defaultCurrentUserId,
    label: 'User 1',
    username: 'user1',
  ),
  AppAccount(
    id: partnerUserId,
    label: 'User 2',
    username: 'user2',
  ),
];

enum CompletedTaskRetentionPolicy {
  oneMonth('1_month', '1 month', Duration(days: 30)),
  sixMonths('6_months', '6 months', Duration(days: 183)),
  twelveMonths('12_months', '12 months', Duration(days: 365));

  const CompletedTaskRetentionPolicy(
    this.storedValue,
    this.label,
    this.duration,
  );

  final String storedValue;
  final String label;
  final Duration duration;

  DateTime trashAfter(DateTime completedAt) {
    return completedAt.add(duration);
  }

  static CompletedTaskRetentionPolicy fromStoredValue(String? value) {
    return CompletedTaskRetentionPolicy.values.firstWhere(
      (policy) => policy.storedValue == value,
      orElse: () => CompletedTaskRetentionPolicy.oneMonth,
    );
  }
}

enum SyncStatus {
  synced('synced'),
  pending('pending');

  const SyncStatus(this.storedValue);

  final String storedValue;

  static SyncStatus fromStoredValue(String? value) {
    return SyncStatus.values.firstWhere(
      (status) => status.storedValue == value,
      orElse: () => SyncStatus.pending,
    );
  }
}

enum TaskReminderOption {
  none('none', 'no alarm'),
  atStart('at_start', 'start'),
  beforeMinutes('before_minutes', 'before 5 min'),
  beforeHours('before_hours', 'before 1 hour'),
  startOfDay('start_of_day', 'start of day');

  const TaskReminderOption(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static TaskReminderOption fromStoredValue(String? value) {
    switch (value) {
      case 'before_5_minutes':
      case 'before_10_minutes':
      case 'before_30_minutes':
        return TaskReminderOption.beforeMinutes;
      case 'before_1_hour':
      case 'before_2_hours':
        return TaskReminderOption.beforeHours;
    }
    return TaskReminderOption.values.firstWhere(
      (option) => option.storedValue == value,
      orElse: () => TaskReminderOption.none,
    );
  }

  static int? valueFromStoredValue(String? value) {
    switch (value) {
      case 'before_10_minutes':
        return 10;
      case 'before_30_minutes':
        return 30;
      case 'before_2_hours':
        return 2;
    }
    return null;
  }
}

class SubTask {
  SubTask({
    this.id = 0,
    this.taskId = 0,
    this.syncId = '',
    this.taskSyncId = '',
    this.ownerUserId = '',
    this.visibility = SyncVisibility.privateItem,
    this.workspaceId,
    required this.title,
    this.isCompleted = false,
    this.dueDateTime,
    DateTime? createdAt,
    this.updatedAt,
    this.version = 1,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
    this.purgeAfter,
    this.lastSyncedAt,
    this.deviceId = '',
  }) : createdAt = createdAt ?? DateTime.now();

  final int id;
  final int taskId;
  final String syncId;
  final String taskSyncId;
  final String ownerUserId;
  final SyncVisibility visibility;
  final String? workspaceId;
  final String title;
  final bool isCompleted;
  final DateTime? dueDateTime;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int version;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;
  final DateTime? purgeAfter;
  final DateTime? lastSyncedAt;
  final String deviceId;

  SubTask copyWith({
    int? id,
    int? taskId,
    String? syncId,
    String? taskSyncId,
    String? ownerUserId,
    SyncVisibility? visibility,
    Object? workspaceId = _unset,
    String? title,
    bool? isCompleted,
    Object? dueDateTime = _unset,
    DateTime? createdAt,
    Object? updatedAt = _unset,
    int? version,
    SyncStatus? syncStatus,
    Object? deletedAt = _unset,
    Object? purgeAfter = _unset,
    Object? lastSyncedAt = _unset,
    String? deviceId,
  }) {
    return SubTask(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      syncId: syncId ?? this.syncId,
      taskSyncId: taskSyncId ?? this.taskSyncId,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      visibility: visibility ?? this.visibility,
      workspaceId:
          workspaceId == _unset ? this.workspaceId : workspaceId as String?,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      dueDateTime:
          dueDateTime == _unset ? this.dueDateTime : dueDateTime as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime?,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      purgeAfter:
          purgeAfter == _unset ? this.purgeAfter : purgeAfter as DateTime?,
      lastSyncedAt: lastSyncedAt == _unset
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}

const _unset = Object();

class TodoTask {
  TodoTask({
    this.id = 0,
    this.syncId = '',
    this.ownerUserId = '',
    this.visibility = SyncVisibility.privateItem,
    this.workspaceId,
    this.createdByUserId = '',
    this.updatedByUserId = '',
    required this.title,
    this.note = '',
    this.category = '',
    this.isCompleted = false,
    this.sharedCompletionMode = SharedCompletionMode.single,
    Iterable<String> completedByUserIds = const [],
    this.dueDateTime,
    this.reminderOption = TaskReminderOption.none,
    this.reminderValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.version = 1,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
    this.purgeAfter,
    this.lastSyncedAt,
    this.deviceId = '',
    this.isStarterContent = false,
    this.subTasks = const [],
  })  : createdAt = createdAt ?? DateTime.now(),
        completedByUserIds = _normalizedCompletionUserIds(completedByUserIds),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final int id;
  final String syncId;
  final String ownerUserId;
  final SyncVisibility visibility;
  final String? workspaceId;
  final String createdByUserId;
  final String updatedByUserId;
  final String title;
  final String note;
  final String category;
  final bool isCompleted;
  final SharedCompletionMode sharedCompletionMode;
  final List<String> completedByUserIds;
  final DateTime? dueDateTime;
  final TaskReminderOption reminderOption;
  final int? reminderValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;
  final DateTime? purgeAfter;
  final DateTime? lastSyncedAt;
  final String deviceId;
  final bool isStarterContent;
  final List<SubTask> subTasks;

  bool get requiresBothSharedCompletion {
    return visibility == SyncVisibility.shared &&
        sharedCompletionMode == SharedCompletionMode.both;
  }

  List<String> get effectiveCompletedByUserIds {
    if (requiresBothSharedCompletion &&
        isCompleted &&
        completedByUserIds.isEmpty) {
      return sharedCompletionUserIds;
    }
    return completedByUserIds;
  }

  bool get isPartiallyCompleted {
    return requiresBothSharedCompletion &&
        !isCompleted &&
        effectiveCompletedByUserIds.isNotEmpty;
  }

  bool isCompletedByUser(String userId) {
    return effectiveCompletedByUserIds.contains(normalizeAppUserId(userId));
  }

  TodoTask toggledCompletionForUser(
    String userId, {
    DateTime? updatedAt,
  }) {
    final normalizedUserId = normalizeAppUserId(userId);
    final changedAt = updatedAt ?? DateTime.now();

    if (requiresBothSharedCompletion) {
      final completedBy = effectiveCompletedByUserIds.toSet();
      if (completedBy.contains(normalizedUserId)) {
        completedBy.remove(normalizedUserId);
      } else {
        completedBy.add(normalizedUserId);
      }
      final isFullyCompleted = sharedCompletionUserIds.every(
        completedBy.contains,
      );
      return copyWith(
        isCompleted: isFullyCompleted,
        completedByUserIds: _normalizedCompletionUserIds(completedBy),
        updatedAt: changedAt,
      );
    }

    final nextCompleted = !isCompleted;
    return copyWith(
      isCompleted: nextCompleted,
      completedByUserIds: visibility == SyncVisibility.shared && nextCompleted
          ? [normalizedUserId]
          : const <String>[],
      updatedAt: changedAt,
    );
  }

  TodoTask copyWith({
    int? id,
    String? syncId,
    String? ownerUserId,
    SyncVisibility? visibility,
    Object? workspaceId = _unset,
    String? createdByUserId,
    String? updatedByUserId,
    String? title,
    String? note,
    String? category,
    bool? isCompleted,
    SharedCompletionMode? sharedCompletionMode,
    List<String>? completedByUserIds,
    Object? dueDateTime = _unset,
    TaskReminderOption? reminderOption,
    Object? reminderValue = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    SyncStatus? syncStatus,
    Object? deletedAt = _unset,
    Object? purgeAfter = _unset,
    Object? lastSyncedAt = _unset,
    String? deviceId,
    bool? isStarterContent,
    List<SubTask>? subTasks,
  }) {
    return TodoTask(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      visibility: visibility ?? this.visibility,
      workspaceId:
          workspaceId == _unset ? this.workspaceId : workspaceId as String?,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      updatedByUserId: updatedByUserId ?? this.updatedByUserId,
      title: title ?? this.title,
      note: note ?? this.note,
      category: category ?? this.category,
      isCompleted: isCompleted ?? this.isCompleted,
      sharedCompletionMode: sharedCompletionMode ?? this.sharedCompletionMode,
      completedByUserIds: completedByUserIds ?? this.completedByUserIds,
      dueDateTime:
          dueDateTime == _unset ? this.dueDateTime : dueDateTime as DateTime?,
      reminderOption: reminderOption ?? this.reminderOption,
      reminderValue:
          reminderValue == _unset ? this.reminderValue : reminderValue as int?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      purgeAfter:
          purgeAfter == _unset ? this.purgeAfter : purgeAfter as DateTime?,
      lastSyncedAt: lastSyncedAt == _unset
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      deviceId: deviceId ?? this.deviceId,
      isStarterContent: isStarterContent ?? this.isStarterContent,
      subTasks: subTasks ?? this.subTasks,
    );
  }
}

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entitySyncId,
    required this.operation,
    this.payloadJson,
    required this.attemptCount,
    this.lastError,
    required this.createdAt,
    required this.nextAttemptAt,
  });

  final int id;
  final String entityType;
  final String entitySyncId;
  final String operation;
  final String? payloadJson;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime nextAttemptAt;
}

class SyncQueueSummary {
  const SyncQueueSummary({
    required this.pendingCount,
    required this.failedCount,
    this.nextRetryAt,
  });

  final int pendingCount;
  final int failedCount;
  final DateTime? nextRetryAt;
}

class SyncedTaskChange {
  const SyncedTaskChange({
    required this.operation,
    required this.task,
    this.changedTaskFields = const [],
    this.changedSubtaskSyncIds = const [],
  });

  final String operation;
  final TodoTask task;
  final List<String> changedTaskFields;
  final List<String> changedSubtaskSyncIds;
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
