import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'api/todo_api_models.dart';
import 'models.dart';
import 'native_widget_bridge.dart';
import 'server_api_config.dart';
import 'settings_store.dart';

enum AppThemeMode {
  dark,
  light,
  followSystem;

  String get label {
    switch (this) {
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.followSystem:
        return 'Follow system';
    }
  }

  String get storedValue {
    switch (this) {
      case AppThemeMode.dark:
        return 'DARK';
      case AppThemeMode.light:
        return 'LIGHT';
      case AppThemeMode.followSystem:
        return 'FOLLOW_SYSTEM';
    }
  }

  static AppThemeMode fromStoredValue(String? value) {
    return AppThemeMode.values.firstWhere(
      (mode) => mode.storedValue == value,
      orElse: () => AppThemeMode.light,
    );
  }
}

enum AppTimeFormat {
  twentyFourHour,
  amPm;

  String get label {
    switch (this) {
      case AppTimeFormat.twentyFourHour:
        return '24 hour';
      case AppTimeFormat.amPm:
        return 'AM/PM';
    }
  }

  String get storedValue {
    switch (this) {
      case AppTimeFormat.twentyFourHour:
        return 'TWENTY_FOUR_HOUR';
      case AppTimeFormat.amPm:
        return 'AM_PM';
    }
  }

  static AppTimeFormat fromStoredValue(String? value) {
    return AppTimeFormat.values.firstWhere(
      (format) => format.storedValue == value,
      orElse: () => AppTimeFormat.amPm,
    );
  }
}

enum AppLanguage {
  korean('ko', 'Korean'),
  english('en', 'English');

  const AppLanguage(this.languageCode, this.label);

  final String languageCode;
  final String label;

  Locale get locale => Locale(languageCode);

  static AppLanguage fromStoredValue(String? value) {
    return AppLanguage.values.firstWhere(
      (language) => language.languageCode == value,
      orElse: () => AppLanguage.korean,
    );
  }
}

enum TaskSortOption {
  dueDate('Due date', 'due_date'),
  title('Title', 'title'),
  lastModified('Last modified', 'last_modified');

  const TaskSortOption(this.label, this.storedValue);

  final String label;
  final String storedValue;

  static TaskSortOption fromStoredValue(String? value) {
    return TaskSortOption.values.firstWhere(
      (option) => option.storedValue == value,
      orElse: () => TaskSortOption.dueDate,
    );
  }
}

enum TaskSortDirection {
  ascending('Ascending order', 'ascending'),
  descending('Descending order', 'descending');

  const TaskSortDirection(this.label, this.storedValue);

  final String label;
  final String storedValue;

  static TaskSortDirection fromStoredValue(String? value) {
    return TaskSortDirection.values.firstWhere(
      (direction) => direction.storedValue == value,
      orElse: () => TaskSortDirection.ascending,
    );
  }
}

enum ServerConnectionStatus {
  notConnected('not_connected', 'Not connected yet'),
  connected('connected', 'Connected'),
  failed('failed', 'Connection failed');

  const ServerConnectionStatus(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static ServerConnectionStatus fromStoredValue(String? value) {
    return ServerConnectionStatus.values.firstWhere(
      (status) => status.storedValue == value,
      orElse: () => ServerConnectionStatus.notConnected,
    );
  }
}

class SettingsController extends ChangeNotifier {
  static const _showCompletedTasksKey = 'show_completed_tasks';
  static const _themeModeKey = 'theme_mode';
  static const _timeFormatKey = 'time_format';
  static const _languageKey = 'app_language';
  static const _legacySettingsMigratedKey = 'legacy_settings_migrated';
  static const _completedTaskRetentionPolicyKey =
      'completed_task_retention_policy';
  static const _currentUserIdKey = 'current_user_id';
  static const _taskSortOptionKey = 'task_sort_option';
  static const _taskSortDirectionKey = 'task_sort_direction';
  static const _apiBaseUrlKey = 'api_base_url';
  static const _serverConnectionStatusKey = 'server_connection_status';
  static const _serverConnectionUsernameKey = 'server_connection_username';
  static const _lastSyncCursorKey = 'last_sync_cursor';
  static const _lastSyncAtKey = 'last_sync_at';
  static const _lastBootstrapTaskCountKey = 'last_bootstrap_task_count';
  static const _accessTokenKey = 'server_access_token';
  static const _refreshTokenKey = 'server_refresh_token';
  static const _authDeviceIdKey = 'server_auth_device_id';
  static const _initialLoginCompletedKey = 'initial_login_completed';

  SettingsController({SettingsStore? store})
      : _store = store ?? SettingsStore();

  final SettingsStore _store;

  bool showCompletedTasks = true;
  AppThemeMode themeMode = AppThemeMode.light;
  AppTimeFormat timeFormat = AppTimeFormat.amPm;
  AppLanguage language = AppLanguage.korean;
  CompletedTaskRetentionPolicy completedTaskRetentionPolicy =
      CompletedTaskRetentionPolicy.oneMonth;
  String currentUserId = defaultCurrentUserId;
  TaskSortOption taskSortOption = TaskSortOption.dueDate;
  TaskSortDirection taskSortDirection = TaskSortDirection.ascending;
  String apiBaseUrl = defaultTodoApiBaseUrl;
  ServerConnectionStatus serverConnectionStatus =
      ServerConnectionStatus.notConnected;
  String serverConnectionUsername = '';
  String lastSyncCursor = '';
  DateTime? lastSyncAt;
  int lastBootstrapTaskCount = 0;
  String accessToken = '';
  String refreshToken = '';
  String authDeviceId = '';
  bool initialLoginCompleted = false;

  Future<void> init({
    Map<String, Object?> legacySettings = const {},
    bool legacyMigrationSucceeded = true,
  }) async {
    await _store.init();
    if (!(await _store.getBool(_legacySettingsMigratedKey) ?? false)) {
      await _applyLegacySettings(legacySettings);
      if (legacyMigrationSucceeded) {
        await _store.setBool(_legacySettingsMigratedKey, true);
      }
    }
    await _read();
  }

  Future<void> close() async {
    await _store.close();
  }

  Future<void> setShowCompletedTasks(bool value) async {
    showCompletedTasks = value;
    await _store.setBool(_showCompletedTasksKey, value);
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode value) async {
    themeMode = value;
    await _store.setString(_themeModeKey, value.storedValue);
    unawaited(NativeWidgetBridge.refreshHomeWidget(
      themeMode: value.storedValue,
    ));
    notifyListeners();
  }

  Future<void> setTimeFormat(AppTimeFormat value) async {
    timeFormat = value;
    await _store.setString(_timeFormatKey, value.storedValue);
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage value) async {
    language = value;
    await _store.setString(_languageKey, value.languageCode);
    unawaited(NativeWidgetBridge.refreshHomeWidget(
      languageCode: value.languageCode,
    ));
    notifyListeners();
  }

  Future<void> setCompletedTaskRetentionPolicy(
    CompletedTaskRetentionPolicy value,
  ) async {
    completedTaskRetentionPolicy = value;
    await _store.setString(
      _completedTaskRetentionPolicyKey,
      value.storedValue,
    );
    notifyListeners();
  }

  Future<void> setCurrentUserId(String value) async {
    currentUserId = appAccounts.any((account) => account.id == value)
        ? value
        : defaultCurrentUserId;
    await _store.setString(_currentUserIdKey, currentUserId);
    unawaited(NativeWidgetBridge.refreshHomeWidget(
      currentUserId: currentUserId,
    ));
    notifyListeners();
  }

  Future<void> setTaskSortOption(TaskSortOption value) async {
    taskSortOption = value;
    await _store.setString(_taskSortOptionKey, value.storedValue);
    notifyListeners();
  }

  Future<void> setTaskSortDirection(TaskSortDirection value) async {
    taskSortDirection = value;
    await _store.setString(_taskSortDirectionKey, value.storedValue);
    notifyListeners();
  }

  Future<void> setApiBaseUrl(String value) async {
    apiBaseUrl = normalizeTodoApiBaseUrl(value);
    await _store.setString(_apiBaseUrlKey, apiBaseUrl);
    notifyListeners();
  }

  Future<void> recordServerConnectionSuccess({
    required String username,
    required String cursor,
    required int taskCount,
    AuthSession? session,
  }) async {
    final syncedAt = DateTime.now();
    serverConnectionStatus = ServerConnectionStatus.connected;
    serverConnectionUsername = username.trim();
    lastSyncCursor = cursor;
    lastSyncAt = syncedAt;
    lastBootstrapTaskCount = taskCount;
    if (session != null) {
      _applyAuthSession(session);
    }
    await _store.setString(
      _serverConnectionStatusKey,
      serverConnectionStatus.storedValue,
    );
    await _store.setString(
      _serverConnectionUsernameKey,
      serverConnectionUsername,
    );
    await _store.setString(_lastSyncCursorKey, lastSyncCursor);
    await _store.setInt(_lastSyncAtKey, syncedAt.millisecondsSinceEpoch);
    await _store.setInt(_lastBootstrapTaskCountKey, lastBootstrapTaskCount);
    if (session != null) {
      await _writeAuthSession();
    }
    notifyListeners();
  }

  Future<void> recordAuthSession(AuthSession session) async {
    _applyAuthSession(session);
    await _writeAuthSession();
    notifyListeners();
  }

  Future<void> recordSyncSuccess({
    required String cursor,
    required int taskCount,
  }) async {
    final syncedAt = DateTime.now();
    serverConnectionStatus = ServerConnectionStatus.connected;
    lastSyncCursor = cursor;
    lastSyncAt = syncedAt;
    lastBootstrapTaskCount = taskCount;
    await _store.setString(
      _serverConnectionStatusKey,
      serverConnectionStatus.storedValue,
    );
    await _store.setString(_lastSyncCursorKey, lastSyncCursor);
    await _store.setInt(_lastSyncAtKey, syncedAt.millisecondsSinceEpoch);
    await _store.setInt(_lastBootstrapTaskCountKey, lastBootstrapTaskCount);
    notifyListeners();
  }

  Future<void> recordServerConnectionFailure() async {
    serverConnectionStatus = ServerConnectionStatus.failed;
    await _store.setString(
      _serverConnectionStatusKey,
      serverConnectionStatus.storedValue,
    );
    notifyListeners();
  }

  Future<void> _applyLegacySettings(Map<String, Object?> legacySettings) async {
    final showCompletedTasks = legacySettings[_showCompletedTasksKey];
    if (showCompletedTasks is bool &&
        !(await _store.containsKey(_showCompletedTasksKey))) {
      await _store.setBool(_showCompletedTasksKey, showCompletedTasks);
    }

    final themeMode = legacySettings[_themeModeKey];
    if (themeMode is String &&
        AppThemeMode.values.any((mode) => mode.storedValue == themeMode) &&
        !(await _store.containsKey(_themeModeKey))) {
      await _store.setString(_themeModeKey, themeMode);
    }

    final timeFormat = legacySettings[_timeFormatKey];
    if (timeFormat is String &&
        AppTimeFormat.values
            .any((format) => format.storedValue == timeFormat) &&
        !(await _store.containsKey(_timeFormatKey))) {
      await _store.setString(_timeFormatKey, timeFormat);
    }
  }

  Future<void> _read() async {
    showCompletedTasks = await _store.getBool(_showCompletedTasksKey) ?? true;
    themeMode = AppThemeMode.fromStoredValue(
      await _store.getString(_themeModeKey),
    );
    timeFormat = AppTimeFormat.fromStoredValue(
      await _store.getString(_timeFormatKey),
    );
    language =
        AppLanguage.fromStoredValue(await _store.getString(_languageKey));
    completedTaskRetentionPolicy = CompletedTaskRetentionPolicy.fromStoredValue(
      await _store.getString(_completedTaskRetentionPolicyKey),
    );
    currentUserId =
        _readCurrentUserId(await _store.getString(_currentUserIdKey));
    taskSortOption = TaskSortOption.fromStoredValue(
      await _store.getString(_taskSortOptionKey),
    );
    taskSortDirection = TaskSortDirection.fromStoredValue(
      await _store.getString(_taskSortDirectionKey),
    );
    apiBaseUrl = normalizeTodoApiBaseUrl(
      await _store.getString(_apiBaseUrlKey) ?? defaultTodoApiBaseUrl,
    );
    serverConnectionStatus = ServerConnectionStatus.fromStoredValue(
      await _store.getString(_serverConnectionStatusKey),
    );
    serverConnectionUsername =
        await _store.getString(_serverConnectionUsernameKey) ?? '';
    lastSyncCursor = await _store.getString(_lastSyncCursorKey) ?? '';
    lastSyncAt = _dateFromMillis(await _store.getInt(_lastSyncAtKey));
    lastBootstrapTaskCount =
        await _store.getInt(_lastBootstrapTaskCountKey) ?? 0;
    accessToken = await _store.getString(_accessTokenKey) ?? '';
    refreshToken = await _store.getString(_refreshTokenKey) ?? '';
    authDeviceId = await _store.getString(_authDeviceIdKey) ?? '';
    initialLoginCompleted =
        await _store.getBool(_initialLoginCompletedKey) ?? false;
  }

  void _applyAuthSession(AuthSession session) {
    accessToken = session.accessToken;
    refreshToken = session.refreshToken;
    authDeviceId = session.deviceId;
    currentUserId = _readCurrentUserId(session.userId);
  }

  Future<void> _writeAuthSession() async {
    initialLoginCompleted = true;
    await _store.setString(_currentUserIdKey, currentUserId);
    await _store.setString(_accessTokenKey, accessToken);
    await _store.setString(_refreshTokenKey, refreshToken);
    await _store.setString(_authDeviceIdKey, authDeviceId);
    await _store.setBool(_initialLoginCompletedKey, true);
  }

  String _readCurrentUserId(String? storedValue) {
    if (appAccounts.any((account) => account.id == storedValue)) {
      return storedValue!;
    }
    return defaultCurrentUserId;
  }

  DateTime? _dateFromMillis(int? millis) {
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
