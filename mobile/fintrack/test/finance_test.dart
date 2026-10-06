import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/domain/finance.dart';

void main() {
  final cases =
      jsonDecode(File('../../fixtures/finance.json').readAsStringSync())
          as List;
  for (final scenario in cases) {
    test(scenario['name'], () {
      final records = (scenario['records'] as List)
          .map((r) => Doc.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      final totals = summary(records, scenario['today']);
      for (final entry in (scenario['expected'] as Map).entries) {
        expect(totals[entry.key], entry.value, reason: entry.key);
      }
      if (scenario['check'] != null) {
        final c = scenario['check'];
        final result = checkSpending(
          records,
          scenario['today'],
          c['amount'],
          c['categoryId'],
        );
        for (final key in ['maximum', 'allowed', 'shortfall']) {
          expect(result[key], c[key], reason: key);
        }
      }
      if (scenario['dates'] != null) {
        expect(
          occurrences(
            records,
            scenario['today'],
            scenario['through'],
          ).map((o) => o.doc.data['date']).toList(),
          scenario['dates'],
        );
      }
    });
  }
  test('payday clamps to short month', () {
    expect(cycle('2026-02-28', 31), {
      'start': '2026-02-28',
      'end': '2026-03-31',
    });
  });
}
