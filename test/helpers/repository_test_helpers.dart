import 'dart:convert';
import 'package:personaltodo/api/todo_api_models.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';

Future<void> acknowledgeLocalQueueItem(
    LocalTodoRepository repository, int id) async {
  final queue = await repository.getPendingSyncQueue();
  final item = queue.firstWhere((item) => item.id == id);
  final payload = RemoteTaskRecord.fromJson(
          Map<String, Object?>.from(jsonDecode(item.payloadJson!) as Map))
      .toTodoTask();
  final tasks = [...repository.tasks, ...repository.trashTasks];
  final local =
      tasks.where((task) => task.syncId == item.entitySyncId).firstOrNull ??
          payload;
  final children = {
    for (final child in payload.subTasks) child.syncId: child,
    for (final child in local.subTasks) child.syncId: child
  };
  await repository.acknowledgeTaskChanges([
    SyncedTaskAcknowledgement(
      queueItemId: id,
      operation: item.operation,
      task: local.copyWith(subTasks: children.values.toList()),
    )
  ]);
}
