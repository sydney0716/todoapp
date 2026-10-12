import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Requests iOS time to finish a current upload; it does not schedule new work.
class BackgroundSyncTask {
  static const _channel =
      MethodChannel('com.example.personaltodo/background_sync');

  static Future<void> run(Future<void> Function() action) async {
    int? identifier;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        identifier = await _channel.invokeMethod<int>('begin');
      } on MissingPluginException {
        // The queued change can still be attempted without extra OS time.
      } on PlatformException {
        // iOS may decline a background execution request.
      }
    }
    try {
      await action();
    } finally {
      if (identifier != null) {
        try {
          await _channel.invokeMethod<void>('end', identifier);
        } on MissingPluginException {
          // The native expiration handler also releases its execution time.
        } on PlatformException {
          // The native task may already have expired.
        }
      }
    }
  }
}
