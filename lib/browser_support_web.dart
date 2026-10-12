import 'dart:js_interop';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:web/web.dart' as web;

void initializeBrowserStorage() {
  final base = Uri.parse(web.document.baseURI);
  databaseFactory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      indexedDbName: 'personaltodo',
      sqlite3WasmUri: base.resolve('sqlite3.wasm'),
      sharedWorkerUri: base.resolve('sqflite_sw.js'),
    ),
  );
}

/// A closed Safari tab releases its lock, including after an interrupted sync.
Future<T?> withBrowserSyncLock<T>(
    String databasePath, Future<T> Function() action) async {
  T? result;
  Future<JSAny?> run(web.Lock? lock) async {
    if (lock != null) result = await action();
    return null;
  }

  final callback = ((web.Lock? lock) => run(lock).toJS).toJS;
  await web.window.navigator.locks
      .request(
        'personaltodo-sync:$databasePath',
        web.LockOptions(ifAvailable: true),
        callback,
      )
      .toDart;
  return result;
}
