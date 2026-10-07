import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/database.dart';
import 'package:fintrack/data/ledger.dart';
import 'package:fintrack/domain/finance.dart';

class SyncApi extends CloudApi {
  final remote = <String, Data>{};
  final downloading = Completer<void>();
  Completer<void>? holdDownload;
  bool offline = false;
  int revision = 0;

  SyncApi() {
    session = {'user': {'id': 'sync-test'}};
  }

  @override
  Future<Data> request(String path, {String method = 'GET', Data? body}) async {
    if (offline) throw ApiException(503, 'Server unavailable');
    if (method == 'POST') {
      final records = <Data>[];
      for (final c in body!['changes']) {
        final record = <String, dynamic>{...c, 'revision': ++revision};
        remote[record['id']] = record;
        records.add(record);
      }
      return {'accepted': true, 'records': records};
    }
    final hold = holdDownload;
    holdDownload = null;
    if (hold != null) {
      downloading.complete();
      await hold.future;
    }
    return {'records': remote.values.toList(), 'cursor': revision};
  }
}

void main() {
  late SyncApi api;
  late Ledger ledger;
  late LedgerDatabase database;
  setUp(() {
    api = SyncApi();
    database = LedgerDatabase(NativeDatabase.memory());
    ledger = Ledger(api)..database = database;
  });
  tearDown(() async {
    ledger.database = null;
    ledger.dispose();
    await database.close();
    api.client.close();
  });

  Doc preferences() => Doc('preferences', 'preferences', {
    ...defaults,
    'payday': 25,
  });

  test('first sync uploads default categories and payment methods', () async {
    await ledger.sync();
    expect(api.remote, isNotEmpty);
    expect(ledger.queue, isEmpty);
    expect(ledger.status, 'Synced');
  });

  test('edit saved during a download uploads before sync finishes', () async {
    final release = Completer<void>();
    api.holdDownload = release;
    final syncing = ledger.sync();
    await api.downloading.future;
    await ledger.save([preferences()]);
    release.complete();
    await syncing;
    expect(api.remote['preferences']!['data']['payday'], 25);
    expect(ledger.queue, isEmpty);
    expect(ledger.status, 'Synced');
    expect((await database.read())!['queue'], isEmpty);
  });

  test('server failure retains edits for the next sync', () async {
    api.offline = true;
    await ledger.save([preferences()], autoSync: false);
    await ledger.sync();
    expect(ledger.queue, hasLength(1));
    expect(ledger.status, 'Server unavailable');
    api.offline = false;
    await ledger.sync();
    expect(ledger.queue, isEmpty);
    expect(api.remote['preferences']!['data']['payday'], 25);
    expect(ledger.status, 'Synced');
  });
}
