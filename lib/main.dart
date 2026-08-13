import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/todo_api_client.dart';
import 'app_strings.dart';
import 'local_todo_repository.dart';
import 'models.dart';
import 'native_settings_migration.dart';
import 'native_widget_bridge.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/task_editor_screen.dart';
import 'settings_controller.dart';
import 'task_notification_service.dart';
import 'theme.dart';
import 'todo_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    PersonalTodoApp(
      repository: repository,
      settings: settings,
    ),
  );
}

class PersonalTodoApp extends StatefulWidget {
  const PersonalTodoApp({
    super.key,
    required this.repository,
    required this.settings,
  });

  final LocalTodoRepository repository;
  final SettingsController settings;

  @override
  State<PersonalTodoApp> createState() => _PersonalTodoAppState();
}

class _PersonalTodoAppState extends State<PersonalTodoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final WidgetsBindingObserver _lifecycleObserver;
  bool _nativeWidgetSyncInFlight = false;
  bool _nativeWidgetSyncAgainAfterCurrent = false;
  bool _nativeWidgetStartupComplete = false;

  @override
  void initState() {
    super.initState();
    _syncCurrentUser();
    widget.settings.addListener(_syncCurrentUser);
    widget.settings.addListener(_syncTaskNotifications);
    widget.repository.addListener(_syncTaskNotifications);
    NativeWidgetBridge.setActionHandler(_handleNativeWidgetAction);
    _lifecycleObserver = _AppLifecycleObserver(
      onResumed: () => unawaited(
        widget.repository.reload(
          refreshNativeWidget: _nativeWidgetStartupComplete,
        ),
      ),
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncNativeWidgetStartup());
      _syncTaskNotifications();
    });
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncCurrentUser);
    widget.settings.removeListener(_syncTaskNotifications);
    widget.repository.removeListener(_syncTaskNotifications);
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
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
    } else if (_nativeWidgetStartupComplete) {
      unawaited(NativeWidgetBridge.refreshHomeWidget(
        tasks: widget.repository.tasks,
        languageCode: widget.settings.language.languageCode,
        themeMode: widget.settings.themeMode.storedValue,
        currentUserId: widget.settings.currentUserId,
      ));
    }
  }

  void _syncTaskNotifications() {
    unawaited(
      TaskNotificationService.syncTasks(
        activeTasks: widget.repository.tasks,
        trashTasks: widget.repository.trashTasks,
        language: widget.settings.language,
        timeFormat: widget.settings.timeFormat,
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
      case NativeWidgetBridge.openNewTaskAction:
        await _openNewTaskFromWidget(
          initialDueDate: _dateFromMillisArgument(arguments, 'dueAtMillis'),
        );
        return;
      case NativeWidgetBridge.completeTaskAction:
        final taskId = _intArgument(arguments, 'taskId');
        if (taskId == null) return;
        final didChange = await widget.repository.markTaskDoneById(taskId);
        if (didChange) {
          unawaited(_syncNativeWidgetMutation());
        }
        return;
      case NativeWidgetBridge.toggleTaskCompletionAction:
        final taskId = _intArgument(arguments, 'taskId');
        if (taskId == null) return;
        final task = widget.repository.getTask(taskId);
        final didChange = task?.requiresBothSharedCompletion == true
            ? await widget.repository.toggleSharedTaskCompletionById(taskId)
            : await widget.repository.markTaskDoneById(taskId);
        if (didChange) {
          unawaited(_syncNativeWidgetMutation());
        }
        return;
      case NativeWidgetBridge.completeSubTaskAction:
        final taskId = _intArgument(arguments, 'taskId');
        final subTaskId = _intArgument(arguments, 'subTaskId');
        if (taskId == null || subTaskId == null) return;
        final didChange =
            await widget.repository.markSubTaskDoneById(taskId, subTaskId);
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
    if (!_canSyncNativeWidgetMutation) return;
    if (_nativeWidgetSyncInFlight) {
      _nativeWidgetSyncAgainAfterCurrent = true;
      return;
    }

    _nativeWidgetSyncInFlight = true;
    try {
      await TodoSyncService(
        repository: widget.repository,
        settings: widget.settings,
      ).syncNow();
    } catch (_) {
      // Widget-triggered sync is best-effort; manual sync still surfaces errors.
    } finally {
      _nativeWidgetSyncInFlight = false;
      if (_nativeWidgetSyncAgainAfterCurrent) {
        _nativeWidgetSyncAgainAfterCurrent = false;
        unawaited(_syncNativeWidgetMutation());
      }
    }
  }

  bool get _canSyncNativeWidgetMutation {
    return _hasStoredSession &&
        widget.settings.serverConnectionStatus ==
            ServerConnectionStatus.connected &&
        widget.settings.refreshToken.isNotEmpty;
  }

  Future<void> _openNewTaskFromWidget({DateTime? initialDueDate}) async {
    await widget.repository.reload();
    if (!mounted) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => TaskEditorScreen(
          repository: widget.repository,
          settings: widget.settings,
          initialDueDate: initialDueDate,
        ),
      ),
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
                )
              : LoginScreen(
                  onLogin: _handleLogin,
                ),
        );
      },
    );
  }

  bool get _hasStoredSession {
    return widget.settings.initialLoginCompleted &&
        widget.settings.refreshToken.isNotEmpty &&
        (widget.settings.authDeviceId.isEmpty ||
            widget.settings.authDeviceId == widget.repository.deviceId);
  }

  Future<void> _handleLogin(AppAccount account, String password) async {
    final result = await verifyTodoServerConnection(
      baseUrl: widget.settings.apiBaseUrl,
      username: account.username,
      password: password,
      deviceId: widget.repository.deviceId,
    );
    final taskCount = await widget.repository.reconcileBootstrapTasks(
      result.bootstrap.tasks.map((task) => task.toTodoTask()).toList(),
    );
    await widget.settings.recordServerConnectionSuccess(
      username: account.username,
      cursor: result.bootstrap.cursor,
      taskCount: taskCount,
      session: result.session,
    );
    _syncCurrentUser();
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  _AppLifecycleObserver({required this.onResumed});

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
