import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class SettingsStore {
  static const databaseName = 'personal_todo_settings.db';

  SettingsStore({String? databasePath}) : _databasePath = databasePath;

  final String? _databasePath;
  late final Database _database;

  Future<void> init() async {
    final databasePath =
        _databasePath ?? path.join(await getDatabasesPath(), databaseName);

    _database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> close() async {
    await _database.close();
  }

  Future<bool> containsKey(String key) async {
    return await getString(key) != null;
  }

  Future<bool?> getBool(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    return value == 'true';
  }

  Future<int?> getInt(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    return int.tryParse(value);
  }

  Future<String?> getString(String key) async {
    final rows = await _database.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.single['value'] as String;
  }

  Future<void> setBool(String key, bool value) async {
    await _setValue(key, value.toString());
  }

  Future<void> setInt(String key, int value) async {
    await _setValue(key, value.toString());
  }

  Future<void> setString(String key, String value) async {
    await _setValue(key, value);
  }

  Future<void> _setValue(String key, String value) async {
    await _database.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
