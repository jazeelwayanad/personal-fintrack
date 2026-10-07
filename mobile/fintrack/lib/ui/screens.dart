import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Future<void> openDeveloperLink(String url) async {
    try {
      await const MethodChannel(
        'fintrack/external_links',
      ).invokeMethod('open', url);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No app could open this link. Contact info@eucodes.in.',
            ),
          ),
        );
      }
    }
  }

  Future<void> giveFeedback(Ledger ledger) async {
    final message = TextEditingController();
    final form = GlobalKey<FormState>();
    final id = const Uuid().v4();
    var topic = 'suggestion', error = '';
    var busy = false, sent = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('Give feedback'),
            content: SingleChildScrollView(
              child: sent
                  ? const Text('Thank you. Your feedback has been received.')
                  : Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Share an idea or report an issue with Eucodes. Your ledger is not attached.',
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: topic,
                            decoration: const InputDecoration(
                              labelText: 'Topic',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'suggestion',
                                child: Text('Suggestion'),
                              ),
                              DropdownMenuItem(
                                value: 'issue',
                                child: Text('Report an issue'),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) => update(() => topic = value!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: message,
                            enabled: !busy,
                            minLines: 4,
                            maxLines: 6,
                            maxLength: 3000,
                            decoration: const InputDecoration(
                              labelText: 'Your feedback',
                              hintText: 'What could we improve?',
                            ),
                            validator: (value) =>
                                (value ?? '').trim().length < 10
                                ? 'Please write at least 10 characters.'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Avoid passwords and sensitive financial details. Feedback is saved with your account and app version for developer review and email notification.',
                            style: TextStyle(fontSize: 12),
                          ),
                          if (error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: Text(sent ? 'Done' : 'Cancel'),
              ),
              if (!sent)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          update(() {
                            busy = true;
                            error = '';
                          });
                          try {
                            await ledger.api.request(
                              '/api/v1/feedback',
                              method: 'POST',
                              body: {
                                'id': id,
                                'topic': topic,
                                'message': message.text,
                                'appVersion': '1.1.1',
                              },
                            );
                            if (context.mounted) update(() => sent = true);
                          } catch (e) {
                            if (context.mounted) {
                              update(() => error = e.toString());
                            }
                          } finally {
                            if (context.mounted) update(() => busy = false);
                          }
                        },
                  child: Text(busy ? 'Sending…' : 'Send feedback'),
                ),
            ],
          ),
        ),
      ),
    );
    message.dispose();
  }

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
      final colors = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: colors.inverseSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            content: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: colors.onInverseSurface,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        );
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      notice(e.toString());
    }
  }

  Widget panel(String title, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  Widget metric(String label, int value, {bool hero = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(hero ? 24 : 20),
      decoration: BoxDecoration(
        color: hero ? const Color(0xff073b3b) : colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: hero
                        ? const Color(0xffbbddc4)
                        : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                hero
                    ? Icons.auto_awesome_rounded
                    : Icons.account_balance_wallet_outlined,
                color: hero ? const Color(0xffbbddc4) : colors.primary,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            rupees(value),
            style: TextStyle(
              fontSize: hero ? 34 : 28,
              letterSpacing: -.8,
              fontWeight: FontWeight.w800,
              color: hero ? Colors.white : null,
            ),
          ),
          if (hero) ...[
            const SizedBox(height: 8),
            const Text(
              'After bills, savings and category reserves',
              style: TextStyle(color: Color(0xffbbddc4), fontSize: 12),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  for (final action in [
                    (Icons.arrow_upward_rounded, 'Spend', 'expense'),
                    (Icons.arrow_downward_rounded, 'Income', 'income'),
                    (Icons.event_note_rounded, 'Plans', 'plans'),
                  ])
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          if (action.$3 == 'plans') {
                            context.go('/plans');
                          } else {
                            editRecord(
                              context,
                              ref.read(ledgerProvider),
                              'transaction',
                              initial: Doc(const Uuid().v4(), 'transaction', {
                                'type': action.$3,
                                'amount': 0,
                                'date': todayIndia(),
                                'description': '',
                              }),
                            );
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              action.$1,
                              size: 20,
                              color: const Color(0xff171b19),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              action.$2,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xff171b19),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> remove(Ledger ledger, Doc record) async {
    final name = text(record.data, 'name').isNotEmpty
        ? text(record.data, 'name')
        : text(record.data, 'description').isNotEmpty
        ? text(record.data, 'description')
        : 'this item';
    if (await confirm(
      context,
      'This will remove $name from your ledger.',
      title: 'Delete this item?',
      action: 'Delete',
      destructive: true,
    )) {
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
    final selected = await showModalBottomSheet<Doc>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Link a transaction',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a recorded payment to match this plan.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (available.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No matching unlinked transactions.'),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: available.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final record = available[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          text(record.data, 'description').isEmpty
                              ? 'Transaction'
                              : text(record.data, 'description'),
                        ),
                        subtitle: Text(text(record.data, 'date')),
                        trailing: Text(rupees(amount(record.data, 'amount'))),
                        onTap: () => Navigator.pop(sheetContext, record),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
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
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              const Text('Nothing due right now'),
            ],
          ),
        ),
      for (final o in items)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: o.doc.id == widget.occurrenceId
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(17),
          ),
          padding: const EdgeInsets.all(14),
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
                        const SizedBox(height: 4),
                        Text(
                          text(o.doc.data, 'date'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        rupees(amount(o.doc.data, 'amount')),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: o.state == 'overdue'
                              ? Theme.of(context).colorScheme.errorContainer
                              : Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          o.state,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
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
                          title: 'Skip this payment?',
                          action: 'Skip payment',
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
        metric('Available credit', amount(totals, 'unallocated'), hero: true),
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
            nextPaymentPerPlan(
              occurrences(ledger.records, today, totals['period']['end']),
            ),
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
      sections.add(
        panel('Payment schedule', [payments(ledger, nextPaymentPerPlan(all))]),
      );
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
                  isExpanded: true,
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
        panel('About FinTrack', [
          const Text('Version 1.1.1'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => openDeveloperLink('https://eucodes.in/'),
            child: const Text('Developed by Eucodes ↗'),
          ),
        ]),
      );
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
                          title: 'Discard local changes?',
                          action: 'Discard',
                          destructive: true,
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
        ]),
      );
      sections.add(
        panel('Reminder inbox', [
          payments(ledger, reminders(ledger.records, today)),
        ]),
      );
    }
    if (widget.screen == 'account') {
      final user = Map<String, dynamic>.from(
        ledger.api.session?['user'] as Map? ?? {},
      );
      final name = (user['name'] as String?)?.trim();
      sections.addAll([
        panel('Profile', [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xfff5ff76),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.person_outline_rounded, size: 31),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name?.isNotEmpty == true ? name! : 'FinTrack account',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      user['email'] as String? ?? '',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]),
        TextButton.icon(
          onPressed: () => giveFeedback(ledger),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Give feedback'),
        ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        leading: widget.screen == 'account'
            ? IconButton(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to home',
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'FinTrack',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => ledger.sync(),
            icon: const Icon(Icons.sync),
            tooltip: 'Sync now · ${ledger.status}',
          ),
          if (widget.screen != 'account')
            IconButton(
              onPressed: () => context.go('/account'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  ledger.api.session?['accessToken'] is String
                      ? ClipOval(
                          child: Image.network(
                            '${ledger.api.baseUrl}/api/v1/account/photo',
                            width: 30,
                            height: 30,
                            fit: BoxFit.cover,
                            headers: {
                              'Authorization':
                                  'Bearer ${ledger.api.session!['accessToken']}',
                            },
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.person_outline_rounded),
                          ),
                        )
                      : const Icon(Icons.person_outline_rounded),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ledger.status == 'Synced'
                            ? Colors.green
                            : ledger.status == 'Syncing'
                            ? Colors.amber
                            : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              tooltip: 'My account',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ledger.sync,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR FINANCES',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.screen == 'account'
                            ? 'My account'
                            : titles[index < 0 ? 0 : index],
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.7,
                            ),
                      ),
                    ],
                  ),
                ),
                if (widget.screen != 'account')
                  FilledButton.tonalIcon(
                    onPressed: () => editRecord(
                      context,
                      ledger,
                      widget.screen == 'plans' ? 'plan' : 'transaction',
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _headerChip(
                  Icons.calendar_month_outlined,
                  '${totals['period']['start']} – ${totals['period']['end']}',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ...sections.expand((w) => [w, const SizedBox(height: 16)]),
            const Center(
              child: Text(
                'FinTrack v1.1.1 · Developed by Eucodes',
                style: TextStyle(fontSize: 12, color: Color(0xff657672)),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          ['home', 'transactions', 'plans'].contains(widget.screen)
          ? FloatingActionButton(
              backgroundColor: const Color(0xffffe03d),
              foregroundColor: const Color(0xff073b3b),
              tooltip: 'Add transaction',
              onPressed: () => editRecord(context, ledger, 'transaction'),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: widget.screen == 'account'
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xfffce8e6),
                    foregroundColor: const Color(0xff9c3030),
                    side: BorderSide.none,
                  ),
                  onPressed: () => act(() async {
                    if (ledger.queue.isNotEmpty &&
                        !await confirm(
                          context,
                          'Unsynced changes will remain on this device. Sign out?',
                          title: 'Sign out?',
                          action: 'Sign out',
                        )) {
                      return;
                    }
                    await notifications?.logout();
                    await ledger.logout();
                  }),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ),
            )
          : NavigationBar(
              selectedIndex: index < 0 ? 0 : index,
              onDestinationSelected: (i) => context.go(routes[i]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note_rounded),
                  label: 'Plans',
                ),
                NavigationDestination(
                  icon: Icon(Icons.swap_horiz),
                  selectedIcon: Icon(Icons.swap_horiz_rounded),
                  label: 'Activity',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded),
                  label: 'Reports',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }

  Widget _headerChip(IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
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
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .4),
              ),
            ),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xfff5ff76), Color(0xffdff2a7)],
                        ),
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 34,
                        color: Color(0xff171b19),
                      ),
                    ),
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
                    validator: (v) => v == null || !v.contains('@')
                        ? 'Enter your email'
                        : null,
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
                    validator: (v) => (v?.length ?? 0) < 8
                        ? 'Use at least 8 characters'
                        : null,
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
    ),
  );
}
