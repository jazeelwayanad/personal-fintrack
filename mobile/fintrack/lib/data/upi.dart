import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'api.dart';
import '../domain/finance.dart';

const _attempts = '/api/v1/upi/attempts';
const _ids = Uuid();

String _outcomeKey(CloudApi api) =>
    'fintrack-upi-outcome:${Uri.encodeComponent(api.baseUrl)}:${api.session!['user']['id']}';

Future<void> retryUpiOutcome(CloudApi api) async {
  final key = _outcomeKey(api);
  final saved = await api.storage.read(key: key);
  if (saved == null) return;
  final pending = Map<String, dynamic>.from(jsonDecode(saved) as Map);
  final path = '$_attempts/${pending['attemptId']}';
  final attempt = await api.request(path);
  // Only a claimed attempt can receive an app result. The account may have
  // already recorded it on another device while this device was offline.
  if (attempt['status'] == 'awaiting_confirmation') {
    try {
      await api.request(
        '$path/outcome',
        method: 'POST',
        body: {
          'idempotencyKey': pending['idempotencyKey'],
          'result': pending['result'],
        },
      );
    } on ApiException catch (error) {
      if (error.status != 409) rethrow;
      final current = await api.request(path);
      if (current['status'] == 'awaiting_confirmation') rethrow;
    }
  }
  if (await api.storage.read(key: key) == saved) {
    await api.storage.delete(key: key);
  }
}

Future<String> handoffUpi(
  CloudApi api,
  String attemptId,
  String payload,
  Future<String?> Function(String payload) open,
) async {
  await retryUpiOutcome(api);
  final storageKey = _outcomeKey(api);
  Future<void> retain(String result) => api.storage.write(
    key: storageKey,
    value: jsonEncode({
      'attemptId': attemptId,
      'idempotencyKey': _ids.v4(),
      'result': result,
    }),
  );
  // Persist uncertainty before handing control to another app. If Android kills
  // this process, history can recover the result without opening payment again.
  await retain('unknown');
  final claim = await api.request(
    '$_attempts/$attemptId/outcome',
    method: 'POST',
    body: {'idempotencyKey': _ids.v4(), 'result': 'claim'},
  );
  if (claim['launchAllowed'] != true) {
    await retryUpiOutcome(api);
    return 'unknown';
  }
  final result = await open(payload) ?? 'unknown';
  await retain(result);
  await retryUpiOutcome(api);
  return result;
}

Future<Data> recordUpiExpense(CloudApi api, String attemptId, Data input) {
  final request = <String, dynamic>{
    'expectedRevision': input['expectedRevision'],
    'paymentMethodId': input['paymentMethodId'],
    if (input['existingExpenseId'] != null)
      'existingExpenseId': input['existingExpenseId'],
    if (input['postingDate'] != null) 'postingDate': input['postingDate'],
  };
  // A retry of the same record survives navigation and process restarts.
  final idempotencyKey = _ids.v5(
    Namespace.url.value,
    jsonEncode([api.baseUrl, api.session!['user']['id'], attemptId, request]),
  );
  return api.request(
    '$_attempts/$attemptId/record',
    method: 'POST',
    body: {'idempotencyKey': idempotencyKey, ...request},
  );
}
