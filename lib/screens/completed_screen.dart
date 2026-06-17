import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../date_formatting.dart';
import '../local_todo_repository.dart';
import '../models.dart';
import '../settings_controller.dart';
import 'shared/paper_background.dart';

class CompletedScreen extends StatelessWidget {
  const CompletedScreen({
    super.key,
    required this.repository,
    required this.settings,
  });

  final LocalTodoRepository repository;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([repository, settings]),
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final tasks = repository.tasks
            .where((task) => task.isCompleted)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        return Scaffold(
          appBar: AppBar(title: Text(strings.completed)),
          body: PaperBackground(
            child: tasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        strings.noCompletedTasks,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _CompletedTaskRow(
                        task: task,
                        onUndo: () => repository.upsertTask(
                          task.copyWith(
                            isCompleted: false,
                            completedByUserIds: const <String>[],
                            updatedAt: DateTime.now(),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _CompletedTaskRow extends StatelessWidget {
  const _CompletedTaskRow({
    required this.task,
    required this.onUndo,
  });

  final TodoTask task;
  final Future<void> Function() onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.completedOn(
                    formatEditorDueDate(
                      task.updatedAt,
                      language: strings.language,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: strings.markNotDone,
            onPressed: () => onUndo(),
            icon: const Icon(Icons.undo_outlined),
          ),
        ],
      ),
    );
  }
}
