import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../data/ledger.dart';
import '../data/notifications.dart';
import '../domain/finance.dart';
import 'editor.dart';

class FinScreen extends ConsumerStatefulWidget {
  final String screen;
  final String? occurrenceId;
  const FinScreen({super.key, required this.screen, this.occurrenceId});
  @override
  ConsumerState<FinScreen> createState() => _FinScreenState();
}

class _FinScreenState extends ConsumerState<FinScreen>
    with WidgetsBindingObserver {
  String month = todayIndia().substring(0, 7),
      filter = 'all',
      planFilter = 'all',
      checkCategory = '';
  final checkController = TextEditingController();
  PushNotifications? notifications;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(ledgerProvider).sync());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    checkController.dispose();
    notifications?.dispose();
    super.dispose();
  }

  void notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      notice(e.toString());
    }
  }

  Widget panel(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  Widget metric(String label, int value, {bool hero = false}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: hero
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: hero ? Colors.white70 : null)),
        const SizedBox(height: 8),
        Text(
          rupees(value),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: hero ? Colors.white : null,
          ),
        ),
      ],
    ),
  );
  Future<void> remove(Ledger ledger, Doc record) async {
    if (await confirm(context, 'Delete this item?')) {
      await ledger.save([record.copy(deleted: true)]);
    }
  }

  Future<void> pay(Ledger ledger, Occurrence o) => editRecord(
    context,
    ledger,
    'transaction',
    occurrenceId: o.doc.id,
    initial: Doc('payment:${o.doc.id}', 'transaction', {
      'type': text(o.doc.data, 'type'),
      'amount': amount(o.doc.data, 'amount'),
      'categoryId': text(o.doc.data, 'categoryId'),
      'paymentMethodId':
          ledger.active
              .where((r) => r.kind == 'paymentMethod')
              .firstOrNull
              ?.id ??
          '',
      'description': text(o.doc.data, 'name'),
      'date': todayIndia(),
    }),
  );
  Future<void> link(Ledger ledger, Occurrence o) async {
    final available = ledger.active
        .where(
          (r) =>
              r.kind == 'transaction' &&
              text(r.data, 'occurrenceId').isEmpty &&
              text(r.data, 'type') == text(o.doc.data, 'type'),
        )
        .toList();
    final selected = await showDialog<Doc>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Link existing transaction'),
        children: available.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No matching unlinked transactions.'),
                ),
              ]
            : available
                  .map(
                    (r) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(c, r),
                      child: Text(
                        '${text(r.data, 'date')} · ${text(r.data, 'description')} · ${rupees(amount(r.data, 'amount'))}',
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
    if (selected != null) {
      await ledger.save([
        o.doc,
        selected.copy(data: {...selected.data, 'occurrenceId': o.doc.id}),
      ]);
    }
  }

  Widget payments(Ledger ledger, List<Occurrence> items) => Column(
    children: [
      if (items.isEmpty) const Text('No payments to show.'),
      for (final o in items)
        Container(
          decoration: BoxDecoration(
            color: o.doc.id == widget.occurrenceId
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: .15),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text(o.doc.data, 'name'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${text(o.doc.data, 'date')} · ${o.state}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    rupees(amount(o.doc.data, 'amount')),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (!o.paid && o.state != 'skipped')
                Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => pay(ledger, o),
                      child: Text(
                        text(o.doc.data, 'type') == 'income'
                            ? 'Received'
                            : 'Mark paid',
                      ),
                    ),
                    TextButton(
                      onPressed: () => act(() => link(ledger, o)),
                      child: const Text('Link'),
                    ),
                    TextButton(
                      onPressed: () => act(() async {
                        if (await confirm(
                          context,
                          'Skip this payment and release its reserved money?',
                        )) {
                          await ledger.save([
                            o.doc.copy(
                              data: {...o.doc.data, 'status': 'skipped'},
                            ),
                          ]);
                        }
                      }),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              if (o.state == 'skipped')
                TextButton(
                  onPressed: () => act(
                    () => ledger.save([
                      o.doc.copy(data: {...o.doc.data, 'status': 'pending'}),
                    ]),
                  ),
                  child: const Text('Restore'),
                ),
            ],
          ),
        ),
    ],
  );
  List<Widget> budgetRows(Ledger ledger, Data totals, {bool edit = false}) => [
    if ((totals['budgets'] as List).isEmpty)
      const Text('Set category budgets in Plans to reserve everyday spending.'),
    for (final b in totals['budgets'])
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ledger.active
                            .where((r) => r.id == b['categoryId'])
                            .firstOrNull
                            ?.data['name'] ??
                        'Category',
                  ),
                ),
                Text('${rupees(b['spent'])} / ${rupees(b['amount'])}'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: b['amount'] > 0
                  ? (b['spent'] / b['amount']).clamp(0.0, 1.0)
                  : 0,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              color: b['spent'] > b['amount'] ? Colors.red : null,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${rupees(b['remaining'])} remaining',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (edit)
                  TextButton(
                    onPressed: () => editRecord(
                      context,
                      ledger,
                      'budget',
                      initial: ledger.active.firstWhere((r) => r.id == b['id']),
                    ),
                    child: const Text('Edit'),
                  ),
              ],
            ),
          ],
        ),
      ),
  ];
  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    if (ledger.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!ledger.signedIn) return LoginScreen(ledger: ledger);
    notifications ??= PushNotifications(ledger.api, (route) {
      if (mounted) context.go(route.startsWith('/plans') ? route : '/plans');
    })..initialize().catchError((_) {});
    final today = todayIndia(),
        totals = summary(ledger.records, today),
        active = ledger.active;
    final labels = {for (final r in active) r.id: text(r.data, 'name')};
    final through = '${int.parse(today.substring(0, 4)) + 1}-12-31';
    final all = occurrences(ledger.records, today, through);
    final titles = ['Home', 'Plans', 'Transactions', 'Reports', 'Settings'],
        routes = ['/', '/plans', '/transactions', '/reports', '/settings'];
    final index = [
      'home',
      'plans',
      'transactions',
      'reports',
      'settings',
    ].indexOf(widget.screen);
    final sections = <Widget>[];
    if (widget.screen == 'home') {
      sections.addAll([
        metric('Unallocated money', amount(totals, 'unallocated'), hero: true),
        metric('Current balance', amount(totals, 'balance')),
        panel('Money reserved', [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Unpaid bills'),
            trailing: Text(rupees(amount(totals, 'commitments'))),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Category budgets'),
            trailing: Text(rupees(amount(totals, 'reservedBudgets'))),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Protected savings'),
            trailing: Text(rupees(amount(totals, 'savings'))),
          ),
        ]),
      ]);
      if (amount(totals, 'unallocated') < 0) {
        sections.add(
          Text(
            'Your commitments exceed available money by ${rupees(-amount(totals, 'unallocated'))}. Review your plans and budgets.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
      }
      final check = checkSpending(
        ledger.records,
        today,
        ((double.tryParse(checkController.text) ?? 0) * 100).round(),
        checkCategory,
      );
      sections.add(
        panel('Can I spend this?', [
          TextField(
            controller: checkController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: active.any((r) => r.id == checkCategory)
                ? checkCategory
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: active
                .where(
                  (r) =>
                      r.kind == 'category' && text(r.data, 'type') == 'expense',
                )
                .map(
                  (r) => DropdownMenuItem(
                    value: r.id,
                    child: Text(text(r.data, 'name')),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => checkCategory = v ?? ''),
          ),
          const SizedBox(height: 14),
          Text('Available: ${rupees(amount(check, 'maximum'))}'),
          if (checkController.text.isNotEmpty && checkCategory.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              check['allowed'] == true
                  ? 'Within your spending limit'
                  : 'Over the limit by ${rupees(amount(check, 'shortfall'))}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: check['allowed'] == true
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            Text(
              'Balance after: ${rupees(amount(check, 'balanceAfter'))}\nAllowance remaining: ${rupees(amount(check, 'remaining'))}',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  check['allowed'] != true &&
                      totals['preferences']['limitMode'] == 'block'
                  ? null
                  : () => editRecord(
                      context,
                      ledger,
                      'transaction',
                      initial: Doc(const Uuid().v4(), 'transaction', {
                        'type': 'expense',
                        'amount':
                            ((double.tryParse(checkController.text) ?? 0) * 100)
                                .round(),
                        'categoryId': checkCategory,
                        'paymentMethodId':
                            active
                                .where((r) => r.kind == 'paymentMethod')
                                .firstOrNull
                                ?.id ??
                            '',
                        'date': today,
                        'description': '',
                      }),
                    ),
              child: const Text('Record expense'),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Protects bills, savings, and other category reserves. Expected income is excluded. ${ledger.status == 'Synced' ? '' : 'Using this device’s saved data.'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      );
      sections.add(panel('Category budgets', budgetRows(ledger, totals)));
      sections.add(
        panel('Upcoming and overdue', [
          payments(
            ledger,
            occurrences(
              ledger.records,
              today,
              totals['period']['end'],
            ).where((o) => !o.paid && o.state != 'skipped').toList(),
          ),
        ]),
      );
    }
    if (widget.screen == 'plans') {
      sections.add(
        panel('Scheduled income and expenses', [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  ['all', 'salary', 'income', 'emi', 'subscription', 'expense']
                      .map(
                        (v) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(v == 'emi' ? 'EMIs' : v),
                            selected: planFilter == v,
                            onSelected: (_) => setState(() => planFilter = v),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          for (final p in active.where(
            (r) =>
                r.kind == 'plan' &&
                (planFilter == 'all' || text(r.data, 'planType') == planFilter),
          ))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(p.data, 'name')),
              subtitle: Text(
                '${text(p.data, 'recurrence')} · ${text(p.data, 'startDate')}\n${rupees(amount(p.data, 'amount'))}${text(p.data, 'pausedAt').isNotEmpty ? ' · Paused' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => act(() async {
                  if (v == 'edit') {
                    await editRecord(context, ledger, 'plan', initial: p);
                  } else {
                    await ledger.save([
                      ...snapshotPast(ledger.records, p.id, today),
                      p.copy(
                        data: {
                          ...p.data,
                          'pausedAt': text(p.data, 'pausedAt').isEmpty
                              ? today
                              : null,
                        },
                      ),
                    ]);
                  }
                }),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'pause',
                    child: Text(
                      text(p.data, 'pausedAt').isEmpty ? 'Pause' : 'Resume',
                    ),
                  ),
                ],
              ),
            ),
        ]),
      );
      sections.add(
        panel('Category budgets', [
          ...budgetRows(ledger, totals, edit: true),
          FilledButton.tonal(
            onPressed: () => editRecord(context, ledger, 'budget'),
            child: const Text('Set category budget'),
          ),
        ]),
      );
      sections.add(panel('Payment schedule', [payments(ledger, all)]));
    }
    if (widget.screen == 'transactions') {
      sections.add(
        panel('Your ledger', [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: month,
                  decoration: const InputDecoration(
                    labelText: 'Month (YYYY-MM)',
                  ),
                  onChanged: (v) => setState(() => month = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: filter,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: ['all', 'income', 'expense']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => filter = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final t
              in (active
                  .where(
                    (r) =>
                        r.kind == 'transaction' &&
                        text(r.data, 'date').startsWith(month) &&
                        (filter == 'all' || text(r.data, 'type') == filter),
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      text(b.data, 'date').compareTo(text(a.data, 'date')),
                )))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                text(t.data, 'description').isEmpty
                    ? labels[text(t.data, 'categoryId')] ?? 'Transaction'
                    : text(t.data, 'description'),
              ),
              subtitle: Text(
                '${text(t.data, 'date')} · ${labels[text(t.data, 'categoryId')]}\n${labels[text(t.data, 'paymentMethodId')]}${text(t.data, 'occurrenceId').isEmpty ? '' : ' · Planned payment'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${text(t.data, 'type') == 'income' ? '+' : '−'}${rupees(amount(t.data, 'amount'))}',
                    style: TextStyle(
                      color: text(t.data, 'type') == 'income'
                          ? Colors.green
                          : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => act(
                      () => v == 'edit'
                          ? editRecord(
                              context,
                              ledger,
                              'transaction',
                              initial: t,
                            )
                          : remove(ledger, t),
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      );
    }
    if (widget.screen == 'reports') {
      sections.addAll([
        metric('Income this cycle', amount(totals, 'income')),
        metric('Expenses this cycle', amount(totals, 'expenses')),
        metric(
          'Net this cycle',
          amount(totals, 'income') - amount(totals, 'expenses'),
        ),
        panel('Budget versus actual', budgetRows(ledger, totals)),
        panel('Expenses by category', [
          for (final c in active.where(
            (r) => r.kind == 'category' && text(r.data, 'type') == 'expense',
          ))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(c.data, 'name')),
              trailing: Text(
                rupees(
                  active
                      .where(
                        (t) =>
                            t.kind == 'transaction' &&
                            text(t.data, 'type') == 'expense' &&
                            text(t.data, 'categoryId') == c.id &&
                            text(
                                  t.data,
                                  'date',
                                ).compareTo(totals['period']['start']) >=
                                0 &&
                            text(
                                  t.data,
                                  'date',
                                ).compareTo(totals['period']['end']) <
                                0 &&
                            text(t.data, 'date').compareTo(today) <= 0,
                      )
                      .fold(0, (v, t) => v + amount(t.data, 'amount')),
                ),
              ),
            ),
        ]),
        panel('Planned versus paid', [
          payments(
            ledger,
            all
                .where(
                  (o) =>
                      text(
                            o.doc.data,
                            'date',
                          ).compareTo(totals['period']['start']) >=
                          0 &&
                      text(
                            o.doc.data,
                            'date',
                          ).compareTo(totals['period']['end']) <
                          0,
                )
                .toList(),
          ),
        ]),
      ]);
    }
    if (widget.screen == 'settings') {
      sections.add(
        panel('Financial preferences', [
          Text(
            'Payday: ${totals['preferences']['payday']}\nProtected savings: ${rupees(amount(totals, 'savings'))}\nOver-limit behavior: ${totals['preferences']['limitMode']}',
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => editRecord(
              context,
              ledger,
              'preferences',
              initial: Doc('preferences', 'preferences', {
                ...defaults,
                ...totals['preferences'],
              }),
            ),
            child: const Text('Edit preferences'),
          ),
          TextButton(
            onPressed: () => editRecord(context, ledger, 'adjustment'),
            child: const Text('Add opening-balance adjustment'),
          ),
          for (final a in active.where((r) => r.kind == 'adjustment'))
            ListTile(
              title: Text(rupees(amount(a.data, 'amount'))),
              subtitle: Text(text(a.data, 'date')),
              trailing: IconButton(
                onPressed: () => act(() => remove(ledger, a)),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ]),
      );
      sections.add(
        panel('Notifications and appearance', [
          const Text(
            'One morning summary for upcoming, due, and overdue payments. Cloud reminders use synced data.',
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => act(() async {
              await notifications!.enable();
              notice('Notifications enabled');
            }),
            child: const Text('Enable notifications'),
          ),
          TextButton(
            onPressed: () => act(() async {
              await ledger.api.request('/api/v1/devices/test', method: 'POST');
              notice('Test notification sent');
            }),
            child: const Text('Send test'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            initialValue: ref.watch(themeProvider),
            decoration: const InputDecoration(labelText: 'Theme'),
            items: ThemeMode.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                .toList(),
            onChanged: (v) => ref.read(themeProvider.notifier).state = v!,
          ),
        ]),
      );
      for (final kind in ['category', 'paymentMethod']) {
        sections.add(
          panel(kind == 'category' ? 'Categories' : 'Payment methods', [
            for (final r in active.where((r) => r.kind == kind))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(text(r.data, 'name')),
                subtitle: kind == 'category'
                    ? Text(text(r.data, 'type'))
                    : null,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => act(
                    () => v == 'edit'
                        ? editRecord(context, ledger, kind, initial: r)
                        : remove(ledger, r),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            TextButton(
              onPressed: () => editRecord(context, ledger, kind),
              child: Text(
                kind == 'category' ? 'Add category' : 'Add payment method',
              ),
            ),
          ]),
        );
      }
      sections.add(
        panel('Sync and account', [
          Text(
            '${ledger.status}\n${ledger.queue.length} pending changes\nLast synced: ${ledger.lastSync ?? 'Never'}',
          ),
          for (final q in ledger.queue.where(
            (q) => q.containsKey('conflict') || q.containsKey('error'),
          ))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                Text(q['error'] ?? 'Another device changed these records.'),
                ExpansionTile(
                  title: const Text('Compare changes'),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert({
                        'local': q['changes'],
                        'server': q['conflict'],
                      }),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => act(() => ledger.resolve(q, true)),
                      child: const Text('Keep local and retry'),
                    ),
                    TextButton(
                      onPressed: () => act(() async {
                        if (await confirm(
                          context,
                          'Discard these changes and dependent edits, and reload server data?',
                        )) {
                          await ledger.resolve(q, false);
                        }
                      }),
                      child: const Text('Use server'),
                    ),
                  ],
                ),
              ],
            ),
          TextButton(
            onPressed: () => ledger.sync(),
            child: const Text('Sync now'),
          ),
          TextButton(
            onPressed: () => act(() async {
              if (ledger.queue.isNotEmpty &&
                  !await confirm(
                    context,
                    'Unsynced changes will remain on this device. Sign out?',
                  )) {
                return;
              }
              await notifications?.logout();
              await ledger.logout();
            }),
            child: const Text('Sign out'),
          ),
        ]),
      );
      sections.add(
        panel('Reminder inbox', [
          payments(ledger, reminders(ledger.records, today)),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FinTrack',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => ledger.sync(),
            icon: const Icon(Icons.sync),
            tooltip: 'Sync now',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ledger.sync,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Text(
              titles[index < 0 ? 0 : index],
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Cycle ${totals['period']['start']} → ${totals['period']['end']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${ledger.status}${ledger.queue.isEmpty ? '' : ' · ${ledger.queue.length} pending'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            ...sections.expand((w) => [w, const SizedBox(height: 16)]),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editRecord(
          context,
          ledger,
          widget.screen == 'plans' ? 'plan' : 'transaction',
        ),
        icon: const Icon(Icons.add),
        label: Text(widget.screen == 'plans' ? 'Add plan' : 'Add transaction'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(routes[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            label: 'Plans',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz),
            label: 'Transactions',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final Ledger ledger;
  const LoginScreen({super.key, required this.ledger});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>(),
      email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 58,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'FinTrack',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Plan your bills. Know what you can spend.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (register) ...[
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      v == null || !v.contains('@') ? 'Enter your email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: password,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => obscure = !obscure),
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v?.length ?? 0) < 8 ? 'Use at least 8 characters' : null,
                ),
                const SizedBox(height: 20),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await widget.ledger.login(
                              email.text.trim(),
                              password.text,
                              register: register,
                              name: name.text.trim(),
                            );
                          } catch (e) {
                            if (mounted) setState(() => error = e.toString());
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: Text(
                    busy
                        ? 'Connecting…'
                        : register
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => register = !register),
                  child: Text(
                    register
                        ? 'Already have an account? Sign in'
                        : 'Create an account',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign in once online. Your saved ledger remains available offline.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
