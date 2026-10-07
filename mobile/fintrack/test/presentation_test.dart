import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/domain/finance.dart';

void main() {
  Occurrence item(
    String id,
    String plan,
    String date,
    String state, [
    String? transaction,
  ]) => Occurrence(
    Doc(id, 'occurrence', {'planId': plan, 'date': date}),
    state,
    transaction,
  );

  test('schedule keeps oldest unpaid per plan and advances after payment', () {
    final overdue = item('a-old', 'a', '2026-09-01', 'overdue');
    final upcoming = item('a-next', 'a', '2026-11-01', 'upcoming');
    final today = item('b', 'b', '2026-10-07', 'due');
    final paid = item('c', 'c', '2026-09-01', 'paid', 'transaction');
    final skipped = item('d', 'd', '2026-09-01', 'skipped');
    final all = [upcoming, today, paid, skipped, overdue];
    expect(nextPaymentPerPlan(all), [overdue, today]);
    expect(all.length, 5);
    expect(nextPaymentPerPlan([upcoming, today, paid, skipped]), [
      today,
      upcoming,
    ]);
  });
}
