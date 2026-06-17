import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../date_formatting.dart';
import '../local_todo_repository.dart';
import '../models.dart';
import '../settings_controller.dart';
import 'shared/paper_background.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({
    super.key,
    required this.repository,
    required this.settings,
  });

  final LocalTodoRepository repository;
  final SettingsController settings;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.repository, widget.settings]),
      builder: (context, _) {
        final tasks = widget.repository.trashTasks;
        final isEmpty = tasks.isEmpty;
        final strings = AppStrings.of(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(strings.trashcan),
            actions: [
              IconButton(
                tooltip: strings.emptyTrash,
                onPressed: tasks.isEmpty
                    ? null
                    : () => unawaited(_confirmEmptyTrash()),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          body: PaperBackground(
            child: Column(
              children: [
                Expanded(
                  child: isEmpty
                      ? _TrashEmptyState(label: strings.tasksLabel)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: tasks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            return _TrashItem(
                              title: task.title,
                              subtitle: _trashSubtitle(
                                task.deletedAt,
                                task.purgeAfter,
                              ),
                              canPermanentlyDelete: widget.repository
                                  .canPermanentlyDeleteTask(task),
                              onRestore: () => _restoreTask(task),
                              onDeletePermanently: () =>
                                  _confirmDeletePermanently(task),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _trashSubtitle(DateTime? deletedAt, DateTime? purgeAfter) {
    final strings = AppStrings.of(context);
    return strings.trashSubtitle(
      deletedAt: deletedAt,
      purgeAfter: purgeAfter,
      formatDate: (date) => formatEditorDueDate(
        date,
        language: strings.language,
      ),
    );
  }

  Future<void> _confirmEmptyTrash() async {
    final strings = AppStrings.of(context);
    final confirmed = await _confirm(
      title: strings.emptyTrashTitle,
      message: strings.emptyTrashMessage,
    );
    if (!confirmed) return;
    await widget.repository.emptyTrash();
  }

  Future<void> _restoreTask(TodoTask task) async {
    await widget.repository.restoreTaskFromTrash(task);
  }

  Future<void> _confirmDeletePermanently(TodoTask task) async {
    final strings = AppStrings.of(context);
    final confirmed = await _confirm(
      title: strings.deletePermanentlyTitle,
      message: strings.permanentDeleteMessage(task.title),
      confirmLabel: strings.deletePermanently,
    );
    if (!confirmed) return;

    final deleted = await widget.repository.permanentlyDeleteTask(task);
    if (!deleted && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(strings.syncBeforePermanentDelete)),
        );
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String? confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final strings = AppStrings.of(context);

        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel ?? strings.delete),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }
}

class _TrashItem extends StatelessWidget {
  const _TrashItem({
    required this.title,
    required this.subtitle,
    required this.canPermanentlyDelete,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  final String title;
  final String subtitle;
  final bool canPermanentlyDelete;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDeletePermanently;

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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
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
            tooltip: strings.restore,
            onPressed: () => onRestore(),
            icon: const Icon(Icons.restore_from_trash_outlined),
          ),
          IconButton(
            tooltip: canPermanentlyDelete
                ? strings.deletePermanently
                : strings.waitingForSync,
            onPressed:
                canPermanentlyDelete ? () => onDeletePermanently() : null,
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        ],
      ),
    );
  }
}

class _TrashEmptyState extends StatelessWidget {
  const _TrashEmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          strings.noDeletedItems(label),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
