import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../domain/finance.dart';
import 'api.dart';
import 'database.dart';

class Ledger extends ChangeNotifier {
  final CloudApi api;
  LedgerDatabase? database;
  List<Doc> records = [];
  List<Data> queue = [];
  int cursor = 0;
  String status = 'Ready';
  String? lastSync;
  bool loading = true;
  Future<void>? _syncing;
  Timer? _timer;
  Ledger(this.api);
  bool get signedIn => api.session != null;
  List<Doc> get active => records.where((r) => !r.deleted).toList();
  Future<void> initialize() async {
    await api.restore();
    if (signedIn) await open();
    loading = false;
    notifyListeners();
  }

  Future<void> open() async {
    _timer?.cancel();
    await database?.close();
    database = await LedgerDatabase.open(api.session!['user']['id']);
    final saved = await database!.read();
    records = (saved?['records'] as List? ?? [])
        .map((r) => Doc.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    queue = (saved?['queue'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    cursor = saved?['cursor'] ?? 0;
    lastSync = saved?['lastSync'];
    notifyListeners();
    unawaited(sync());
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(sync()),
    );
  }

  Future<void> login(
    String email,
    String password, {
    bool register = false,
    String name = '',
  }) async {
    await api.login(email, password, register: register, name: name);
    await open();
    notifyListeners();
  }

  Future<void> logout() async {
    _timer?.cancel();
    await _syncing;
    await api.logout();
    await database?.close();
    database = null;
    records = [];
    queue = [];
    cursor = 0;
    notifyListeners();
  }

  Future<void> persist() async {
    await database?.write({
      'records': records.map((r) => r.toJson()).toList(),
      'queue': queue,
      'cursor': cursor,
      'lastSync': lastSync,
    });
    notifyListeners();
  }

  Future<void> save(List<Doc> docs, {bool autoSync = true}) async {
    final changes = <Data>[];
    for (final d in docs) {
      final old = records.where((r) => r.id == d.id).firstOrNull;
      final updated = d.copy(revision: old?.revision ?? 0);
      records.removeWhere((r) => r.id == d.id);
      records.add(updated);
      changes.add({
        'id': d.id,
        'kind': d.kind,
        'data': d.data,
        'deleted': d.deleted,
        'baseRevision': old?.revision ?? 0,
      });
    }
    queue.add({'id': const Uuid().v4(), 'changes': changes});
    await persist();
    if (autoSync) unawaited(sync());
  }

  Future<void> sync() {
    if (!signedIn || database == null) return Future.value();
    return _syncing ??= _drainSync().whenComplete(() {
      _syncing = null;
      notifyListeners();
    });
  }

  Future<void> _drainSync() async {
    // Include edits saved during a download and newly seeded defaults in this
    // sync. Stop on errors so offline edits remain queued for a later retry.
    while (await _performSync()) {
      if (!signedIn || database == null || queue.isEmpty) break;
    }
  }

  Future<bool> _performSync() async {
    status = 'Syncing';
    notifyListeners();
    try {
      while (queue.isNotEmpty) {
        final first = queue.first;
        if (first.containsKey('conflict') || first.containsKey('error')) {
          status = 'Review sync conflict in Settings';
          return false;
        }
        Data result;
        try {
          result = await api.request(
            '/api/v1/sync',
            method: 'POST',
            body: {'id': first['id'], 'changes': first['changes']},
          );
        } on ApiException catch (e) {
          if (e.status == 400 || e.status == 409) {
            first['error'] = e.message;
            first['conflict'] = [];
            await persist();
          }
          rethrow;
        }
        if (result['accepted'] != true) {
          first['conflict'] = result['records'];
          await persist();
          status = 'Review sync conflict in Settings';
          return false;
        }
        queue.removeAt(0);
        for (final value in result['records']) {
          final remote = Doc.fromJson(Map<String, dynamic>.from(value));
          var later = false;
          for (final q in queue) {
            for (final c in q['changes']) {
              if (c['id'] == remote.id) {
                c['baseRevision'] = remote.revision;
                later = true;
              }
            }
          }
          final old = records.where((r) => r.id == remote.id).firstOrNull;
          records.removeWhere((r) => r.id == remote.id);
          records.add(
            later && old != null ? old.copy(revision: remote.revision) : remote,
          );
        }
        await persist();
      }
      final result = await api.request('/api/v1/sync?since=$cursor');
      final pendingIds = queue
          .expand((q) => (q['changes'] as List).map((c) => c['id']))
          .toSet();
      for (final value in result['records']) {
        final remote = Doc.fromJson(Map<String, dynamic>.from(value));
        if (!pendingIds.contains(remote.id)) {
          records.removeWhere((r) => r.id == remote.id);
          records.add(remote);
        }
      }
      cursor = result['cursor'];
      lastSync = DateTime.now().toIso8601String();
      status = 'Synced';
      await persist();
      if (records.isEmpty) {
        final docs = <Doc>[
          Doc(const Uuid().v4(), 'category', {
            'name': 'Salary',
            'type': 'income',
            'color': '#22c55e',
            'icon': '',
          }),
          for (final name in ['Food', 'Transport', 'Shopping', 'Bills'])
            Doc(const Uuid().v4(), 'category', {
              'name': name,
              'type': 'expense',
              'color': '#74aa89',
              'icon': '',
            }),
          for (final name in ['Cash', 'Bank account', 'Card'])
            Doc(const Uuid().v4(), 'paymentMethod', {'name': name, 'icon': ''}),
        ];
        await save(docs, autoSync: false);
        status = 'Initial categories ready';
      }
      return true;
    } catch (e) {
      status = e is ApiException
          ? e.message
          : 'Offline or server unavailable · saved on this device';
      return false;
    }
  }

  Future<void> resolve(Data pending, bool keepLocal) async {
    final remote = {for (final r in pending['conflict'] ?? []) r['id']: r};
    if (keepLocal) {
      pending['id'] = const Uuid().v4();
      for (final c in pending['changes']) {
        c['baseRevision'] = remote[c['id']]?['revision'] ?? 0;
      }
      pending.remove('conflict');
      pending.remove('error');
    } else {
      final ids = (pending['changes'] as List).map((c) => c['id']).toSet();
      final start = queue.indexOf(pending);
      final discard = <Data>[];
      for (final q in queue.skip(start)) {
        if ((q['changes'] as List).any((c) => ids.contains(c['id']))) {
          ids.addAll((q['changes'] as List).map((c) => c['id']));
          discard.add(q);
        }
      }
      queue.removeWhere(discard.contains);
      records.removeWhere((r) => ids.contains(r.id));
    }
    cursor = 0;
    await persist();
    await sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    database?.close();
    super.dispose();
  }
}
