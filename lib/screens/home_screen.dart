import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../api/todo_api_models.dart';
import '../date_formatting.dart';
import '../local_todo_repository.dart';
import '../models.dart';
import '../native_widget_bridge.dart';
import '../settings_controller.dart';
import '../theme.dart';
import '../todo_sync_service.dart';
import 'completed_screen.dart';
import 'settings_screen.dart';
import 'shared/delete_background.dart';
import 'shared/paper_background.dart';
import 'shared/sync_visibility_widgets.dart';
import 'task_editor_screen.dart';
import 'trash_screen.dart';

const _newCategoryAction = '__new_category__';
const _trashSnackBarDuration = Duration(seconds: 3);
const _undoSnackBarFallbackDuration = Duration(seconds: 8);

Set<DateTime> calendarDueDatesForTasks(Iterable<TodoTask> tasks) {
  return {
    for (final task in tasks) ...[
      if (task.dueDateTime != null) dateOnly(task.dueDateTime!),
      for (final subTask in task.subTasks)
        if (!subTask.isCompleted && subTask.dueDateTime != null)
          dateOnly(subTask.dueDateTime!),
    ],
  };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.settings,
    this.syncRunner,
  });

  final LocalTodoRepository repository;
  final SettingsController settings;
  final TodoSyncRunner? syncRunner;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _autoSyncOpenDelay = Duration(milliseconds: 600);
  static const _autoSyncEditDebounce = Duration(seconds: 2);

  bool _monthExpanded = false;
  bool _includeSharedItems = true;
  bool _taskSelectMode = false;
  bool _autoSyncInFlight = false;
  bool _autoSyncAgainAfterCurrent = false;
  bool _pendingAutoPull = false;
  Timer? _autoSyncTimer;
  final Set<int> _selectedTaskIds = {};

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_handleRepositoryChangedForSync);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleAutoSync(
        delay: _autoSyncOpenDelay,
        pullEvenWithoutPending: true,
      );
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    widget.repository.removeListener(_handleRepositoryChangedForSync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.repository, widget.settings]),
      builder: (context, _) {
        final today = dateOnly(DateTime.now());
        final tasks = _visibleTasks();
        final showTaskSelection = _taskSelectMode;
        final showTaskSelectionActions =
            showTaskSelection && _selectedTaskIds.isNotEmpty;
        final dueDates = calendarDueDatesForTasks(tasks);
        final strings = AppStrings.of(context);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          floatingActionButton: showTaskSelection
              ? null
              : FloatingActionButton.small(
                  onPressed: () => unawaited(_openTaskEditor()),
                  tooltip: strings.newTask,
                  child: const Icon(Icons.add),
                ),
          body: PaperBackground(
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      CalendarHeader(
                        today: today,
                        dueDates: dueDates,
                        monthExpanded: _monthExpanded,
                        scopeVisibility: _includeSharedItems
                            ? SyncVisibility.shared
                            : SyncVisibility.privateItem,
                        onToggleMonthExpanded: () {
                          setState(() => _monthExpanded = !_monthExpanded);
                        },
                        onToggleScopeVisibility:
                            showTaskSelection ? null : _toggleVisibilityScope,
                        onCancelSelection:
                            showTaskSelection ? _exitTaskSelectMode : null,
                        onMenuSelected:
                            showTaskSelection ? null : _handleMenuAction,
                        onDateSelected: (date) =>
                            unawaited(_openTaskEditor(initialDueDate: date)),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _manualSync,
                          child: tasks.isEmpty
                              ? _EmptyState(
                                  title: _emptyTaskTitle(),
                                  message: _emptyTaskMessage(),
                                )
                              : ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    showTaskSelection ? 20 : 96,
                                  ),
                                  itemCount: tasks.length,
                                  separatorBuilder: (context, _) => Divider(
                                    height: 1,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                  itemBuilder: (context, index) {
                                    final task = tasks[index];
                                    return TaskRow(
                                      task: task,
                                      today: today,
                                      selectionMode: showTaskSelection,
                                      isSelected:
                                          _selectedTaskIds.contains(task.id),
                                      onSelectionChanged: (selected) =>
                                          _setTaskSelected(task, selected),
                                      onTap: showTaskSelection
                                          ? () => _toggleTaskSelection(task)
                                          : () => unawaited(
                                                _openTaskEditor(task: task),
                                              ),
                                      onToggleCompleted: () async {
                                        await widget.repository.upsertTask(
                                          task.toggledCompletionForUser(
                                            widget.settings.currentUserId,
                                          ),
                                        );
                                      },
                                      onToggleSubTask: (subTask) =>
                                          _toggleSubTask(task, subTask),
                                      onDelete: () => _deleteTask(task),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                  if (showTaskSelectionActions)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _TaskSelectionActionDock(
                        onMarkDone: () => unawaited(_markSelectedTasksDone()),
                        onMoveCategory: () =>
                            unawaited(_showMoveSelectedCategorySheet()),
                        onDelete: () => unawaited(_deleteSelectedTasks()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<TodoTask> _visibleTasks() {
    final completedFiltered = widget.settings.showCompletedTasks
        ? widget.repository.tasks
        : widget.repository.tasks.where((task) => !task.isCompleted);

    return completedFiltered.where(_isTaskVisibleInScope).toList()
      ..sort(_compareTasks);
  }

  List<TodoTask> _selectedTasks() {
    return widget.repository.tasks
        .where((task) => _selectedTaskIds.contains(task.id))
        .toList();
  }

  void _enterTaskSelectMode() {
    setState(() {
      _taskSelectMode = true;
      _selectedTaskIds.clear();
    });
  }

  void _exitTaskSelectMode() {
    setState(_clearTaskSelection);
  }

  void _clearTaskSelection() {
    _taskSelectMode = false;
    _selectedTaskIds.clear();
  }

  void _toggleTaskSelection(TodoTask task) {
    _setTaskSelected(task, !_selectedTaskIds.contains(task.id));
  }

  void _setTaskSelected(TodoTask task, bool selected) {
    setState(() {
      if (selected) {
        _selectedTaskIds.add(task.id);
      } else {
        _selectedTaskIds.remove(task.id);
      }
    });
  }

  bool _isTaskVisibleInScope(TodoTask task) {
    return _includeSharedItems || task.visibility == SyncVisibility.privateItem;
  }

  void _toggleVisibilityScope() {
    setState(() {
      _includeSharedItems = !_includeSharedItems;
      _clearTaskSelection();
    });
    final strings = AppStrings.of(context);
    _showMessage(
      _includeSharedItems
          ? strings.showPersonalAndShared
          : strings.showPersonalOnly,
    );
  }

  int _compareTasks(TodoTask a, TodoTask b) {
    final completed = _compareBool(a.isCompleted, b.isCompleted);
    if (completed != 0) return completed;

    switch (widget.settings.taskSortOption) {
      case TaskSortOption.dueDate:
        final due = _compareNullableDate(
          a.dueDateTime,
          b.dueDateTime,
          descending:
              widget.settings.taskSortDirection == TaskSortDirection.descending,
        );
        if (due != 0) return due;
        return _compareTitleThenUpdated(a, b);
      case TaskSortOption.title:
        final title = _compareString(
          a.title,
          b.title,
          descending:
              widget.settings.taskSortDirection == TaskSortDirection.descending,
        );
        if (title != 0) return title;
        return _compareNullableDate(a.dueDateTime, b.dueDateTime);
      case TaskSortOption.lastModified:
        final updated = _compareDate(
          a.updatedAt,
          b.updatedAt,
          descending:
              widget.settings.taskSortDirection == TaskSortDirection.descending,
        );
        if (updated != 0) return updated;
        return _compareNullableDate(a.dueDateTime, b.dueDateTime);
    }
  }

  int _compareTitleThenUpdated(TodoTask a, TodoTask b) {
    final title = _compareString(a.title, b.title);
    if (title != 0) return title;
    return _compareDate(a.updatedAt, b.updatedAt, descending: true);
  }

  int _compareBool(bool a, bool b) {
    if (a == b) return 0;
    return a ? 1 : -1;
  }

  int _compareString(String a, String b, {bool descending = false}) {
    final result = a.toLowerCase().compareTo(b.toLowerCase());
    return descending ? -result : result;
  }

  int _compareDate(DateTime a, DateTime b, {bool descending = false}) {
    final result = a.compareTo(b);
    return descending ? -result : result;
  }

  int _compareNullableDate(
    DateTime? a,
    DateTime? b, {
    bool descending = false,
  }) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return _compareDate(a, b, descending: descending);
  }

  String _emptyTaskTitle() {
    final strings = AppStrings.of(context);
    if (!widget.settings.showCompletedTasks &&
        widget.repository.tasks.isNotEmpty) {
      return strings.noVisibleTasks;
    }
    return strings.noTasksYet;
  }

  String _emptyTaskMessage() {
    final strings = AppStrings.of(context);
    if (!widget.settings.showCompletedTasks &&
        widget.repository.tasks.isNotEmpty) {
      return strings.completedTasksHidden;
    }
    return strings.addTaskEmptyMessage;
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'select':
        _enterTaskSelectMode();
        return;
      case 'sort':
        unawaited(_showSortSheet());
        return;
      case 'trash':
        unawaited(Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrashScreen(
              repository: widget.repository,
              settings: widget.settings,
            ),
          ),
        ));
        return;
      case 'completed':
        unawaited(Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompletedScreen(
              repository: widget.repository,
              settings: widget.settings,
            ),
          ),
        ));
        return;
      case 'settings':
        unawaited(Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              settings: widget.settings,
            ),
          ),
        ));
        return;
    }
  }

  Future<void> _markSelectedTasksDone() async {
    final selectedTasks = _selectedTasks();
    if (selectedTasks.isEmpty) return;

    final now = DateTime.now();
    for (final task in selectedTasks) {
      if (task.requiresBothSharedCompletion &&
          task.isCompletedByUser(widget.settings.currentUserId)) {
        continue;
      }
      if (!task.isCompleted) {
        await widget.repository.upsertTask(
          task.toggledCompletionForUser(
            widget.settings.currentUserId,
            updatedAt: now,
          ),
        );
      }
    }

    if (!mounted) return;
    final strings = AppStrings.of(context);
    _showMessage(strings.selectedTasksMarkedDone(selectedTasks.length));
    _exitTaskSelectMode();
  }

  Future<void> _showMoveSelectedCategorySheet() async {
    if (_selectedTaskIds.isEmpty) return;

    final existingCategories = widget.repository.tasks
        .map((task) => task.category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final strings = AppStrings.of(context);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.label_off_outlined),
                title: Text(strings.noCategory),
                onTap: () => Navigator.of(context).pop(''),
              ),
              for (final category in existingCategories)
                ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(category),
                  onTap: () => Navigator.of(context).pop(category),
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(strings.newCategory),
                onTap: () => Navigator.of(context).pop(_newCategoryAction),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;

    final category =
        choice == _newCategoryAction ? await _showNewCategoryDialog() : choice;
    if (!mounted || category == null) return;

    await _moveSelectedTasksToCategory(category);
  }

  Future<String?> _showNewCategoryDialog() async {
    final category = await showDialog<String>(
      context: context,
      builder: (context) => const _NewCategoryDialog(),
    );

    if (category == null || category.isEmpty) return null;
    return category;
  }

  Future<void> _moveSelectedTasksToCategory(String category) async {
    final selectedTasks = _selectedTasks();
    if (selectedTasks.isEmpty) return;

    final now = DateTime.now();
    for (final task in selectedTasks) {
      await widget.repository.upsertTask(
        task.copyWith(category: category, updatedAt: now),
      );
    }

    if (!mounted) return;
    final strings = AppStrings.of(context);
    _showMessage(
      strings.selectedTasksMovedToCategory(selectedTasks.length, category),
    );
    _exitTaskSelectMode();
  }

  Future<void> _deleteSelectedTasks() async {
    final selectedTasks = _selectedTasks();
    if (selectedTasks.isEmpty) return;

    for (final task in selectedTasks) {
      await widget.repository.moveTaskToTrash(task);
    }

    if (!mounted) return;
    final strings = AppStrings.of(context);
    _exitTaskSelectMode();

    _showSnackBar(
      SnackBar(
        duration: _undoSnackBarFallbackDuration,
        content: Text(strings.tasksMovedToTrash(selectedTasks.length)),
        action: SnackBarAction(
          label: strings.undo,
          onPressed: () {
            for (final task in selectedTasks) {
              unawaited(widget.repository.restoreTaskFromTrash(task));
            }
          },
        ),
      ),
      forceDismissAfter: _trashSnackBarDuration,
    );
  }

  void _showMessage(String message) {
    _showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSnackBar(
    SnackBar snackBar, {
    Duration? forceDismissAfter,
  }) {
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final controller = messenger.showSnackBar(snackBar);

    if (forceDismissAfter == null) return;
    unawaited(
      Future<void>.delayed(forceDismissAfter).then((_) {
        if (mounted) controller.close();
      }),
    );
  }

  Future<void> _manualSync() async {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _pendingAutoPull = false;
    final strings = AppStrings.of(context);
    _showMessage(strings.syncingNow);

    if (_autoSyncInFlight) {
      _autoSyncAgainAfterCurrent = true;
      return;
    }

    _autoSyncInFlight = true;
    try {
      final result = await _manualSyncRunner();
      if (!mounted) return;
      _showMessage(
        strings.syncResultMessage(
          pushed: result.pushedCount,
          pulled: result.pulledCount,
          failed: result.failedCount,
          snapshotReconciled: result.snapshotReconciled,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(_syncErrorMessage(error));
    } finally {
      _autoSyncInFlight = false;
      if (_autoSyncAgainAfterCurrent && mounted) {
        _autoSyncAgainAfterCurrent = false;
        _scheduleAutoSync(delay: _autoSyncEditDebounce);
      }
    }
  }

  String _syncErrorMessage(Object error) {
    final strings = AppStrings.of(context);
    if (error is TodoSyncException) return error.message;
    if (error is TodoApiException) {
      if (error.statusCode == 401) return strings.reconnectToServer;
      return '${error.message} (${error.statusCode})';
    }
    if (error is FormatException) return strings.unexpectedServerResponse;
    return strings.unableToSyncNow;
  }

  Future<void> _showSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final strings = AppStrings.of(context);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in TaskSortOption.values)
                    ListTile(
                      title: Text(strings.taskSortOptionLabel(option)),
                      trailing: widget.settings.taskSortOption == option
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        unawaited(
                          widget.settings.setTaskSortOption(option).then(
                              (_) => NativeWidgetBridge.refreshHomeWidget()),
                        );
                        setSheetState(() {});
                      },
                    ),
                  const Divider(height: 1),
                  for (final direction in TaskSortDirection.values)
                    ListTile(
                      title: Text(strings.taskSortDirectionLabel(direction)),
                      trailing: widget.settings.taskSortDirection == direction
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        unawaited(
                          widget.settings.setTaskSortDirection(direction).then(
                              (_) => NativeWidgetBridge.refreshHomeWidget()),
                        );
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openTaskEditor({
    TodoTask? task,
    DateTime? initialDueDate,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskEditorScreen(
          repository: widget.repository,
          settings: widget.settings,
          task: task,
          initialDueDate: initialDueDate,
        ),
      ),
    );
  }

  Future<void> _toggleSubTask(TodoTask task, SubTask subTask) async {
    final now = DateTime.now();
    await widget.repository.upsertTask(
      task.copyWith(
        updatedAt: now,
        subTasks: [
          for (final candidate in task.subTasks)
            _isSameSubTask(candidate, subTask)
                ? candidate.copyWith(
                    isCompleted: !candidate.isCompleted,
                    updatedAt: now,
                    syncStatus: SyncStatus.pending,
                  )
                : candidate,
        ],
      ),
    );
  }

  bool _isSameSubTask(SubTask a, SubTask b) {
    if (a.id != 0 && b.id != 0) return a.id == b.id;
    if (a.syncId.isNotEmpty && b.syncId.isNotEmpty) return a.syncId == b.syncId;
    return identical(a, b);
  }

  Future<void> _deleteTask(TodoTask task) async {
    await widget.repository.moveTaskToTrash(task);
    if (!mounted) return;
    final strings = AppStrings.of(context);

    _showSnackBar(
      SnackBar(
        duration: _undoSnackBarFallbackDuration,
        content: Text(strings.taskMovedToTrash(task.title)),
        action: SnackBarAction(
          label: strings.undo,
          onPressed: () {
            unawaited(widget.repository.restoreTaskFromTrash(task));
          },
        ),
      ),
      forceDismissAfter: _trashSnackBarDuration,
    );
  }

  TodoSyncRunner get _syncRunner {
    return widget.syncRunner ??
        () => TodoSyncService(
              repository: widget.repository,
              settings: widget.settings,
            ).syncNow();
  }

  TodoSyncRunner get _manualSyncRunner {
    return widget.syncRunner ??
        () => TodoSyncService(
              repository: widget.repository,
              settings: widget.settings,
            ).syncNow(reconcileSnapshot: true);
  }

  bool get _canAutoSync {
    return widget.settings.serverConnectionStatus ==
            ServerConnectionStatus.connected &&
        widget.settings.refreshToken.isNotEmpty;
  }

  void _handleRepositoryChangedForSync() {
    if (!_canAutoSync) return;
    if (_autoSyncInFlight) {
      _autoSyncAgainAfterCurrent = true;
      return;
    }
    _scheduleAutoSync(delay: _autoSyncEditDebounce);
  }

  void _scheduleAutoSync({
    required Duration delay,
    bool pullEvenWithoutPending = false,
  }) {
    if (!_canAutoSync) return;
    _pendingAutoPull = _pendingAutoPull || pullEvenWithoutPending;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(delay, () => unawaited(_runAutoSync()));
  }

  Future<void> _runAutoSync() async {
    if (!_canAutoSync || _autoSyncInFlight || !mounted) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    final shouldPull = _pendingAutoPull;
    _pendingAutoPull = false;

    if (!shouldPull) {
      final pendingTasks = await widget.repository.getPendingSyncQueue(
        now: DateTime.now(),
        entityTypes: {'task'},
      );
      if (pendingTasks.isEmpty) return;
    }

    _autoSyncInFlight = true;
    try {
      await _syncRunner();
    } catch (_) {
      // Foreground auto sync is best-effort; manual sync still surfaces errors.
    } finally {
      _autoSyncInFlight = false;
      if (_autoSyncAgainAfterCurrent && mounted) {
        _autoSyncAgainAfterCurrent = false;
        _scheduleAutoSync(delay: _autoSyncEditDebounce);
      }
    }
  }
}

class CalendarHeader extends StatefulWidget {
  const CalendarHeader({
    super.key,
    required this.today,
    required this.dueDates,
    required this.monthExpanded,
    this.scopeVisibility = SyncVisibility.privateItem,
    required this.onToggleMonthExpanded,
    this.onToggleScopeVisibility,
    this.onCancelSelection,
    this.onMenuSelected,
    this.onDateSelected,
  });

  final DateTime today;
  final Set<DateTime> dueDates;
  final bool monthExpanded;
  final SyncVisibility scopeVisibility;
  final VoidCallback onToggleMonthExpanded;
  final VoidCallback? onToggleScopeVisibility;
  final VoidCallback? onCancelSelection;
  final ValueChanged<String>? onMenuSelected;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  State<CalendarHeader> createState() => _CalendarHeaderState();
}

class _CalendarHeaderState extends State<CalendarHeader> {
  static const _initialWeekPage = 10000;
  static const _initialMonthPage = 10000;
  static const _calendarAnimationDuration = Duration(milliseconds: 200);

  late final PageController _weekPageController;
  late final PageController _monthPageController;
  late final DateTime _baseDate;
  late DateTime _visibleDate;

  @override
  void initState() {
    super.initState();
    _baseDate = dateOnly(widget.today);
    _visibleDate = _baseDate;
    _weekPageController = PageController(initialPage: _initialWeekPage);
    _monthPageController = PageController(initialPage: _initialMonthPage);
  }

  @override
  void didUpdateWidget(CalendarHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.monthExpanded == widget.monthExpanded) return;

    if (widget.monthExpanded) {
      _jumpToPagerPageAfterBuild(
        _monthPageController,
        _monthPageForDate(_visibleDate),
      );
    } else {
      _jumpToPagerPageAfterBuild(
        _weekPageController,
        _weekPageForDate(_visibleDate),
      );
    }
  }

  @override
  void dispose() {
    _weekPageController.dispose();
    _monthPageController.dispose();
    super.dispose();
  }

  void _handleWeekPageChanged(int page) {
    final weekOffset = page - _initialWeekPage;
    setState(() {
      _visibleDate = dateOnly(_baseDate.add(Duration(days: weekOffset * 7)));
    });
  }

  void _handleMonthPageChanged(int page) {
    final monthOffset = page - _initialMonthPage;
    setState(() {
      _visibleDate = DateTime(_baseDate.year, _baseDate.month + monthOffset);
    });
  }

  int _monthPageForDate(DateTime date) {
    final monthOffset =
        ((date.year - _baseDate.year) * 12) + date.month - _baseDate.month;
    return _initialMonthPage + monthOffset;
  }

  int _weekPageForDate(DateTime date) {
    final baseWeekStart = _weekStartDate(_baseDate);
    final dateWeekStart = _weekStartDate(date);
    final weekOffset = dateWeekStart.difference(baseWeekStart).inDays ~/ 7;
    return _initialWeekPage + weekOffset;
  }

  void _jumpToPagerPageAfterBuild(PageController controller, int page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpToPage(page);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final visibleMonthCells = _monthCalendarCells(_visibleDate);
    final calendarHeight = widget.monthExpanded
        ? _CalendarGrid.heightForCellCount(visibleMonthCells.length)
        : _CalendarGrid.weekHeight;

    return Material(
      color: plannerTopPanelColor(theme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              6,
              2,
              6,
              widget.monthExpanded ? 6 : 10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.onToggleMonthExpanded,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            Text(
                              formatMonthYear(
                                _visibleDate,
                                language: strings.language,
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            AnimatedRotation(
                              turns: widget.monthExpanded ? 0.5 : 0,
                              duration: _calendarAnimationDuration,
                              curve: Curves.easeOutCubic,
                              child: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.onToggleScopeVisibility != null)
                      IconButton(
                        tooltip: widget.scopeVisibility == SyncVisibility.shared
                            ? strings.showPersonalOnly
                            : strings.showPersonalAndShared,
                        onPressed: widget.onToggleScopeVisibility,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(6),
                        icon: SyncVisibilityIcon(
                          visibility: widget.scopeVisibility,
                          size: 22,
                          showTooltip: false,
                        ),
                      ),
                    if (widget.onCancelSelection != null)
                      TextButton(
                        onPressed: widget.onCancelSelection,
                        child: Text(strings.cancel),
                      )
                    else if (widget.onMenuSelected != null)
                      PopupMenuButton<String>(
                        tooltip: strings.openMenu,
                        icon: const Icon(Icons.settings_outlined),
                        onSelected: widget.onMenuSelected,
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'select',
                            child: Text(strings.select),
                          ),
                          PopupMenuItem(
                            value: 'sort',
                            child: Text(strings.sort),
                          ),
                          PopupMenuItem(
                            value: 'trash',
                            child: Text(strings.trash),
                          ),
                          PopupMenuItem(
                            value: 'completed',
                            child: Text(strings.completed),
                          ),
                          PopupMenuItem(
                            value: 'settings',
                            child: Text(strings.settings),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRect(
                  child: AnimatedSize(
                    duration: _calendarAnimationDuration,
                    curve: Curves.easeOutCubic,
                    child: SizedBox(
                      height: calendarHeight,
                      child: widget.monthExpanded
                          ? PageView.builder(
                              key: const ValueKey('month-pager'),
                              controller: _monthPageController,
                              onPageChanged: _handleMonthPageChanged,
                              itemBuilder: (context, page) {
                                final monthOffset = page - _initialMonthPage;
                                final monthDate = DateTime(
                                  _baseDate.year,
                                  _baseDate.month + monthOffset,
                                );
                                return _CalendarGridViewport(
                                  cells: _monthCalendarCells(monthDate),
                                  today: widget.today,
                                  dueDates: widget.dueDates,
                                  onDateSelected: widget.onDateSelected,
                                );
                              },
                            )
                          : PageView.builder(
                              key: const ValueKey('week-pager'),
                              controller: _weekPageController,
                              onPageChanged: _handleWeekPageChanged,
                              itemBuilder: (context, page) {
                                final weekOffset = page - _initialWeekPage;
                                final weekDate = dateOnly(
                                  _baseDate.add(
                                    Duration(days: weekOffset * 7),
                                  ),
                                );
                                return _CalendarGridViewport(
                                  cells: [
                                    for (final date
                                        in _currentWeekDates(weekDate))
                                      date,
                                  ],
                                  today: widget.today,
                                  dueDates: widget.dueDates,
                                  onDateSelected: widget.onDateSelected,
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return AlertDialog(
      title: Text(strings.newCategory),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: strings.categoryName),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(strings.move),
        ),
      ],
    );
  }
}

class _TaskSelectionActionDock extends StatelessWidget {
  const _TaskSelectionActionDock({
    required this.onMarkDone,
    required this.onMoveCategory,
    required this.onDelete,
  });

  final VoidCallback onMarkDone;
  final VoidCallback onMoveCategory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Material(
              elevation: 8,
              shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.20),
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SelectionActionButton(
                      icon: Icons.check_circle_outline,
                      label: strings.done,
                      onPressed: onMarkDone,
                    ),
                    _SelectionActionButton(
                      icon: Icons.label_outline,
                      label: strings.move,
                      onPressed: onMoveCategory,
                    ),
                    _SelectionActionButton(
                      icon: Icons.delete_outline,
                      label: strings.delete,
                      color: theme.colorScheme.error,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? theme.colorScheme.primary;

    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: resolvedColor,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.labelMedium,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.today,
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
    required this.onTap,
    required this.onToggleCompleted,
    required this.onToggleSubTask,
    required this.onDelete,
  });

  final TodoTask task;
  final DateTime today;
  final bool selectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback onTap;
  final Future<void> Function() onToggleCompleted;
  final Future<void> Function(SubTask subTask) onToggleSubTask;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final dueText = task.dueDateTime == null
        ? ''
        : formatListDueDate(task.dueDateTime!, language: strings.language);
    final dueDelta = task.dueDateTime == null
        ? null
        : dueDateDayDelta(task.dueDateTime!, today: today);
    final dueColor = task.isCompleted
        ? theme.colorScheme.onSurfaceVariant
        : dueDelta == null
            ? theme.colorScheme.onSurfaceVariant
            : dueDelta < 0
                ? theme.colorScheme.error
                : dueDelta == 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant;

    final rowContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: task.isCompleted ? 0.62 : 1,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  2,
                  4,
                  2,
                  task.subTasks.isNotEmpty ? 0 : 4,
                ),
                child: Row(
                  children: [
                    if (selectionMode)
                      const SizedBox(width: 10, height: 48)
                    else
                      SizedBox.square(
                        dimension: 28,
                        child: Center(
                          child: _TaskCompletionBox(
                            state: task.isCompleted
                                ? _TaskCompletionState.complete
                                : task.isPartiallyCompleted
                                    ? _TaskCompletionState.partial
                                    : _TaskCompletionState.open,
                            onPressed: () => unawaited(onToggleCompleted()),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    if (dueText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 136),
                          child: Text(
                            dueText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: dueColor,
                              fontWeight: dueDelta == null || dueDelta > 0
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (task.subTasks.isNotEmpty) ...[
                _SubTaskPreview(
                  subTasks: task.subTasks,
                  today: today,
                  onToggleSubTask: onToggleSubTask,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final row = selectionMode
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                child: Transform.scale(
                  scale: 0.9,
                  child: Checkbox(
                    value: isSelected,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (value) {
                      onSelectionChanged?.call(value ?? false);
                    },
                  ),
                ),
              ),
              Expanded(child: rowContent),
            ],
          )
        : rowContent;

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction:
          selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await onDelete();
        return false;
      },
      background: const SwipeDeleteBackground(icon: Icons.delete),
      child: row,
    );
  }
}

enum _TaskCompletionState {
  open,
  partial,
  complete,
}

class _TaskCompletionBox extends StatelessWidget {
  const _TaskCompletionBox({
    required this.state,
    required this.onPressed,
  });

  final _TaskCompletionState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isComplete = state == _TaskCompletionState.complete;
    final isPartial = state == _TaskCompletionState.partial;

    return Semantics(
      button: true,
      checked: isComplete,
      child: InkResponse(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        radius: 18,
        child: SizedBox.square(
          dimension: 18,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isComplete ? primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: primary, width: 1.8),
                ),
              ),
              if (isPartial)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
              if (isComplete)
                Icon(
                  Icons.check,
                  size: 16,
                  color: theme.colorScheme.onPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTaskPreview extends StatelessWidget {
  const _SubTaskPreview({
    required this.subTasks,
    required this.today,
    required this.onToggleSubTask,
  });

  final List<SubTask> subTasks;
  final DateTime today;
  final Future<void> Function(SubTask subTask) onToggleSubTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final previewSubTasks = [
      for (final subTask in subTasks)
        if (!subTask.isCompleted) subTask,
      for (final subTask in subTasks)
        if (subTask.isCompleted) subTask,
    ];
    final visibleSubTasks = previewSubTasks.take(5).toList();
    final hiddenCount = previewSubTasks.length - visibleSubTasks.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 0, 10, 2),
      child: Column(
        children: [
          for (final subTask in visibleSubTasks)
            _SubTaskPreviewItem(
              subTask: subTask,
              today: today,
              onToggleSubTask: onToggleSubTask,
            ),
          if (hiddenCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  strings.hiddenSubtasks(hiddenCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SubTaskPreviewItem extends StatelessWidget {
  const _SubTaskPreviewItem({
    required this.subTask,
    required this.today,
    required this.onToggleSubTask,
  });

  final SubTask subTask;
  final DateTime today;
  final Future<void> Function(SubTask subTask) onToggleSubTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final dueText = subTask.dueDateTime == null
        ? ''
        : formatListDueDate(subTask.dueDateTime!, language: strings.language);
    final dueDelta = subTask.dueDateTime == null
        ? null
        : dueDateDayDelta(subTask.dueDateTime!, today: today);
    final dueColor = subTask.isCompleted
        ? theme.colorScheme.onSurfaceVariant
        : dueDelta == null
            ? theme.colorScheme.onSurfaceVariant
            : dueDelta < 0
                ? theme.colorScheme.error
                : dueDelta == 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => unawaited(onToggleSubTask(subTask)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 0),
            child: Row(
              children: [
                Icon(
                  subTask.isCompleted
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subTask.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration: subTask.isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                ),
                if (dueText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      dueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dueColor,
                        fontWeight: dueDelta == null || dueDelta > 0
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarGridViewport extends StatelessWidget {
  const _CalendarGridViewport({
    required this.cells,
    required this.today,
    required this.dueDates,
    this.onDateSelected,
  });

  final List<DateTime?> cells;
  final DateTime today;
  final Set<DateTime> dueDates;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: _CalendarGrid.maxHeight,
        child: SizedBox(
          height: _CalendarGrid.heightForCellCount(cells.length),
          child: _CalendarGrid(
            cells: cells,
            today: today,
            dueDates: dueDates,
            onDateSelected: onDateSelected,
          ),
        ),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.cells,
    required this.today,
    required this.dueDates,
    this.onDateSelected,
  });

  static const weekdayHeight = 20.0;
  static const weekdayGap = 8.0;
  static const dateCellHeight = 40.0;
  static const rowGap = 4.0;
  static const weekHeight = weekdayHeight + weekdayGap + dateCellHeight;
  static final maxHeight = heightForCellCount(42);

  static double heightForCellCount(int cellCount) {
    final calculatedRows = (cellCount + 6) ~/ 7;
    final rowCount = calculatedRows < 1
        ? 1
        : calculatedRows > 6
            ? 6
            : calculatedRows;
    return weekdayHeight +
        weekdayGap +
        (dateCellHeight * rowCount) +
        (rowGap * (rowCount - 1));
  }

  final List<DateTime?> cells;
  final DateTime today;
  final Set<DateTime> dueDates;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return Column(
      children: [
        SizedBox(
          height: weekdayHeight,
          child: Row(
            children: [
              for (final weekday in _calendarWeekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      _weekdayLabel(weekday, strings.language),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: weekdayGap),
        for (var row = 0; row < cells.length; row += 7)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : rowGap),
            child: Row(
              children: [
                for (final date in cells.skip(row).take(7))
                  Expanded(
                    child: _CalendarDateCell(
                      date: date,
                      today: today,
                      hasTask:
                          date != null && dueDates.contains(dateOnly(date)),
                      onDateSelected: onDateSelected,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalendarDateCell extends StatelessWidget {
  const _CalendarDateCell({
    required this.date,
    required this.today,
    required this.hasTask,
    this.onDateSelected,
  });

  final DateTime? date;
  final DateTime today;
  final bool hasTask;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentDate = date;
    if (currentDate == null) {
      return const SizedBox(height: _CalendarGrid.dateCellHeight);
    }

    final isToday = isSameDate(currentDate, today);
    final normalizedDate = dateOnly(currentDate);
    final color = isToday
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary.withValues(alpha: 0.60);
    final textColor = hasTask
        ? isToday
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSecondary
        : isToday
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;
    final border = hasTask && !isToday
        ? Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.42),
          )
        : null;

    return SizedBox(
      height: _CalendarGrid.dateCellHeight,
      child: Center(
        child: InkResponse(
          containedInkWell: true,
          customBorder: const CircleBorder(),
          onTap: onDateSelected == null
              ? null
              : () => onDateSelected!(normalizedDate),
          child: Container(
            key: ValueKey<DateTime>(normalizedDate),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: hasTask
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: border,
                  )
                : null,
            child: Text(
              '${currentDate.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight:
                    isToday || hasTask ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<DateTime> _currentWeekDates(DateTime today) {
  final weekStart = _weekStartDate(today);
  return List.generate(
      7, (index) => dateOnly(weekStart.add(Duration(days: index))));
}

DateTime _weekStartDate(DateTime date) {
  final normalizedDate = dateOnly(date);
  return normalizedDate.subtract(Duration(days: normalizedDate.weekday % 7));
}

List<DateTime?> _monthCalendarCells(DateTime monthDate) {
  final firstDay = DateTime(monthDate.year, monthDate.month);
  final lastDay = DateTime(monthDate.year, monthDate.month + 1, 0);
  final leadingEmptyCells = firstDay.weekday % 7;
  final cells = <DateTime?>[
    for (var i = 0; i < leadingEmptyCells; i++) null,
    for (var day = 1; day <= lastDay.day; day++)
      DateTime(monthDate.year, monthDate.month, day),
  ];

  while (cells.length % 7 != 0) {
    cells.add(null);
  }

  return cells;
}

const _calendarWeekdays = [
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
];

String _weekdayLabel(int weekday, AppLanguage language) {
  if (language == AppLanguage.korean) {
    switch (weekday) {
      case DateTime.monday:
        return '월';
      case DateTime.tuesday:
        return '화';
      case DateTime.wednesday:
        return '수';
      case DateTime.thursday:
        return '목';
      case DateTime.friday:
        return '금';
      case DateTime.saturday:
        return '토';
      case DateTime.sunday:
        return '일';
      default:
        return '';
    }
  }

  switch (weekday) {
    case DateTime.monday:
      return 'Mon';
    case DateTime.tuesday:
      return 'Tue';
    case DateTime.wednesday:
      return 'Wed';
    case DateTime.thursday:
      return 'Thu';
    case DateTime.friday:
      return 'Fri';
    case DateTime.saturday:
      return 'Sat';
    case DateTime.sunday:
      return 'Sun';
    default:
      return '';
  }
}
