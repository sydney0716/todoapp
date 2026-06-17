import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personaltodo/api/todo_api_models.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/settings_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('retries legacy settings migration after a failed native read',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_settings_');
    final databasePath = path.join(tempDir.path, 'settings.db');

    var settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init(
      legacySettings: const {},
      legacyMigrationSucceeded: false,
    );

    expect(settings.themeMode, AppThemeMode.light);
    await settings.close();

    settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init(
      legacySettings: const {'theme_mode': 'DARK'},
      legacyMigrationSucceeded: true,
    );
    addTearDown(() async {
      await settings.close();
      await tempDir.delete(recursive: true);
    });

    expect(settings.themeMode, AppThemeMode.dark);
  });

  test('does not reapply legacy settings after migration is complete',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_settings_');
    final databasePath = path.join(tempDir.path, 'settings.db');

    var settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init(
      legacySettings: const {},
      legacyMigrationSucceeded: true,
    );
    await settings.close();

    settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init(
      legacySettings: const {'theme_mode': 'DARK'},
      legacyMigrationSucceeded: true,
    );
    addTearDown(() async {
      await settings.close();
      await tempDir.delete(recursive: true);
    });

    expect(settings.themeMode, AppThemeMode.light);
  });

  test('persists completed task retention and current account choices',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_settings_');
    final databasePath = path.join(tempDir.path, 'settings.db');

    var settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    expect(settings.language, AppLanguage.korean);
    await settings.setCompletedTaskRetentionPolicy(
      CompletedTaskRetentionPolicy.sixMonths,
    );
    await settings.setCurrentUserId(partnerUserId);
    await settings.setLanguage(AppLanguage.english);
    await settings.close();

    settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    addTearDown(() async {
      await settings.close();
      await tempDir.delete(recursive: true);
    });

    expect(
      settings.completedTaskRetentionPolicy,
      CompletedTaskRetentionPolicy.sixMonths,
    );
    expect(settings.currentUserId, partnerUserId);
    expect(settings.language, AppLanguage.english);
  });

  test('persists task sort choice', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_settings_');
    final databasePath = path.join(tempDir.path, 'settings.db');

    var settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    await settings.setTaskSortOption(TaskSortOption.lastModified);
    await settings.setTaskSortDirection(TaskSortDirection.descending);
    await settings.close();

    settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    addTearDown(() async {
      await settings.close();
      await tempDir.delete(recursive: true);
    });

    expect(settings.taskSortOption, TaskSortOption.lastModified);
    expect(settings.taskSortDirection, TaskSortDirection.descending);
  });

  test('persists server connection session metadata', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_settings_');
    final databasePath = path.join(tempDir.path, 'settings.db');

    var settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    await settings.setApiBaseUrl('hytodo.duckdns.org/');
    await settings.recordServerConnectionSuccess(
      username: 'user',
      cursor: '12',
      taskCount: 3,
      session: const AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: defaultCurrentUserId,
        deviceId: '11111111-1111-4111-8111-111111111111',
      ),
    );
    await settings.close();

    settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    addTearDown(() async {
      await settings.close();
      await tempDir.delete(recursive: true);
    });

    expect(settings.apiBaseUrl, 'https://hytodo.duckdns.org');
    expect(settings.serverConnectionStatus, ServerConnectionStatus.connected);
    expect(settings.serverConnectionUsername, 'user');
    expect(settings.lastSyncCursor, '12');
    expect(settings.lastBootstrapTaskCount, 3);
    expect(settings.accessToken, 'access-token');
    expect(settings.refreshToken, 'refresh-token');
    expect(settings.authDeviceId, '11111111-1111-4111-8111-111111111111');
    expect(settings.initialLoginCompleted, isTrue);
  });

  test('auth session persists returned account identity', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('personaltodo_settings_');
    final databasePath = path.join(tempDir.path, 'settings.db');

    var settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    expect(settings.initialLoginCompleted, isFalse);
    await settings.recordServerConnectionSuccess(
      username: 'partner',
      cursor: '0',
      taskCount: 0,
      session: const AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        userId: partnerUserId,
        deviceId: '11111111-1111-4111-8111-111111111111',
      ),
    );
    await settings.close();

    settings = SettingsController(
      store: SettingsStore(databasePath: databasePath),
    );
    await settings.init();
    addTearDown(() async {
      await settings.close();
      await tempDir.delete(recursive: true);
    });

    expect(settings.currentUserId, partnerUserId);
    expect(settings.initialLoginCompleted, isTrue);
  });
}
