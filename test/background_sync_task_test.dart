import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/background_sync_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.personaltodo/background_sync');
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'begin' ? 42 : null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('releases iOS execution time even when the upload fails', () async {
    await expectLater(
      BackgroundSyncTask.run(() async => throw StateError('offline')),
      throwsStateError,
    );
    expect(calls.map((call) => call.method), ['begin', 'end']);
    expect(calls.last.arguments, 42);
  });

  test('still attempts the queued upload when iOS declines execution time',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    var attempted = false;
    await BackgroundSyncTask.run(() async {
      attempted = true;
    });
    expect(attempted, isTrue);
    expect(calls.map((call) => call.method), ['begin']);
  });
}
