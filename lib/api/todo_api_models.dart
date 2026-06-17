import '../models.dart';

class TodoApiException implements Exception {
  const TodoApiException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'TodoApiException($statusCode): $message';
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.userId,
    required this.deviceId,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final String userId;
  final String deviceId;

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      accessToken: _readString(json, 'access_token'),
      refreshToken: _readString(json, 'refresh_token'),
      tokenType: _readString(json, 'token_type'),
      userId: _readString(json, 'user_id'),
      deviceId: _readString(json, 'device_id'),
    );
  }
}

class ConnectionCheckResult {
  const ConnectionCheckResult({
    required this.session,
    required this.bootstrap,
  });

  final AuthSession session;
  final SyncBootstrap bootstrap;
}

class SyncBootstrap {
  const SyncBootstrap({
    required this.cursor,
    required this.tasks,
  });

  final String cursor;
  final List<RemoteTaskRecord> tasks;

  factory SyncBootstrap.fromJson(Map<String, Object?> json) {
    final tasks = _readList(json, 'tasks')
        .map((task) => RemoteTaskRecord.fromJson(_asObject(task, 'task')))
        .toList(growable: false);
    return SyncBootstrap(
      cursor: _readString(json, 'cursor'),
      tasks: tasks,
    );
  }
}

class SyncTaskChange {
  const SyncTaskChange({
    required this.operation,
    required this.record,
    this.changedTaskFields = const [],
  });

  final String operation;
  final Map<String, Object?> record;
  final List<String> changedTaskFields;

  Map<String, Object?> toJson() {
    return {
      'operation': operation,
      'record': record,
      'changed_task_fields': changedTaskFields,
    };
  }
}

class SyncPushResult {
  const SyncPushResult({
    required this.cursor,
    required this.accepted,
    required this.rejected,
  });

  final String cursor;
  final List<RemoteTaskRecord> accepted;
  final List<String> rejected;

  factory SyncPushResult.fromJson(Map<String, Object?> json) {
    final accepted = _readList(json, 'accepted')
        .map((task) => RemoteTaskRecord.fromJson(_asObject(task, 'task')))
        .toList(growable: false);
    final rejected = _readList(json, 'rejected').map((value) {
      if (value is String) return value;
      throw const FormatException('Expected rejected item to be a string');
    }).toList(growable: false);
    return SyncPushResult(
      cursor: _readString(json, 'cursor'),
      accepted: accepted,
      rejected: rejected,
    );
  }
}

class SyncPullResult {
  const SyncPullResult({
    required this.cursor,
    required this.changes,
  });

  final String cursor;
  final List<RemoteTaskChange> changes;

  factory SyncPullResult.fromJson(Map<String, Object?> json) {
    final changes = _readList(json, 'changes')
        .map((change) => RemoteTaskChange.fromJson(_asObject(change, 'change')))
        .toList(growable: false);
    return SyncPullResult(
      cursor: _readString(json, 'cursor'),
      changes: changes,
    );
  }
}

class RemoteTaskChange {
  const RemoteTaskChange({
    required this.operation,
    required this.record,
    required this.eventId,
    required this.originDeviceId,
    required this.changedTaskFields,
    required this.changedSubtaskIds,
  });

  final String operation;
  final RemoteTaskRecord record;
  final int? eventId;
  final String? originDeviceId;
  final List<String> changedTaskFields;
  final List<String> changedSubtaskIds;

  factory RemoteTaskChange.fromJson(Map<String, Object?> json) {
    return RemoteTaskChange(
      operation: _readString(json, 'operation'),
      record: RemoteTaskRecord.fromJson(_asObject(json['record'], 'record')),
      eventId: _readNullableInt(json, 'event_id'),
      originDeviceId: _readNullableString(json, 'origin_device_id'),
      changedTaskFields: _readOptionalStringList(json, 'changed_task_fields'),
      changedSubtaskIds: _readOptionalStringList(json, 'changed_subtask_ids'),
    );
  }
}

class RemoteTaskRecord {
  const RemoteTaskRecord({
    required this.id,
    required this.ownerUserId,
    required this.visibility,
    required this.workspaceId,
    required this.title,
    required this.note,
    required this.category,
    required this.isCompleted,
    required this.sharedCompletionMode,
    required this.completedByUserIds,
    required this.dueAt,
    required this.reminderOption,
    required this.reminderValue,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    required this.deletedAt,
    required this.purgeAfter,
    required this.createdByUserId,
    required this.updatedByUserId,
    required this.deviceId,
    required this.subtasks,
  });

  final String id;
  final String ownerUserId;
  final SyncVisibility visibility;
  final String? workspaceId;
  final String title;
  final String note;
  final String category;
  final bool isCompleted;
  final SharedCompletionMode sharedCompletionMode;
  final List<String> completedByUserIds;
  final DateTime? dueAt;
  final String reminderOption;
  final int? reminderValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final DateTime? purgeAfter;
  final String createdByUserId;
  final String updatedByUserId;
  final String deviceId;
  final List<RemoteSubtaskRecord> subtasks;

  factory RemoteTaskRecord.fromJson(Map<String, Object?> json) {
    final subtasks = _readList(json, 'subtasks')
        .map(
          (subtask) => RemoteSubtaskRecord.fromJson(
            _asObject(subtask, 'subtask'),
          ),
        )
        .toList(growable: false);
    return RemoteTaskRecord(
      id: _readString(json, 'id'),
      ownerUserId: _readString(json, 'owner_user_id'),
      visibility: SyncVisibility.fromStoredValue(
        _readString(json, 'visibility'),
      ),
      workspaceId: _readNullableString(json, 'workspace_id'),
      title: _readString(json, 'title'),
      note: _readString(json, 'note'),
      category: _readString(json, 'category'),
      isCompleted: _readBool(json, 'is_completed'),
      sharedCompletionMode: SharedCompletionMode.fromStoredValue(
        _readNullableString(json, 'shared_completion_mode'),
      ),
      completedByUserIds:
          _readOptionalStringList(json, 'completed_by_user_ids'),
      dueAt: _readNullableDate(json, 'due_at'),
      reminderOption: _readString(json, 'reminder_option'),
      reminderValue: _readNullableInt(json, 'reminder_value'),
      createdAt: _readDate(json, 'created_at'),
      updatedAt: _readDate(json, 'updated_at'),
      version: _readInt(json, 'version'),
      deletedAt: _readNullableDate(json, 'deleted_at'),
      purgeAfter: _readNullableDate(json, 'purge_after'),
      createdByUserId: _readString(json, 'created_by_user_id'),
      updatedByUserId: _readString(json, 'updated_by_user_id'),
      deviceId: _readString(json, 'device_id'),
      subtasks: subtasks,
    );
  }

  TodoTask toTodoTask() {
    return TodoTask(
      syncId: id,
      ownerUserId: ownerUserId,
      visibility: visibility,
      workspaceId: workspaceId,
      createdByUserId: createdByUserId,
      updatedByUserId: updatedByUserId,
      title: title,
      note: note,
      category: category,
      isCompleted: isCompleted,
      sharedCompletionMode: sharedCompletionMode,
      completedByUserIds: completedByUserIds,
      dueDateTime: dueAt,
      reminderOption: TaskReminderOption.fromStoredValue(reminderOption),
      reminderValue: reminderValue,
      createdAt: createdAt,
      updatedAt: updatedAt,
      version: version,
      syncStatus: SyncStatus.synced,
      deletedAt: deletedAt,
      purgeAfter: purgeAfter,
      lastSyncedAt: DateTime.now(),
      deviceId: deviceId,
      subTasks: subtasks.map((subtask) => subtask.toSubTask()).toList(),
    );
  }
}

class RemoteSubtaskRecord {
  const RemoteSubtaskRecord({
    required this.id,
    required this.taskId,
    required this.title,
    required this.isCompleted,
    required this.dueAt,
    required this.position,
    required this.updatedAt,
    required this.version,
    required this.deletedAt,
  });

  final String id;
  final String taskId;
  final String title;
  final bool isCompleted;
  final DateTime? dueAt;
  final int position;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;

  factory RemoteSubtaskRecord.fromJson(Map<String, Object?> json) {
    return RemoteSubtaskRecord(
      id: _readString(json, 'id'),
      taskId: _readString(json, 'task_id'),
      title: _readString(json, 'title'),
      isCompleted: _readBool(json, 'is_completed'),
      dueAt: _readNullableDate(json, 'due_at'),
      position: _readInt(json, 'position'),
      updatedAt: _readDate(json, 'updated_at'),
      version: _readInt(json, 'version'),
      deletedAt: _readNullableDate(json, 'deleted_at'),
    );
  }

  SubTask toSubTask() {
    return SubTask(
      syncId: id,
      taskSyncId: taskId,
      title: title,
      isCompleted: isCompleted,
      dueDateTime: dueAt,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      version: version,
      syncStatus: SyncStatus.synced,
      deletedAt: deletedAt,
      lastSyncedAt: DateTime.now(),
    );
  }
}

Map<String, Object?> _asObject(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw FormatException('Expected $label to be an object');
}

List<Object?> _readList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List) return value.cast<Object?>();
  throw FormatException('Expected $key to be a list');
}

List<String> _readOptionalStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is List) {
    return value.map((item) {
      if (item is String) return item;
      throw FormatException('Expected $key item to be a string');
    }).toList(growable: false);
  }
  throw FormatException('Expected $key to be a list');
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected $key to be a string');
}

String? _readNullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected $key to be a string or null');
}

bool _readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected $key to be a bool');
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Expected $key to be an int');
}

int? _readNullableInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('Expected $key to be an int or null');
}

DateTime _readDate(Map<String, Object?> json, String key) {
  return DateTime.parse(_readString(json, key));
}

DateTime? _readNullableDate(Map<String, Object?> json, String key) {
  final value = _readNullableString(json, key);
  if (value == null) return null;
  return DateTime.parse(value);
}
