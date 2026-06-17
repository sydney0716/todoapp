import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../date_formatting.dart';
import '../local_todo_repository.dart';
import '../models.dart';
import '../settings_controller.dart';
import 'shared/delete_background.dart';
import 'shared/paper_background.dart';

const _customMinuteValues = [1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];
const _customHourValues = [
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
];

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.repository,
    required this.settings,
    this.task,
    this.initialDueDate,
  });

  final LocalTodoRepository repository;
  final SettingsController settings;
  final TodoTask? task;
  final DateTime? initialDueDate;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late String _category;
  late SyncVisibility _visibility;
  late SharedCompletionMode _sharedCompletionMode;
  late DateTime? _dueDate;
  late TimeOfDay? _dueTime;
  late TaskReminderOption _reminderOption;
  late int? _reminderValue;
  late List<_EditableSubTask> _subTasks;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _noteController = TextEditingController(text: task?.note ?? '');
    _category = task?.category ?? '';
    _visibility = task?.visibility ?? SyncVisibility.privateItem;
    _sharedCompletionMode =
        task?.sharedCompletionMode ?? SharedCompletionMode.single;
    _dueDate = _initialDueDate(task?.dueDateTime) ??
        (task == null ? _initialDueDate(widget.initialDueDate) : null);
    _dueTime = _initialDueTime(task?.dueDateTime);
    _reminderOption = task?.reminderOption ?? TaskReminderOption.none;
    _reminderValue = task?.reminderValue;
    _subTasks = [
      for (final subTask in task?.subTasks ?? const <SubTask>[])
        _EditableSubTask.fromSubTask(subTask),
    ];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final isNewTask = widget.task == null;

    return Scaffold(
      bottomNavigationBar: PaperBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: _isSaving ? null : () => unawaited(_save()),
                  child: Text(_isSaving
                      ? strings.saving
                      : isNewTask
                          ? strings.saveTask
                          : strings.saveChanges),
                ),
              ],
            ),
          ),
        ),
      ),
      body: PaperBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: _isSaving
                        ? null
                        : () => unawaited(Navigator.of(context).maybePop()),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  if (!isNewTask) ...[
                    const Spacer(),
                    IconButton(
                      tooltip: strings.deleteTask,
                      onPressed:
                          _isSaving ? null : () => unawaited(_deleteTask()),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ],
              ),
              TextField(
                controller: _titleController,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.next,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: strings.title,
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 20),
              _DividerRow(
                leading: Icons.notes,
                child: TextField(
                  controller: _noteController,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: strings.addDetails,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              Dismissible(
                key: const ValueKey('due-date-row'),
                direction: _dueDate == null
                    ? DismissDirection.none
                    : DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  _clearDueDate();
                  return false;
                },
                background: const SwipeDeleteBackground(),
                child: _DividerRow(
                  leading: Icons.calendar_today,
                  child: _DueDateTimeControls(
                    dateLabel: _dueDate == null
                        ? strings.dueDate
                        : formatListDueDate(
                            _dueDate!,
                            language: strings.language,
                          ),
                    timeLabel: _dueDate == null
                        ? strings.time
                        : _dueTime == null
                            ? strings.addTime
                            : _formatTimeOfDay(_dueTime!),
                    onDateTap: () => unawaited(_openDatePicker()),
                    onTimeTap: _dueDate == null
                        ? null
                        : () => unawaited(_openTimePicker()),
                  ),
                ),
              ),
              _DividerRow(
                leading: Icons.notifications_none,
                child: _ReminderControl(
                  label: _reminderLabel(),
                  onTap: () => unawaited(_openReminderPicker()),
                ),
              ),
              _DividerRow(
                leading: _visibility == SyncVisibility.shared
                    ? Icons.group_outlined
                    : Icons.person_outline,
                child: _VisibilityToggle(
                  visibility: _visibility,
                  sharedCompletionMode: _sharedCompletionMode,
                  onPressed: _toggleVisibility,
                  onSharedCompletionChanged: (value) {
                    setState(() {
                      _sharedCompletionMode = value
                          ? SharedCompletionMode.both
                          : SharedCompletionMode.single;
                    });
                  },
                ),
              ),
              _DividerRow(
                leading: Icons.label_outline,
                child: _CategorySelector(
                  category: _category,
                  categories: _availableCategories(),
                  onSelected: (category) {
                    setState(() => _category = category);
                  },
                ),
              ),
              const SizedBox(height: 2),
              for (var index = 0; index < _subTasks.length; index++)
                _buildSubTaskRow(index),
              _AddSubTaskRow(onPressed: _addSubTask),
            ],
          ),
        ),
      ),
    );
  }

  static DateTime? _initialDueDate(DateTime? dueDateTime) {
    if (dueDateTime == null) return null;
    return DateTime(dueDateTime.year, dueDateTime.month, dueDateTime.day);
  }

  static TimeOfDay? _initialDueTime(DateTime? dueDateTime) {
    if (dueDateTime == null) return null;
    if (dueDateTime.hour == 0 &&
        dueDateTime.minute == 0 &&
        dueDateTime.second == 0 &&
        dueDateTime.millisecond == 0 &&
        dueDateTime.microsecond == 0) {
      return null;
    }
    return TimeOfDay.fromDateTime(dueDateTime);
  }

  DateTime? _selectedDueDateTime() {
    final dueDate = _dueDate;
    if (dueDate == null) return null;

    final dueTime = _dueTime;
    if (dueTime == null) {
      return DateTime(dueDate.year, dueDate.month, dueDate.day);
    }

    return DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      dueTime.hour,
      dueTime.minute,
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final strings = AppStrings.of(context);
    return formatTimeOfDay(
      DateTime(2000, 1, 1, time.hour, time.minute),
      widget.settings.timeFormat,
      language: strings.language,
    );
  }

  List<String> _availableCategories() {
    final categories = <String>{
      for (final task in widget.repository.tasks) task.category.trim(),
      for (final task in widget.repository.trashTasks) task.category.trim(),
      _category.trim(),
    }..removeWhere((category) => category.isEmpty);

    final sortedCategories = categories.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sortedCategories;
  }

  Widget _buildSubTaskRow(int index) {
    final subTask = _subTasks[index];

    return Dismissible(
      key: ValueKey('subtask-${subTask.draftId}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() {
          _subTasks.removeWhere((candidate) {
            return candidate.draftId == subTask.draftId;
          });
        });
      },
      background: const SwipeDeleteBackground(),
      child: _SubTaskField(
        subTask: subTask,
        showBranchIcon: index == 0,
        onDueDateTap: () => unawaited(_openSubTaskDueDatePicker(subTask)),
        onClearDueDate: () => _clearSubTaskDueDate(subTask),
        onChanged: () => setState(() {}),
      ),
    );
  }

  Future<void> _openDatePicker() async {
    final initial = _dueDate ?? DateTime.now();
    final date = await _pickDate(initial);
    if (date == null || !mounted) return;

    setState(() {
      _dueDate = DateTime(date.year, date.month, date.day);
    });
  }

  Future<void> _openTimePicker() async {
    final dueDate = _dueDate;
    if (dueDate == null) return;

    final initial = _selectedDueDateTime() ?? dueDate;
    final time = await _pickTime(initial);
    if (time == null || !mounted) return;

    setState(() => _dueTime = time);
  }

  Future<void> _openSubTaskDueDatePicker(_EditableSubTask subTask) async {
    final initial = subTask.dueDateTime ?? _dueDate ?? DateTime.now();
    final date = await _pickDate(initial);
    if (date == null || !mounted) return;

    setState(() {
      subTask.dueDateTime = DateTime(date.year, date.month, date.day);
    });
  }

  Future<DateTime?> _pickDate(DateTime initial) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  Future<TimeOfDay?> _pickTime(DateTime initial) {
    final strings = AppStrings.of(context);
    return _readTimeDial(
      context: context,
      title: strings.time,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
  }

  void _addSubTask() {
    setState(() => _subTasks.add(_EditableSubTask()));
  }

  void _clearDueDate() {
    setState(() {
      _dueDate = null;
      _dueTime = null;
      _reminderOption = TaskReminderOption.none;
      _reminderValue = null;
    });
  }

  void _clearSubTaskDueDate(_EditableSubTask subTask) {
    setState(() => subTask.dueDateTime = null);
  }

  void _toggleVisibility() {
    setState(() {
      _visibility = _visibility == SyncVisibility.privateItem
          ? SyncVisibility.shared
          : SyncVisibility.privateItem;
    });
  }

  Future<void> _openReminderPicker() async {
    final strings = AppStrings.of(context);

    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.chooseDueDateBeforeAlarm)),
      );
      return;
    }

    final selected = await showModalBottomSheet<_ReminderSelection>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                _ReminderOptionTile(
                  title: strings.reminderOptionLabel(TaskReminderOption.none),
                  icon: Icons.notifications_off_outlined,
                  selected: _reminderOption == TaskReminderOption.none,
                  onTap: () => Navigator.of(context).pop(
                    const _ReminderSelection(TaskReminderOption.none),
                  ),
                ),
                _ReminderOptionTile(
                  title:
                      strings.reminderOptionLabel(TaskReminderOption.atStart),
                  selected: _reminderOption == TaskReminderOption.atStart,
                  onTap: () => Navigator.of(context).pop(
                    const _ReminderSelection(TaskReminderOption.atStart),
                  ),
                ),
                _ReminderOptionTile(
                  title: strings.reminderMinutes(5),
                  selected: _reminderOption == TaskReminderOption.beforeMinutes,
                  onTap: () => Navigator.of(context).pop(
                    const _ReminderSelection(
                      TaskReminderOption.beforeMinutes,
                      value: null,
                    ),
                  ),
                  onCustom: () => Navigator.of(context).pop(
                    const _ReminderSelection(
                      TaskReminderOption.beforeMinutes,
                      isCustom: true,
                    ),
                  ),
                ),
                _ReminderOptionTile(
                  title: strings.reminderHours(1),
                  selected: _reminderOption == TaskReminderOption.beforeHours,
                  onTap: () => Navigator.of(context).pop(
                    const _ReminderSelection(
                      TaskReminderOption.beforeHours,
                      value: null,
                    ),
                  ),
                  onCustom: () => Navigator.of(context).pop(
                    const _ReminderSelection(
                      TaskReminderOption.beforeHours,
                      isCustom: true,
                    ),
                  ),
                ),
                _ReminderOptionTile(
                  title: strings.reminderOptionLabel(
                    TaskReminderOption.startOfDay,
                  ),
                  selected: _reminderOption == TaskReminderOption.startOfDay,
                  onTap: () => Navigator.of(context).pop(
                    const _ReminderSelection(TaskReminderOption.startOfDay),
                  ),
                  onCustom: () => Navigator.of(context).pop(
                    const _ReminderSelection(
                      TaskReminderOption.startOfDay,
                      isCustom: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;

    final resolvedSelection = selected.isCustom
        ? await _openCustomReminderPicker(selected)
        : selected;
    if (resolvedSelection == null || !mounted) return;

    setState(() {
      _reminderOption = resolvedSelection.option;
      _reminderValue = resolvedSelection.value;
    });
  }

  Future<_ReminderSelection?> _openCustomReminderPicker(
    _ReminderSelection selection,
  ) async {
    final strings = AppStrings.of(context);

    switch (selection.option) {
      case TaskReminderOption.beforeMinutes:
        final value = await _readNumberDial(
          context,
          title: strings.customMinutes,
          values: _customMinuteValues,
          initialValue: _customMinuteInitialValue(),
          valueLabel: strings.minuteValue,
        );
        if (value == null) return null;
        return _ReminderSelection(selection.option, value: value);
      case TaskReminderOption.beforeHours:
        final value = await _readNumberDial(
          context,
          title: strings.customHours,
          values: _customHourValues,
          initialValue: _customHourInitialValue(),
          valueLabel: strings.hourValue,
        );
        if (value == null) return null;
        return _ReminderSelection(selection.option, value: value);
      case TaskReminderOption.startOfDay:
        final time = await _readTimeDial(
          context: context,
          title: strings.startOfDayAlarm,
          initialTime: _startOfDayReminderTime(),
        );
        if (time == null) return null;
        return _ReminderSelection(
          selection.option,
          value: time.hour * 60 + time.minute,
        );
      case TaskReminderOption.none:
      case TaskReminderOption.atStart:
        return selection;
    }
  }

  Future<int?> _readNumberDial(
    BuildContext context, {
    required String title,
    required List<int> values,
    required int initialValue,
    required String Function(int value) valueLabel,
  }) async {
    return showDialog<int>(
      context: context,
      builder: (_) => _NumberDialDialog(
        title: title,
        values: values,
        initialValue: initialValue,
        valueLabel: valueLabel,
      ),
    );
  }

  Future<TimeOfDay?> _readTimeDial({
    required BuildContext context,
    required String title,
    required TimeOfDay initialTime,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _TimeDialDialog(
        title: title,
        initialTime: initialTime,
      ),
    );
  }

  int _customMinuteInitialValue() {
    final value = _reminderOption == TaskReminderOption.beforeMinutes
        ? _reminderValue
        : null;
    return _nearestDialValue(_customMinuteValues, value ?? 5);
  }

  int _customHourInitialValue() {
    final value = _reminderOption == TaskReminderOption.beforeHours
        ? _reminderValue
        : null;
    return _nearestDialValue(_customHourValues, value ?? 1);
  }

  int _nearestDialValue(List<int> values, int target) {
    return values.reduce((best, candidate) {
      final bestDistance = (best - target).abs();
      final candidateDistance = (candidate - target).abs();
      return candidateDistance < bestDistance ? candidate : best;
    });
  }

  TimeOfDay _startOfDayReminderTime() {
    final value = _reminderOption == TaskReminderOption.startOfDay
        ? _reminderValue
        : null;
    if (value == null) return const TimeOfDay(hour: 9, minute: 0);
    final clampedValue = value.clamp(0, 1439).toInt();
    return TimeOfDay(hour: clampedValue ~/ 60, minute: clampedValue % 60);
  }

  String _reminderLabel() {
    final strings = AppStrings.of(context);

    switch (_reminderOption) {
      case TaskReminderOption.none:
      case TaskReminderOption.atStart:
        return strings.reminderOptionLabel(_reminderOption);
      case TaskReminderOption.beforeMinutes:
        final minutes = _reminderValue ?? 5;
        return strings.reminderMinutes(minutes);
      case TaskReminderOption.beforeHours:
        final hours = _reminderValue ?? 1;
        return strings.reminderHours(hours);
      case TaskReminderOption.startOfDay:
        final value = _reminderValue;
        if (value == null) return strings.reminderOptionLabel(_reminderOption);
        final clampedValue = value.clamp(0, 1439).toInt();
        final time = formatTimeOfDay(
          DateTime(2000, 1, 1, clampedValue ~/ 60, clampedValue % 60),
          widget.settings.timeFormat,
          language: strings.language,
        );
        return strings.startOfDayWithTime(time);
    }
  }

  Future<void> _deleteTask() async {
    final task = widget.task;
    if (task == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await widget.repository.moveTaskToTrash(task);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.titleRequired)),
      );
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();
    final existingTask = widget.task;
    final ownerUserId = existingTask?.ownerUserId.isNotEmpty == true
        ? existingTask!.ownerUserId
        : widget.settings.currentUserId;
    final task = TodoTask(
      id: existingTask?.id ?? 0,
      syncId: existingTask?.syncId ?? '',
      ownerUserId: ownerUserId,
      visibility: _visibility,
      workspaceId: _visibility == SyncVisibility.shared
          ? defaultSharedWorkspaceId
          : null,
      createdByUserId: existingTask?.createdByUserId ?? '',
      updatedByUserId: existingTask?.updatedByUserId ?? '',
      title: title,
      note: _noteController.text.trim(),
      category: _category.trim(),
      isCompleted: existingTask?.isCompleted ?? false,
      sharedCompletionMode: _visibility == SyncVisibility.shared
          ? _sharedCompletionMode
          : SharedCompletionMode.single,
      completedByUserIds: _visibility == SyncVisibility.shared
          ? existingTask?.completedByUserIds ?? const <String>[]
          : const <String>[],
      dueDateTime: _selectedDueDateTime(),
      reminderOption:
          _dueDate == null ? TaskReminderOption.none : _reminderOption,
      reminderValue: _dueDate == null ? null : _reminderValue,
      createdAt: existingTask?.createdAt ?? now,
      updatedAt: now,
      version: existingTask?.version ?? 1,
      syncStatus: SyncStatus.pending,
      deletedAt: existingTask?.deletedAt,
      purgeAfter: existingTask?.purgeAfter,
      lastSyncedAt: existingTask?.lastSyncedAt,
      deviceId: existingTask?.deviceId ?? '',
      subTasks: [
        for (final subTask in _subTasks)
          if (subTask.title.trim().isNotEmpty)
            SubTask(
              id: subTask.persistedId,
              syncId: subTask.syncId,
              taskSyncId: subTask.taskSyncId,
              ownerUserId: subTask.ownerUserId,
              visibility: _visibility,
              workspaceId: _visibility == SyncVisibility.shared
                  ? defaultSharedWorkspaceId
                  : null,
              title: subTask.title.trim(),
              isCompleted: subTask.isCompleted,
              dueDateTime: subTask.dueDateTime,
              createdAt: subTask.createdAt,
              updatedAt: now,
              version: subTask.version,
              syncStatus: SyncStatus.pending,
              deletedAt: subTask.deletedAt,
              purgeAfter: subTask.purgeAfter,
              lastSyncedAt: subTask.lastSyncedAt,
              deviceId: subTask.deviceId,
            ),
      ],
    );

    try {
      await widget.repository.upsertTask(task);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.category,
    required this.categories,
    required this.onSelected,
  });

  final String category;
  final List<String> categories;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final color = theme.colorScheme.primary;
    final label = category.isEmpty ? strings.noCategory : category;

    return PopupMenuButton<String>(
      tooltip: strings.selectCategory,
      initialValue: category,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: '',
          child: Text(strings.noCategory),
        ),
        for (final category in categories)
          PopupMenuItem(
            value: category,
            child: Text(category),
          ),
      ],
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _DividerRow extends StatelessWidget {
  const _DividerRow({
    required this.leading,
    required this.child,
  });

  final IconData leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              child: Icon(
                leading,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _DueDateTimeControls extends StatelessWidget {
  const _DueDateTimeControls({
    required this.dateLabel,
    required this.timeLabel,
    required this.onDateTap,
    this.onTimeTap,
  });

  final String dateLabel;
  final String timeLabel;
  final VoidCallback onDateTap;
  final VoidCallback? onTimeTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DueDateColumnButton(
            label: dateLabel,
            onPressed: onDateTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DueDateColumnButton(
            label: timeLabel,
            icon: Icons.access_time,
            onPressed: onTimeTap,
          ),
        ),
      ],
    );
  }
}

class _DueDateColumnButton extends StatelessWidget {
  const _DueDateColumnButton({
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final color = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return TextButton(
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderControl extends StatelessWidget {
  const _ReminderControl({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}

class _ReminderSelection {
  const _ReminderSelection(
    this.option, {
    this.value,
    this.isCustom = false,
  });

  final TaskReminderOption option;
  final int? value;
  final bool isCustom;
}

class _NumberDialDialog extends StatefulWidget {
  const _NumberDialDialog({
    required this.title,
    required this.values,
    required this.initialValue,
    required this.valueLabel,
  });

  final String title;
  final List<int> values;
  final int initialValue;
  final String Function(int value) valueLabel;

  @override
  State<_NumberDialDialog> createState() => _NumberDialDialogState();
}

class _NumberDialDialogState extends State<_NumberDialDialog> {
  static const _itemExtent = 44.0;

  late final FixedExtentScrollController _controller;
  late int _selectedValue;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.values.indexOf(widget.initialValue);
    final resolvedIndex = initialIndex < 0 ? 0 : initialIndex;
    _selectedValue = widget.values[resolvedIndex];
    _controller = FixedExtentScrollController(
      initialItem: resolvedIndex,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 180,
        height: 150,
        child: ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: _itemExtent,
          diameterRatio: 1.2,
          physics: const FixedExtentScrollPhysics(),
          overAndUnderCenterOpacity: 0.35,
          onSelectedItemChanged: (index) {
            setState(() => _selectedValue = widget.values[index]);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: widget.values.length,
            builder: (context, index) {
              return Center(
                child: Text(
                  widget.valueLabel(widget.values[index]),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(_selectedValue);
          },
          child: Text(strings.save),
        ),
      ],
    );
  }
}

class _TimeDialDialog extends StatefulWidget {
  const _TimeDialDialog({
    required this.title,
    required this.initialTime,
  });

  final String title;
  final TimeOfDay initialTime;

  @override
  State<_TimeDialDialog> createState() => _TimeDialDialogState();
}

class _TimeDialDialogState extends State<_TimeDialDialog> {
  static const _itemExtent = 44.0;
  static const _minuteValues = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    _minute = _nearestMinute(widget.initialTime.minute);
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(
      initialItem: _minuteValues.indexOf(_minute),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  int _nearestMinute(int minute) {
    return _minuteValues.reduce((best, candidate) {
      final bestDistance = (best - minute).abs();
      final candidateDistance = (candidate - minute).abs();
      return candidateDistance < bestDistance ? candidate : best;
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final strings = AppStrings.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 240,
        height: 170,
        child: Row(
          children: [
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: _hourController,
                itemExtent: _itemExtent,
                diameterRatio: 1.2,
                physics: const FixedExtentScrollPhysics(),
                overAndUnderCenterOpacity: 0.35,
                onSelectedItemChanged: (index) {
                  setState(() => _hour = index);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: 24,
                  builder: (context, index) {
                    return Center(
                      child: Text(
                        index.toString().padLeft(2, '0'),
                      ),
                    );
                  },
                ),
              ),
            ),
            Text(':', style: titleStyle),
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: _minuteController,
                itemExtent: _itemExtent,
                diameterRatio: 1.2,
                physics: const FixedExtentScrollPhysics(),
                overAndUnderCenterOpacity: 0.35,
                onSelectedItemChanged: (index) {
                  setState(() => _minute = _minuteValues[index]);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: _minuteValues.length,
                  builder: (context, index) {
                    return Center(
                      child: Text(
                        _minuteValues[index].toString().padLeft(2, '0'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
          },
          child: Text(strings.save),
        ),
      ],
    );
  }
}

class _ReminderOptionTile extends StatelessWidget {
  const _ReminderOptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon = Icons.notifications_none,
    this.onCustom,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final VoidCallback? onCustom;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCustom != null)
            TextButton(
              onPressed: onCustom,
              child: Text(strings.custom),
            ),
          if (selected) const Icon(Icons.check),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.visibility,
    required this.sharedCompletionMode,
    required this.onPressed,
    required this.onSharedCompletionChanged,
  });

  final SyncVisibility visibility;
  final SharedCompletionMode sharedCompletionMode;
  final VoidCallback onPressed;
  final ValueChanged<bool> onSharedCompletionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final isShared = visibility == SyncVisibility.shared;
    final requiresBoth = sharedCompletionMode == SharedCompletionMode.both;

    return Row(
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onPressed,
          child: Text(isShared ? strings.sharedLabel : strings.privateLabel),
        ),
        if (isShared) ...[
          const Spacer(),
          SizedBox(
            height: 26,
            child: VerticalDivider(
              width: 16,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          Text(
            strings.bothLabel,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            height: 36,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: requiresBoth,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onSharedCompletionChanged,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SubTaskField extends StatelessWidget {
  const _SubTaskField({
    required this.subTask,
    required this.showBranchIcon,
    required this.onDueDateTap,
    required this.onClearDueDate,
    required this.onChanged,
  });

  final _EditableSubTask subTask;
  final bool showBranchIcon;
  final VoidCallback onDueDateTap;
  final VoidCallback onClearDueDate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final dueDateTime = subTask.dueDateTime;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            child: showBranchIcon
                ? Icon(
                    Icons.subdirectory_arrow_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            tooltip:
                subTask.isCompleted ? strings.markNotDone : strings.markDone,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            onPressed: () {
              subTask.isCompleted = !subTask.isCompleted;
              onChanged();
            },
            icon: Icon(
              subTask.isCompleted
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              color: theme.colorScheme.primary,
            ),
          ),
          Expanded(
            child: TextFormField(
              initialValue: subTask.title,
              onChanged: (value) => subTask.title = value,
              style: theme.textTheme.bodyLarge?.copyWith(
                decoration: subTask.isCompleted
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: subTask.isCompleted
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: strings.subtask,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (dueDateTime != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                formatListDueDate(dueDateTime, language: strings.language),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: strings.subtaskOptions,
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'set_due_date') {
                onDueDateTap();
              } else if (value == 'clear_due_date') {
                onClearDueDate();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'set_due_date',
                child: Text(
                  dueDateTime == null
                      ? strings.setDueDate
                      : strings.changeDueDate,
                ),
              ),
              if (dueDateTime != null)
                PopupMenuItem(
                  value: 'clear_due_date',
                  child: Text(strings.clearDueDate),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddSubTaskRow extends StatelessWidget {
  const _AddSubTaskRow({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 88, top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onPressed,
          child: Text(
            strings.addSubtask,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditableSubTask {
  _EditableSubTask({
    this.persistedId = 0,
    this.syncId = '',
    this.taskSyncId = '',
    this.ownerUserId = '',
    this.visibility = SyncVisibility.privateItem,
    this.workspaceId,
    this.title = '',
    this.isCompleted = false,
    this.dueDateTime,
    DateTime? createdAt,
    this.version = 1,
    this.deletedAt,
    this.purgeAfter,
    this.lastSyncedAt,
    this.deviceId = '',
  })  : createdAt = createdAt ?? DateTime.now(),
        draftId = persistedId == 0
            ? 'draft-${DateTime.now().microsecondsSinceEpoch}'
            : 'persisted-$persistedId';

  factory _EditableSubTask.fromSubTask(SubTask subTask) {
    return _EditableSubTask(
      persistedId: subTask.id,
      syncId: subTask.syncId,
      taskSyncId: subTask.taskSyncId,
      ownerUserId: subTask.ownerUserId,
      visibility: subTask.visibility,
      workspaceId: subTask.workspaceId,
      title: subTask.title,
      isCompleted: subTask.isCompleted,
      dueDateTime: subTask.dueDateTime,
      createdAt: subTask.createdAt,
      version: subTask.version,
      deletedAt: subTask.deletedAt,
      purgeAfter: subTask.purgeAfter,
      lastSyncedAt: subTask.lastSyncedAt,
      deviceId: subTask.deviceId,
    );
  }

  final String draftId;
  final int persistedId;
  final String syncId;
  final String taskSyncId;
  final String ownerUserId;
  final SyncVisibility visibility;
  final String? workspaceId;
  String title;
  bool isCompleted;
  DateTime? dueDateTime;
  final DateTime createdAt;
  final int version;
  final DateTime? deletedAt;
  final DateTime? purgeAfter;
  final DateTime? lastSyncedAt;
  final String deviceId;
}
