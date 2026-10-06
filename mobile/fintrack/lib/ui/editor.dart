import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/ledger.dart';
import '../domain/finance.dart';

Future<void> editRecord(
  BuildContext context,
  Ledger ledger,
  String kind, {
  Doc? initial,
  String? occurrenceId,
}) => showDialog<void>(
  context: context,
  builder: (_) => RecordEditor(
    ledger: ledger,
    kind: kind,
    initial: initial,
    occurrenceId: occurrenceId,
  ),
);
Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Please confirm'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class RecordEditor extends StatefulWidget {
  final Ledger ledger;
  final String kind;
  final Doc? initial;
  final String? occurrenceId;
  const RecordEditor({
    super.key,
    required this.ledger,
    required this.kind,
    this.initial,
    this.occurrenceId,
  });
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final form = GlobalKey<FormState>();
  late Data data = Map.of(
    widget.initial?.data ??
        (widget.kind == 'preferences'
            ? defaults
            : {
                'type': widget.kind == 'plan' ? 'income' : 'expense',
                'planType': 'salary',
                'recurrence': 'monthly',
                'date': todayIndia(),
                'startDate': todayIndia(),
                'reminders': true,
                'color': '#8b5cf6',
                'amount': 0,
                'description': '',
                'icon': '',
              }),
  );
  bool alreadySpent = false, busy = false;
  String? error;
  Widget field(
    String key,
    String label, {
    bool required = true,
    bool money = false,
    bool integer = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey(key),
      initialValue: money
          ? (amount(data, key) == 0
                ? ''
                : (amount(data, key) / 100).toStringAsFixed(2))
          : integer
          ? amount(data, key, 1).toString()
          : text(data, key),
      decoration: InputDecoration(labelText: label),
      keyboardType: money || integer
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) return 'Required';
        if (money || integer) {
          final n = double.tryParse(v ?? '');
          if (n == null || !n.isFinite) return 'Enter a valid amount';
          if (key == 'payday' && (n < 1 || n > 31 || n % 1 != 0)) {
            return 'Use a day from 1 to 31';
          }
          if (money && widget.kind != 'adjustment' && n < 0) {
            return 'Cannot be negative';
          }
          if (money &&
              ['transaction', 'plan'].contains(widget.kind) &&
              n <= 0) {
            return 'Must be greater than zero';
          }
          if (money && n.abs() > 10000000000) return 'Amount is too large';
        }
        return null;
      },
      onChanged: (v) {
        data[key] = money
            ? ((double.tryParse(v) ?? 0) * 100).round()
            : integer
            ? int.tryParse(v) ?? 0
            : v;
        if (money) setState(() {});
      },
    ),
  );
  Widget select(String key, String label, List<(String, String)> options) {
    final value = text(data, key);
    final selected = options.any((o) => o.$1 == value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$key-${text(data, 'type')}'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: options
            .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
            .toList(),
        validator: (v) => v == null ? 'Choose an option' : null,
        onChanged: (v) => setState(() {
          data[key] = v;
          if (key == 'type') {
            data['categoryId'] = null;
            data['planType'] = v == 'income' ? 'income' : 'expense';
          }
        }),
      ),
    );
  }

  Widget date(String key, String label, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    DateTime.tryParse(text(data, key)) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100, 12, 31),
              );
              if (picked != null) setState(() => data[key] = iso(picked));
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                suffixIcon: const Icon(Icons.calendar_today_outlined),
              ),
              child: Text(text(data, key, 'Choose date')),
            ),
          ),
        ),
        if (optional)
          IconButton(
            onPressed: () => setState(() => data[key] = null),
            icon: const Icon(Icons.clear),
          ),
      ],
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final kind = widget.kind, ledger = widget.ledger;
      if (['transaction', 'adjustment'].contains(kind) &&
          text(data, 'date').compareTo(todayIndia()) > 0) {
        throw Exception('Use a plan for future income or expenses.');
      }
      if (kind == 'plan' &&
          text(data, 'endDate').isNotEmpty &&
          text(data, 'endDate').compareTo(text(data, 'startDate')) < 0) {
        throw Exception('Final date must follow the first due date.');
      }
      if (kind == 'transaction' &&
          text(data, 'type') == 'expense' &&
          widget.occurrenceId == null &&
          text(data, 'occurrenceId').isEmpty &&
          !alreadySpent) {
        final check = checkSpending(
          ledger.records.where((r) => r.id != widget.initial?.id).toList(),
          todayIndia(),
          amount(data, 'amount'),
          text(data, 'categoryId'),
        );
        if (check['allowed'] != true) {
          if ((summary(ledger.records, todayIndia())['preferences']
                  as Data)['limitMode'] ==
              'block') {
            throw Exception(
              'Above your spending limit. Adjust the budget or choose Already spent.',
            );
          }
          if (!await confirm(
            context,
            'This exceeds your allowance by ${rupees(amount(check, 'shortfall'))}. Record anyway?',
          )) {
            return;
          }
        }
      }
      final id = kind == 'preferences'
          ? 'preferences'
          : kind == 'budget'
          ? 'budget:${text(data, 'categoryId')}'
          : widget.initial?.id ?? const Uuid().v4();
      final docs = kind == 'plan' && widget.initial != null
          ? snapshotPast(ledger.records, id, todayIndia())
          : <Doc>[];
      docs.add(Doc(id, kind, Map.of(data)));
      if (kind == 'plan' && text(data, 'planType') == 'salary') {
        final pref = ledger.active
            .where((r) => r.kind == 'preferences')
            .firstOrNull;
        docs.add(
          Doc('preferences', 'preferences', {
            ...defaults,
            ...?pref?.data,
            'payday': int.parse(text(data, 'startDate').substring(8)),
          }),
        );
      }
      if (widget.occurrenceId != null) {
        final o = occurrences(
          ledger.records,
          todayIndia(),
          '2100-12-31',
        ).firstWhere((o) => o.doc.id == widget.occurrenceId);
        docs[0] = Doc(
          widget.initial?.id ?? 'payment:${o.doc.id}',
          'transaction',
          {...data, 'occurrenceId': o.doc.id},
        );
        docs.add(o.doc);
      }
      await ledger.save(docs);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind, records = widget.ledger.active;
    final isExisting =
        widget.initial != null &&
        records.any((r) => r.id == widget.initial!.id);
    final categories = records.where(
      (r) =>
          r.kind == 'category' &&
          text(r.data, 'type') ==
              (kind == 'budget' ? 'expense' : text(data, 'type')),
    );
    final methods = records.where((r) => r.kind == 'paymentMethod');
    final expense =
        kind == 'transaction' &&
        text(data, 'type') == 'expense' &&
        widget.occurrenceId == null &&
        text(data, 'occurrenceId').isEmpty;
    final check = checkSpending(
      widget.ledger.records.where((r) => r.id != widget.initial?.id).toList(),
      todayIndia(),
      amount(data, 'amount'),
      text(data, 'categoryId'),
    );
    return AlertDialog(
      title: Text(
        '${isExisting ? 'Edit' : 'Add'} ${kind == 'paymentMethod' ? 'payment method' : kind}',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (['category', 'paymentMethod', 'plan'].contains(kind))
                  field('name', 'Name'),
                if (['transaction', 'category', 'plan'].contains(kind))
                  select('type', 'Type', [
                    ('income', 'Income'),
                    ('expense', 'Expense'),
                  ]),
                if (kind == 'plan')
                  select(
                    'planType',
                    'Plan type',
                    (text(data, 'type') == 'income'
                            ? ['salary', 'income']
                            : ['emi', 'subscription', 'expense'])
                        .map((v) => (v, v == 'emi' ? 'EMI' : v))
                        .toList(),
                  ),
                if ([
                  'transaction',
                  'plan',
                  'budget',
                  'adjustment',
                ].contains(kind))
                  field('amount', 'Amount (₹)', money: true),
                if (['transaction', 'plan', 'budget'].contains(kind))
                  select(
                    'categoryId',
                    'Category',
                    categories
                        .map((r) => (r.id, text(r.data, 'name')))
                        .toList(),
                  ),
                if (kind == 'transaction')
                  select(
                    'paymentMethodId',
                    'Payment method',
                    methods.map((r) => (r.id, text(r.data, 'name'))).toList(),
                  ),
                if (['transaction', 'adjustment'].contains(kind))
                  date('date', 'Date'),
                if (['transaction', 'adjustment'].contains(kind))
                  field('description', 'Note', required: false),
                if (kind == 'plan') ...[
                  date('startDate', 'First due date / payday'),
                  date(
                    'endDate',
                    'Final payment date (optional)',
                    optional: true,
                  ),
                  select('recurrence', 'Repeat', [
                    ('once', 'One time'),
                    ('monthly', 'Monthly'),
                    ('yearly', 'Yearly'),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Payment reminders'),
                    value: data['reminders'] != false,
                    onChanged: (v) => setState(() => data['reminders'] = v),
                  ),
                ],
                if (kind == 'preferences') ...[
                  field('payday', 'Monthly payday (1–31)', integer: true),
                  field(
                    'savings',
                    'Protected savings / emergency money (₹)',
                    money: true,
                  ),
                  select('limitMode', 'Over-limit behavior', [
                    ('warn', 'Warn and allow confirmation'),
                    ('block', 'Block planned spending'),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Daily reminders'),
                    value: data['notifications'] != false,
                    onChanged: (v) => setState(() => data['notifications'] = v),
                  ),
                ],
                if (expense) ...[
                  Text('Available: ${rupees(amount(check, 'maximum'))}'),
                  if (amount(check, 'shortfall') > 0)
                    Text(
                      'Shortfall: ${rupees(amount(check, 'shortfall'))}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Already spent'),
                    subtitle: const Text(
                      'Record an actual expense even when over limit',
                    ),
                    value: alreadySpent,
                    onChanged: (v) => setState(() => alreadySpent = v ?? false),
                  ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
