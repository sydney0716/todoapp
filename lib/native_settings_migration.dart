import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LegacySettingsMigrationResult {
  const LegacySettingsMigrationResult({
    required this.settings,
    required this.shouldMarkComplete,
  });

  final Map<String, Object?> settings;
  final bool shouldMarkComplete;
}

class NativeSettingsMigration {
  static const _channel = MethodChannel(
    'com.example.personaltodo/settings_migration',
  );

  static Future<LegacySettingsMigrationResult> readLegacySettings() async {
    try {
      final settings = await _channel.invokeMapMethod<String, Object?>(
        'readLegacySettings',
      );
      return LegacySettingsMigrationResult(
        settings: settings ?? const {},
        shouldMarkComplete: true,
      );
    } on MissingPluginException {
      return LegacySettingsMigrationResult(
        settings: const {},
        shouldMarkComplete: defaultTargetPlatform != TargetPlatform.android,
      );
    } on PlatformException {
      return const LegacySettingsMigrationResult(
        settings: {},
        shouldMarkComplete: false,
      );
    }
  }
}
