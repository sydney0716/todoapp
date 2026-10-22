import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/todo_api_client.dart';
import 'app_strings.dart';
import 'background_sync_task.dart';
import 'browser_support.dart';
import 'local_todo_repository.dart';
import 'models.dart';
import 'mobile_background_sync.dart';
import 'native_settings_migration.dart';
import 'native_widget_bridge.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/task_editor_screen.dart';
import 'settings_controller.dart';
import 'server_api_config.dart';
import 'task_notification_service.dart';
import 'theme.dart';
import 'todo_sync_service.dart';
import 'todo_sync_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeBrowserStorage();

  final legacySettings = await NativeSettingsMigration.readLegacySettings();
  final settings = SettingsController();
  await settings.init(
    legacySettings: legacySettings.settings,
    legacyMigrationSucceeded: legacySettings.shouldMarkComplete,
  );
  await NativeWidgetBridge.refreshHomeWidget(
    languageCode: settings.language.languageCode,
    themeMode: settings.themeMode.storedValue,
    currentUserId: settings.currentUserId,
  );

  final repository = LocalTodoRepository(currentUserId: settings.currentUserId);
  await repository.init(refreshNativeWidget: false);
  await repository.moveExpiredCompletedTasksToTrash(
    settings.completedTaskRetentionPolicy,
    refreshNativeWidget: false,
  );
  await repository.purgeExpiredTrash(refreshNativeWidget: false);
  await MobileBackgroundSync.initialize();
  await MobileBackgroundSync.consumePhoneWidgetActions(repository);

  runApp(
    PersonalTodoApp(
      repository: repository,
      settings: settings,
      connectivityChanges: Connectivity().onConnectivityChanged.map(
            (types) => types.any((type) => type != ConnectivityResult.none),
          ),
    ),
  );
}

class PersonalTodoApp extends StatefulWidget {
  const PersonalTodoApp({
    super.key,
    required this.repository,
    required this.settings,
    this.periodicSyncRunner,
    this.connectivityChanges,
  });

  final LocalTodoRepository repository;
  final SettingsController settings;
  final TodoSyncRunner? periodicSyncRunner;
  final Stream<bool>? connectivityChanges;

  @override
  State<PersonalTodoApp> createState() => _PersonalTodoAppState();
}

class _PersonalTodoAppState extends State<PersonalTodoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final WidgetsBindingObserver _lifecycleObserver;
  late final TodoSyncCoordinator _sync;
  bool _nativeWidgetStartupComplete = false;
  bool _refreshReminderPermissions = false;
  bool _reconnectVisible = false;
  bool _appInactive = false;
  int? _widgetTaskId;

  @override
  void initState() {
    super.initState();
    _syncCurrentUser();
    final service = TodoSyncService(
        repository: widget.repository, settings: widget.settings);
    _sync = TodoSyncCoordinator(
        repository: widget.repository,
        settings: widget.settings,
        connectivityChanges: widget.connectivityChanges,
        backgroundPollInterval:
            !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
                ? backgroundRefreshInterval
                : null,
        runner: (snapshot) =>
            widget.periodicSyncRunner?.call() ??
            service.syncNow(reconcileSnapshot: snapshot))
      ..start();
    widget.settings.addListener(_syncCurrentUser);
    widget.settings.addListener(_syncTaskNotifications);
    widget.settings.addListener(_handleSessionChanged);
    widget.repository.addListener(_syncTaskNotifications);
    NativeWidgetBridge.setActionHandler(_handleNativeWidgetAction);
    _lifecycleObserver = _AppLifecycleObserver(
      onResumed: () => unawaited(_handleAppResumed()),
      onBackground: _handleAppBackgrounded,
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncNativeWidgetStartup());
      _syncTaskNotifications();
      unawaited(_showReconnect());
    });
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncCurrentUser);
    widget.settings.removeListener(_syncTaskNotifications);
    widget.settings.removeListener(_handleSessionChanged);
    widget.repository.removeListener(_syncTaskNotifications);
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _sync.dispose();
    NativeWidgetBridge.clearActionHandler();
    super.dispose();
  }

  Future<void> _handleAppResumed() async {
    _appInactive = false;
    _refreshReminderPermissions = true;
    await _sync.waitUntilIdle();
    await widget.settings.reload();
    await MobileBackgroundSync.consumePhoneWidgetActions(widget.repository);
    await widget.repository
        .reload(refreshNativeWidget: _nativeWidgetStartupComplete);
    if (!mounted) return;
    _sync.setForeground(true);
    unawaited(_showReconnect());
    await NativeWidgetBridge.consumePendingWidgetActions();
  }

  void _handleAppBackgrounded() {
    if (_appInactive) return;
    _appInactive = true;
    _sync.setForeground(false);
    unawaited(BackgroundSyncTask.run(_sync.finishPendingChanges));
  }

  void _handleSessionChanged() {
    if (!widget.settings.initialLoginCompleted || _sync.canSync) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showReconnect());
    });
  }

  void _syncCurrentUser() {
    final nextUserId = widget.settings.currentUserId;
    final didChangeUser = widget.repository.currentUserId != nextUserId;
    widget.repository.currentUserId = nextUserId;
    if (didChangeUser) {
      unawaited(
        widget.repository.reload(
          refreshNativeWidget: _nativeWidgetStartupComplete,
        ),
      );
    }
  }

  void _syncTaskNotifications() {
    final force = _refreshReminderPermissions;
    _refreshReminderPermissions = false;
    unawaited(
      TaskNotificationService.syncTasks(
        activeTasks: widget.repository.tasks,
        trashTasks: widget.repository.trashTasks,
        language: widget.settings.language,
        timeFormat: widget.settings.timeFormat,
        force: force,
      ),
    );
  }

  Future<void> _consumeInitialNativeWidgetAction() async {
    await NativeWidgetBridge.consumePendingWidgetActions();
    final action = await NativeWidgetBridge.consumeInitialAction();
    if (!mounted || action == null) return;
    await _handleNativeWidgetAction(action, const {});
  }

  Future<void> _syncNativeWidgetStartup() async {
    await _consumeInitialNativeWidgetAction();
    if (!mounted) return;

    await NativeWidgetBridge.refreshHomeWidget(
      tasks: widget.repository.tasks,
      languageCode: widget.settings.language.languageCode,
      themeMode: widget.settings.themeMode.storedValue,
      currentUserId: widget.settings.currentUserId,
    );
    _nativeWidgetStartupComplete = true;
  }

  Future<void> _handleNativeWidgetAction(
    String action,
    Map<String, Object?> arguments,
  ) async {
    switch (action) {
      case NativeWidgetBridge.openAppAction:
        return;
      case NativeWidgetBridge.openTaskAction:
        final taskId = _intArgument(arguments, 'taskId');
        if (taskId != null && taskId > 0) {
          await _openTaskFromWidget(taskId);
        }
        return;
      case NativeWidgetBridge.openNewTaskAction:
        await _openNewTaskFromWidget(
          initialDueDate: _dateFromMillisArgument(arguments, 'dueAtMillis'),
        );
        return;
      case NativeWidgetBridge.completeTaskAction:
        final taskId = _intArgument(arguments, 'taskId');
        if (taskId == null) return;
        final didChange = await widget.repository
            .markTaskDoneById(taskId, actionId: arguments['id'] as String?);
        if (didChange) {
          unawaited(_syncNativeWidgetMutation());
        }
        return;
      case NativeWidgetBridge.setTaskCompletionAction:
        final taskId = _intArgument(arguments, 'taskId');
        final isCompleted = arguments['isCompleted'];
        if (taskId == null || isCompleted is! bool) return;
        final didChange = await widget.repository.setTaskCompletionById(taskId,
            isCompleted: isCompleted, actionId: arguments['id'] as String?);
        if (didChange) {
          unawaited(_syncNativeWidgetMutation());
        }
        return;
      case NativeWidgetBridge.toggleTaskCompletionAction:
        final taskId = _intArgument(arguments, 'taskId');
        if (taskId == null) return;
        final task = widget.repository.getTask(taskId);
        final didChange = task?.requiresBothSharedCompletion == true
            ? await widget.repository.toggleSharedTaskCompletionById(taskId,
                actionId: arguments['id'] as String?)
            : await widget.repository
                .markTaskDoneById(taskId, actionId: arguments['id'] as String?);
        if (didChange) {
          unawaited(_syncNativeWidgetMutation());
        }
        return;
      case NativeWidgetBridge.completeSubTaskAction:
        final taskId = _intArgument(arguments, 'taskId');
        final subTaskId = _intArgument(arguments, 'subTaskId');
        if (taskId == null || subTaskId == null) return;
        final didChange = await widget.repository.markSubTaskDoneById(
            taskId, subTaskId,
            actionId: arguments['id'] as String?);
        if (didChange) {
          unawaited(_syncNativeWidgetMutation());
        }
        return;
    }
  }

  int? _intArgument(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  DateTime? _dateFromMillisArgument(
    Map<String, Object?> arguments,
    String key,
  ) {
    final millis = _intArgument(arguments, key);
    if (millis == null) return null;

    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> _syncNativeWidgetMutation() async {
    if (!_sync.canSync) return;
    try {
      await _sync.syncNow();
    } on Object {/* Coordinator exposes sync errors. */}
  }

  Future<void> _openNewTaskFromWidget({DateTime? initialDueDate}) async {
    await widget.repository.reload();
    if (!mounted) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => TaskEditorScreen(
            repository: widget.repository,
            settings: widget.settings,
            initialDueDate: initialDueDate,
          ),
        ),
      ),
    );
  }

  Future<void> _openTaskFromWidget(int taskId) async {
    await widget.repository.reload();
    if (!mounted || !_hasStoredSession) return;
    if (_navigatorKey.currentState == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || _widgetTaskId == taskId) return;

    final task = widget.repository.getTask(taskId);
    final navigator = _navigatorKey.currentState;
    if (task == null || navigator == null) return;

    _widgetTaskId = taskId;
    unawaited(
      navigator
          .push(
        MaterialPageRoute<void>(
          builder: (_) => TaskEditorScreen(
            repository: widget.repository,
            settings: widget.settings,
            task: task,
          ),
        ),
      )
          .whenComplete(() {
        if (_widgetTaskId == taskId) _widgetTaskId = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        final strings = AppStrings.forLanguage(widget.settings.language);

        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: strings.appTitle,
          locale: widget.settings.language.locale,
          supportedLocales:
              AppLanguage.values.map((language) => language.locale),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: flutterThemeMode(widget.settings.themeMode),
          home: _hasStoredSession
              ? HomeScreen(
                  repository: widget.repository,
                  settings: widget.settings,
                  syncCoordinator: _sync,
                  onReconnect: _showReconnect,
                )
              : LoginScreen(
                  onLogin: _handleLogin,
                  onConfigureServer: _configureServer,
                ),
        );
      },
    );
  }

  bool get _hasStoredSession {
    return widget.settings.initialLoginCompleted;
  }

  Future<void> _configureServer() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final controller = TextEditingController(text: widget.settings.apiBaseUrl);
    final isKorean = widget.settings.language == AppLanguage.korean;
    String? error;
    final value = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: Text(isKorean ? '서버 주소' : 'Server address'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(isKorean
                        ? '주소를 변경하면 현재 기기의 할 일을 새 서버로 동기화하며 다시 로그인해야 합니다.'
                        : 'Changing the address keeps this device’s tasks for syncing to the new server and requires signing in again.'),
                    TextField(
                        controller: controller,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(errorText: error)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(isKorean ? '취소' : 'Cancel')),
                    FilledButton(
                        onPressed: () {
                          try {
                            Navigator.pop(context,
                                validateTodoApiBaseUrl(controller.text));
                          } on FormatException catch (e) {
                            setState(() => error = e.message);
                          }
                        },
                        child: Text(isKorean ? '저장' : 'Save'))
                  ],
                )));
    controller.dispose();
    if (value == null || value == widget.settings.apiBaseUrl) return;
    _sync.setForeground(false);
    try {
      await _sync.waitUntilIdle();
      await widget.repository.prepareForServerChange();
      await widget.settings.setApiBaseUrl(value);
    } finally {
      if (mounted) _sync.setForeground(true);
    }
  }

  Future<void> _showReconnect() async {
    if (!mounted ||
        _reconnectVisible ||
        !widget.settings.initialLoginCompleted ||
        _sync.canSync) {
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _reconnectVisible = true;
    try {
      await navigator.push(MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
                accounts: appAccounts
                    .where((account) =>
                        account.id == widget.settings.currentUserId)
                    .toList(),
                onLogin: (account, password) async {
                  await _handleLogin(account, password);
                  if (navigator.mounted) navigator.pop();
                },
              )));
    } finally {
      _reconnectVisible = false;
    }
  }

  Future<void> _handleLogin(AppAccount account, String password) async {
    final result = await verifyTodoServerConnection(
      baseUrl: widget.settings.apiBaseUrl,
      username: account.username,
      password: password,
      deviceId: widget.repository.deviceId,
    );
    await widget.repository.reconcileBootstrapTasks(
      result.bootstrap.tasks.map((task) => task.toTodoTask()).toList(),
    );
    await widget.settings.recordServerConnectionSuccess(
      cursor: result.bootstrap.cursor,
      session: result.session,
    );
    _syncCurrentUser();
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  _AppLifecycleObserver({required this.onResumed, required this.onBackground});

  final VoidCallback onResumed;
  final VoidCallback onBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    } else {
      onBackground();
    }
  }
}
