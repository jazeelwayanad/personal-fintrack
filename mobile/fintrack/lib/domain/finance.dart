import 'dart:math' as math;
import 'package:intl/intl.dart';

typedef Data = Map<String, dynamic>;
String text(Data d, String key, [String fallback = '']) =>
    d[key] is String ? d[key] as String : fallback;
int amount(Data d, String key, [int fallback = 0]) =>
    d[key] is num ? (d[key] as num).round() : fallback;

class Doc {
  final String id, kind;
  final Data data;
  final int revision;
  final bool deleted;
  const Doc(
    this.id,
    this.kind,
    this.data, {
    this.revision = 0,
    this.deleted = false,
  });
  factory Doc.fromJson(Data d) => Doc(
    d['id'],
    d['kind'],
    Map<String, dynamic>.from(d['data']),
    revision: d['revision'] ?? 0,
    deleted: d['deleted'] ?? false,
  );
  Data toJson() => {
    'id': id,
    'kind': kind,
    'data': data,
    'revision': revision,
    'deleted': deleted,
  };
  Doc copy({Data? data, int? revision, bool? deleted}) => Doc(
    id,
    kind,
    data ?? this.data,
    revision: revision ?? this.revision,
    deleted: deleted ?? this.deleted,
  );
}

const defaults = <String, dynamic>{
  'payday': 1,
  'savings': 0,
  'limitMode': 'warn',
  'notifications': true,
};
String iso(DateTime d) => d.toIso8601String().substring(0, 10);
String todayIndia() =>
    iso(DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)));
String day(int year, int month, int date) => iso(
  DateTime.utc(
    year,
    month,
    math.min(date, DateTime.utc(year, month + 1, 0).day),
  ),
);
Data cycle(String today, int payday) {
  final d = DateTime.parse(today),
      here = day(
        DateTime.parse(today).year,
        DateTime.parse(today).month,
        payday,
      );
  return today.compareTo(here) >= 0
      ? {'start': here, 'end': day(d.year, d.month + 1, payday)}
      : {'start': day(d.year, d.month - 1, payday), 'end': here};
}

String addDays(String date, int count) =>
    iso(DateTime.parse('${date}T00:00:00Z').add(Duration(days: count)));

class Occurrence {
  final Doc doc;
  final String state;
  final String? transactionId;
  const Occurrence(this.doc, this.state, this.transactionId);
  bool get paid => transactionId != null;
}

// Presentation only: the full occurrence list remains available to calculations.
List<Occurrence> nextPaymentPerPlan(List<Occurrence> items) {
  final pending = items
      .where(
        (o) => !o.paid && !['paid', 'received', 'skipped'].contains(o.state),
      )
      .toList();
  pending.sort((a, b) {
    final date = text(a.doc.data, 'date').compareTo(text(b.doc.data, 'date'));
    return date == 0 ? a.doc.id.compareTo(b.doc.id) : date;
  });
  final seen = <String>{};
  return pending.where((o) {
    final planId = text(o.doc.data, 'planId');
    return seen.add(planId.isEmpty ? o.doc.id : planId);
  }).toList();
}

List<Occurrence> occurrences(List<Doc> records, String today, String through) {
  final active = records.where((r) => !r.deleted).toList(),
      map = <String, Doc>{};
  for (final plan in active.where((r) => r.kind == 'plan')) {
    final p = plan.data, base = DateTime.tryParse(text(plan.data, 'startDate'));
    if (base == null) continue;
    final recurrence = text(p, 'recurrence'),
        recharge = text(p, 'planType') == 'recharge';
    final interval = recurrence == 'weekly' ? 7 : amount(p, 'intervalDays', 1);
    var anchor = text(p, 'startDate');
    if (recharge) {
      final paidDates =
          active
              .where(
                (r) =>
                    r.kind == 'transaction' &&
                    text(r.data, 'occurrenceId').startsWith('${plan.id}:'),
              )
              .map((r) => text(r.data, 'date'))
              .toList()
            ..sort();
      if (paidDates.isNotEmpty) anchor = addDays(paidDates.last, interval);
      final skipped = active
          .where(
            (r) =>
                r.kind == 'occurrence' &&
                text(r.data, 'planId') == plan.id &&
                text(r.data, 'status') == 'skipped',
          )
          .map((r) => text(r.data, 'date'))
          .toSet();
      while (skipped.contains(anchor)) {
        anchor = addDays(anchor, interval);
      }
    }
    for (var i = 0; i <= 36890; i++) {
      if (i > 0 && recurrence == 'once') break;
      final date = recurrence == 'custom' || recurrence == 'weekly'
          ? (recharge && i > 0
                ? addDays(
                    anchor.compareTo(today) < 0 ? today : anchor,
                    interval * i,
                  )
                : addDays(anchor, interval * i))
          : day(
              base.year + (recurrence == 'yearly' ? i : 0),
              base.month + (recurrence == 'monthly' ? i : 0),
              base.day,
            );
      if (date.compareTo(through) > 0 ||
          date.compareTo('2100-12-31') > 0 ||
          (text(p, 'endDate').isNotEmpty &&
              date.compareTo(text(p, 'endDate')) > 0) ||
          (text(p, 'pausedAt').isNotEmpty &&
              date.compareTo(text(p, 'pausedAt')) > 0)) {
        break;
      }
      final id = '${plan.id}:$date';
      map[id] = Doc(id, 'occurrence', {
        'planId': plan.id,
        'name': text(p, 'name'),
        'type': text(p, 'type'),
        'amount': amount(p, 'amount'),
        'categoryId': text(p, 'categoryId'),
        'date': date,
        'reminders': p['reminders'] != false,
        'status': 'pending',
      });
    }
  }
  for (final item in active.where(
    (r) =>
        r.kind == 'occurrence' && text(r.data, 'date').compareTo(through) <= 0,
  )) {
    final plan = active
        .where((p) => p.id == text(item.data, 'planId') && p.kind == 'plan')
        .firstOrNull;
    if (text(plan?.data ?? {}, 'planType') != 'recharge' ||
        text(item.data, 'status') == 'skipped' ||
        active.any(
          (t) =>
              t.kind == 'transaction' &&
              text(t.data, 'occurrenceId') == item.id,
        ) ||
        map.containsKey(item.id)) {
      map[item.id] = item;
    }
  }
  final payments = {
    for (final t in active.where(
      (r) => r.kind == 'transaction' && text(r.data, 'occurrenceId').isNotEmpty,
    ))
      text(t.data, 'occurrenceId'): t,
  };
  final result = map.values.map((item) {
    final t = payments[item.id], date = text(item.data, 'date');
    final state = t != null
        ? (text(item.data, 'type') == 'income' ? 'received' : 'paid')
        : text(item.data, 'status') == 'skipped'
        ? 'skipped'
        : date.compareTo(today) < 0
        ? 'overdue'
        : date == today
        ? 'due'
        : 'upcoming';
    return Occurrence(item, state, t?.id);
  }).toList();
  result.sort((a, b) {
    final c = text(a.doc.data, 'date').compareTo(text(b.doc.data, 'date'));
    return c == 0 ? a.doc.id.compareTo(b.doc.id) : c;
  });
  return result;
}

Data summary(List<Doc> records, String today) {
  final active = records.where((r) => !r.deleted).toList();
  final preferences =
      active.where((r) => r.kind == 'preferences').firstOrNull?.data ??
      defaults;
  final period = cycle(today, amount(preferences, 'payday', 1));
  final transactions = active
      .where(
        (r) =>
            r.kind == 'transaction' &&
            text(r.data, 'date').compareTo(today) <= 0,
      )
      .toList();
  final balance =
      transactions.fold(
        0,
        (v, r) =>
            v +
            amount(r.data, 'amount') *
                (text(r.data, 'type') == 'income' ? 1 : -1),
      ) +
      active
          .where(
            (r) =>
                r.kind == 'adjustment' &&
                text(r.data, 'date').compareTo(today) <= 0,
          )
          .fold(0, (v, r) => v + amount(r.data, 'amount'));
  final upcoming = occurrences(records, today, period['end']);
  final outstanding = upcoming
      .where(
        (o) =>
            !o.paid &&
            o.state != 'skipped' &&
            text(o.doc.data, 'type') == 'expense' &&
            text(o.doc.data, 'date').compareTo(period['end']) < 0,
      )
      .toList();
  final commitments = outstanding.fold(
    0,
    (v, o) => v + amount(o.doc.data, 'amount'),
  );
  final manual = active.where((r) => r.kind == 'budget').toList();
  final categoryIds = {
    ...manual.map((r) => text(r.data, 'categoryId')),
    ...active
        .where((r) => r.kind == 'plan' && text(r.data, 'type') == 'expense')
        .map((r) => text(r.data, 'categoryId')),
  };
  final budgets = categoryIds.map((categoryId) {
    final entry = manual
        .where((r) => text(r.data, 'categoryId') == categoryId)
        .firstOrNull;
    final planned = upcoming
        .where(
          (o) =>
              o.state != 'skipped' &&
              text(o.doc.data, 'type') == 'expense' &&
              text(o.doc.data, 'categoryId') == categoryId &&
              text(o.doc.data, 'date').compareTo(period['start']) >= 0 &&
              text(o.doc.data, 'date').compareTo(period['end']) < 0,
        )
        .fold(0, (v, o) => v + amount(o.doc.data, 'amount'));
    final spent = transactions
        .where(
          (t) =>
              text(t.data, 'type') == 'expense' &&
              text(t.data, 'categoryId') == categoryId &&
              text(t.data, 'date').compareTo(period['start']) >= 0 &&
              text(t.data, 'date').compareTo(period['end']) < 0,
        )
        .fold(0, (v, t) => v + amount(t.data, 'amount'));
    final outstandingAmount = outstanding
        .where((o) => text(o.doc.data, 'categoryId') == categoryId)
        .fold(0, (v, o) => v + amount(o.doc.data, 'amount'));
    final limit = math.max(amount(entry?.data ?? {}, 'amount'), planned),
        remaining = limit - spent;
    return <String, dynamic>{
      'id': 'budget:$categoryId',
      'categoryId': categoryId,
      'amount': limit,
      'manual': entry == null ? null : amount(entry.data, 'amount'),
      'source': entry == null ? 'plans' : 'manual',
      'planned': planned,
      'spent': spent,
      'remaining': remaining,
      'outstanding': outstandingAmount,
      'reserve': math.max(0, remaining - outstandingAmount),
    };
  }).toList();
  final reserved = budgets.fold(0, (v, b) => v + amount(b, 'reserve')),
      savings = amount(preferences, 'savings');
  final periodTransactions = transactions.where(
    (r) =>
        text(r.data, 'date').compareTo(period['start']) >= 0 &&
        text(r.data, 'date').compareTo(period['end']) < 0,
  );
  return {
    'period': period,
    'preferences': preferences,
    'balance': balance,
    'commitments': commitments,
    'savings': savings,
    'reservedBudgets': reserved,
    'budgets': budgets,
    'unallocated': balance - commitments - savings - reserved,
    'income': periodTransactions
        .where((t) => text(t.data, 'type') == 'income')
        .fold(0, (v, t) => v + amount(t.data, 'amount')),
    'expenses': periodTransactions
        .where((t) => text(t.data, 'type') == 'expense')
        .fold(0, (v, t) => v + amount(t.data, 'amount')),
  };
}

Data checkSpending(
  List<Doc> records,
  String today,
  int proposed,
  String categoryId,
) {
  final totals = summary(records, today),
      budget = (totals['budgets'] as List<Data>)
          .where((b) => b['categoryId'] == categoryId)
          .firstOrNull;
  final cash =
      amount(totals, 'unallocated') +
      (budget == null ? 0 : amount(budget, 'reserve'));
  final maximum = math.max(
    0,
    budget == null ? cash : math.min(amount(budget, 'reserve'), cash),
  );
  return {
    'maximum': maximum,
    'allowed': proposed > 0 && proposed <= maximum,
    'shortfall': math.max(0, proposed - maximum),
    'remaining': maximum - proposed,
    'balanceAfter': amount(totals, 'balance') - proposed,
    'budgetRemaining': budget?['remaining'],
  };
}

Data monthlyForecast(List<Doc> records, String today, String month) {
  final start = '$month-01',
      d = DateTime.parse(start),
      end = day(d.year, d.month + 1, 1);
  final items = occurrences(records, today, end)
      .where(
        (o) =>
            o.state != 'skipped' &&
            text(o.doc.data, 'date').compareTo(start) >= 0 &&
            text(o.doc.data, 'date').compareTo(end) < 0,
      )
      .toList();
  return {
    'start': start,
    'end': end,
    'items': items,
    'count': items.length,
    'expenses': items
        .where((o) => text(o.doc.data, 'type') == 'expense')
        .fold(0, (v, o) => v + amount(o.doc.data, 'amount')),
    'income': items
        .where((o) => text(o.doc.data, 'type') == 'income')
        .fold(0, (v, o) => v + amount(o.doc.data, 'amount')),
  };
}

List<Occurrence> reminders(List<Doc> records, String today) {
  if (records
          .where((r) => !r.deleted && r.kind == 'preferences')
          .firstOrNull
          ?.data['notifications'] ==
      false) {
    return [];
  }
  final later = iso(DateTime.parse(today).add(const Duration(days: 3)));
  return occurrences(records, today, later)
      .where(
        (o) =>
            !o.paid &&
            o.state != 'skipped' &&
            o.doc.data['reminders'] != false &&
            (text(o.doc.data, 'date').compareTo(today) <= 0 ||
                text(o.doc.data, 'date') == later),
      )
      .toList();
}

List<Doc> snapshotPast(List<Doc> records, String id, String today) =>
    occurrences(records, today, today)
        .where(
          (o) =>
              text(o.doc.data, 'planId') == id &&
              !records.any((r) => r.id == o.doc.id),
        )
        .map((o) => o.doc)
        .toList();
String rupees(int paise) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
).format(paise / 100);
