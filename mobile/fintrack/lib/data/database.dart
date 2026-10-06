import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../domain/finance.dart';

class LedgerDatabase extends GeneratedDatabase {
  LedgerDatabase(super.executor);
  static Future<LedgerDatabase> open(String userId) async {
    final directory = await getApplicationSupportDirectory();
    return LedgerDatabase(
      NativeDatabase.createInBackground(
        File(
          p.join(
            directory.path,
            'fintrack-${Uri.encodeComponent(userId)}.sqlite',
          ),
        ),
      ),
    );
  }

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE ledger_state (id INTEGER PRIMARY KEY CHECK (id = 1), value TEXT NOT NULL)',
      );
    },
  );
  Future<Data?> read() async {
    final row = await customSelect(
      'SELECT value FROM ledger_state WHERE id = 1',
    ).getSingleOrNull();
    return row == null ? null : jsonDecode(row.read<String>('value')) as Data;
  }

  Future<void> write(Data state) async {
    await customStatement(
      'INSERT INTO ledger_state (id,value) VALUES (1,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value',
      [jsonEncode(state)],
    );
  }
}
