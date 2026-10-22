import 'dart:convert';

const changedTaskFieldsPayloadKey = '_changed_task_fields';

const taskSyncFieldNames = {
  'owner_user_id',
  'visibility',
  'workspace_id',
  'created_by_user_id',
  'title',
  'note',
  'category',
  'is_completed',
  'shared_completion_mode',
  'completed_by_user_ids',
  'due_at',
  'reminder_option',
  'reminder_value',
  'deleted_at',
};

Map<String, Object?>? decodeSyncPayload(String? payloadJson) {
  if (payloadJson == null) return null;
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } on FormatException {
    // A damaged queue row must not stop valid uploads or remote downloads.
    return null;
  }
  return null;
}

List<String> changedTaskFieldsFromPayload(Map<String, Object?> payload) {
  final value = payload[changedTaskFieldsPayloadKey];
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}
