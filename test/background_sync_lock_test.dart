import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/local_todo_repository.dart';
import 'package:personaltodo/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a second engine cannot sync concurrently and recovers after release',
      () async {
    final directory = await Directory.systemTemp.createTemp('todo_sync_lock_');
    final first = LocalTodoRepository(
        databasePath: '${directory.path}/tasks.db', singleInstance: false);
    final second = LocalTodoRepository(
        databasePath: '${directory.path}/tasks.db', singleInstance: false);
    await first.init(refreshNativeWidget: false);
    await second.init(refreshNativeWidget: false);
    addTearDown(() async {
      await first.close();
      await second.close();
      await directory.delete(recursive: true);
    });
    final entered = Completer<void>();
    final finish = Completer<void>();
    final active = first.withSyncLock(() async {
      entered.complete();
      await finish.future;
      return 'first';
    });
    await entered.future;
    var secondRan = false;
    final overlap = await second.withSyncLock(() async {
      secondRan = true;
      return 'second';
    });
    expect(overlap, isNull);
    expect(secondRan, isFalse);
    finish.complete();
    expect(await active, 'first');
    expect(await second.withSyncLock(() async => 'next'), 'next');
  });

  test('closing a background connection leaves the foreground database usable',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('todo_sync_engine_');
    final first =
        LocalTodoRepository(databasePath: '${directory.path}/tasks.db');
    final background = LocalTodoRepository(
        databasePath: '${directory.path}/tasks.db', singleInstance: false);
    await first.init(refreshNativeWidget: false);
    await background.init(refreshNativeWidget: false);
    await background.upsertTask(TodoTask(title: 'From background'));
    await background.close();
    await first.reload(refreshNativeWidget: false);
    expect(first.tasks.single.title, 'From background');
    await first.upsertTask(TodoTask(title: 'Foreground still works'));
    expect(first.tasks, hasLength(2));
    await first.close();
    await directory.delete(recursive: true);
  });
}
