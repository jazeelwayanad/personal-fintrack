import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation.dart';
import 'patterns.dart';
import 'account.dart';
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
                                'appVersion': '1.2.0',
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
  String search = '', forecastMonth = todayIndia().substring(0, 7);
  bool hideBalances = false;
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

  Widget panel(String title, List<Widget> children) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff1c3535)
        : Colors.white,
    borderRadius: BorderRadius.circular(24),
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
  Widget metric(String label, int value, {bool hero = false}) => Container(
    padding: EdgeInsets.all(hero ? 24 : 20),
    decoration: BoxDecoration(
      color: hero
          ? const Color(0xff073b3b)
          : Theme.of(context).colorScheme.surface,
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
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ),
            if (hero)
              IconButton(
                tooltip: hideBalances ? 'Show balance' : 'Hide balance',
                onPressed: () => setState(() => hideBalances = !hideBalances),
                icon: const FinIcon('eye', color: Colors.white),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          hideBalances ? '••••' : rupees(value),
          style: TextStyle(
            fontSize: hero ? 38 : 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
            color: hero ? Colors.white : null,
          ),
        ),
        if (hero) ...[
          const SizedBox(height: 10),
          const Text(
            'After bills, savings & category reserves',
            style: TextStyle(fontSize: 12, color: Color(0xffbbddc4)),
          ),
          const SizedBox(height: 24),
          Text(
            '${summary(ref.read(ledgerProvider).records, todayIndia())['period']['start']} – ${addDays(summary(ref.read(ledgerProvider).records, todayIndia())['period']['end'], -1)} · INR',
            style: const TextStyle(fontSize: 12, color: Color(0xffbbddc4)),
          ),
        ],
      ],
    ),
  );

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
              text(r.data, 'type') == text(o.doc.data, 'type') &&
              text(r.data, 'categoryId') == text(o.doc.data, 'categoryId'),
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
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FinIcon(
                      'plans',
                      color: categoryColor(
                        ledger.active,
                        text(o.doc.data, 'categoryId'),
                      ),
                    ),
                  ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ledger.active
                          .where((r) => r.id == b['categoryId'])
                          .firstOrNull
                          ?.data['name'] ??
                      'Category',
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
              color: b['spent'] > b['amount']
                  ? Colors.red
                  : categoryColor(ledger.active, b['categoryId']),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${rupees(b['remaining'])} remaining · Planned ${rupees(b['planned'])}\n${b['source'] == 'plans' ? 'Calculated from plans' : 'Manual limit includes plans'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (edit)
                  TextButton(
                    onPressed: () => editRecord(
                      context,
                      ledger,
                      'budget',
                      initial:
                          ledger.active
                              .where((r) => r.id == b['id'])
                              .firstOrNull ??
                          Doc(b['id'], 'budget', {
                            'categoryId': b['categoryId'],
                            'amount': b['amount'],
                          }),
                    ),
                    child: const Text('Edit limit'),
                  ),
                if (edit && b['manual'] != null)
                  IconButton(
                    tooltip: 'Use plan total',
                    icon: const Icon(Icons.auto_awesome_outlined),
                    onPressed: () => act(() async {
                      final entry = ledger.active
                          .where((r) => r.id == b['id'])
                          .firstOrNull;
                      if (entry != null) {
                        await ledger.save([entry.copy(deleted: true)]);
                      }
                    }),
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
    if (ledger.loading ||
        (ledger.signedIn &&
            ledger.records.isEmpty &&
            ledger.status == 'Syncing')) {
      return const Scaffold(body: BrandLoading(label: 'Opening FinTrack…'));
    }
    if (!ledger.signedIn) return LoginScreen(ledger: ledger);
    if (widget.screen == 'home') {
      notifications ??= PushNotifications(ledger.api, (route) {
        if (mounted) {
          navigateTo(context, route.startsWith('/plans') ? route : '/plans');
        }
      })..initialize().catchError((_) {});
    }
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
        quickActions(ledger),
        panel('Balance breakdown', [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Current balance'),
            trailing: Text(rupees(amount(totals, 'balance'))),
          ),
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
          ExpansionTile(
            key: const PageStorageKey('spending-allowance-expanded'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Check before you checkout'),
            children: [
              TextField(
                controller: checkController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                          r.kind == 'category' &&
                          text(r.data, 'type') == 'expense',
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
              if (checkController.text.isNotEmpty &&
                  checkCategory.isNotEmpty) ...[
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
                                ((double.tryParse(checkController.text) ?? 0) *
                                        100)
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
            ],
          ),
        ]),
      );
      sections.add(panel('Category budgets', budgetRows(ledger, totals)));
      sections.add(
        panel('Next payments', [
          payments(
            ledger,
            nextPaymentPerPlan(
              occurrences(ledger.records, today, totals['period']['end']),
            ),
          ),
        ]),
      );
    }
    if (widget.screen == 'home') {
      final spending = sections.removeAt(sections.length - 3);
      final budgets = sections.removeAt(sections.length - 2);
      sections.add(budgets);
      final recent = active.where((r) => r.kind == 'transaction').toList()
        ..sort((a, b) => text(b.data, 'date').compareTo(text(a.data, 'date')));
      sections.add(
        panel('Recent activity', [
          if (recent.isEmpty)
            const FinEmpty(
              'No transactions yet. Add your first income or expense.',
            ),
          for (final t in recent.take(4)) transactionRow(ledger, t),
          TextButton(
            onPressed: () => navigateTo(context, '/transactions'),
            child: const Text('View all'),
          ),
        ]),
      );
      sections.add(spending);
    }
    if (widget.screen == 'plans') {
      sections.add(
        panel('Scheduled income and expenses', [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  [
                        'all',
                        'salary',
                        'income',
                        'emi',
                        'subscription',
                        'expense',
                        'recharge',
                      ]
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
              leading: FinIcon(
                'plans',
                color: categoryColor(active, text(p.data, 'categoryId')),
              ),
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
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search transactions',
              prefixIcon: FinIcon('activity'),
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 14),
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
                        (month.isEmpty ||
                            text(r.data, 'date').startsWith(month)) &&
                        [
                          text(r.data, 'description'),
                          labels[text(r.data, 'categoryId')] ?? '',
                          labels[text(r.data, 'paymentMethodId')] ?? '',
                        ].join(' ').toLowerCase().contains(search) &&
                        (filter == 'all' || text(r.data, 'type') == filter),
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      text(b.data, 'date').compareTo(text(a.data, 'date')),
                )))
            transactionRow(ledger, t, editable: true),
          if (!active.any(
            (r) =>
                r.kind == 'transaction' &&
                (month.isEmpty || text(r.data, 'date').startsWith(month)) &&
                (filter == 'all' || text(r.data, 'type') == filter) &&
                [
                  text(r.data, 'description'),
                  labels[text(r.data, 'categoryId')] ?? '',
                  labels[text(r.data, 'paymentMethodId')] ?? '',
                ].join(' ').toLowerCase().contains(search),
          ))
            const FinEmpty(
              'No matching transactions. Adjust your filters or add a transaction.',
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
              leading: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: categoryColor(active, c.id),
                  shape: BoxShape.circle,
                ),
              ),
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
    if (widget.screen == 'plans' || widget.screen == 'reports') {
      final forecast = monthlyForecast(ledger.records, today, forecastMonth);
      sections.add(
        panel('Calendar-month forecast', [
          TextButton.icon(
            icon: const FinIcon('plans'),
            label: Text(forecastMonth),
            onPressed: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: DateTime.parse('$forecastMonth-01'),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100, 12, 31),
              );
              if (selected != null) {
                setState(() => forecastMonth = iso(selected).substring(0, 7));
              }
            },
          ),
          Text(
            '${forecast['count']} scheduled payments',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Expenses ${rupees(forecast['expenses'])} · Income ${rupees(forecast['income'])}',
          ),
          const SizedBox(height: 12),
          const Text(
            'Exact recurrence dates, not monthly averages. Recharge dates are estimates until paid; overdue commitments remain reserved separately.',
            style: TextStyle(fontSize: 12),
          ),
          if ((forecast['items'] as List).isEmpty)
            const FinEmpty('No payments scheduled in this month.'),
          for (final o in forecast['items'] as List<Occurrence>)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: FinIcon(
                'plans',
                color: categoryColor(active, text(o.doc.data, 'categoryId')),
              ),
              title: Text(text(o.doc.data, 'name')),
              subtitle: Text(text(o.doc.data, 'date')),
              trailing: Text(rupees(amount(o.doc.data, 'amount'))),
            ),
        ]),
      );
    }
    if (widget.screen == 'settings') {
      sections.add(
        panel('About FinTrack', [
          const Text('Version 1.2.0'),
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
      return AccountScreen(
        ledger: ledger,
        feedback: () => giveFeedback(ledger),
        onSignOut: () => act(() async {
          if (ledger.queue.isNotEmpty &&
              !await confirm(
                context,
                'Your unsynced changes will remain on this device. Sign out?',
                action: 'Sign out',
              )) {
            return;
          }
          await ledger.logout();
          if (context.mounted) navigateTo(context, '/');
        }),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: widget.screen == 'account'
            ? IconButton(
                onPressed: () => navigateBack(context),
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  'assets/fintrack-icon.png',
                  fit: BoxFit.cover,
                ),
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
            tooltip: 'Toggle theme',
            onPressed: () => ref.read(themeProvider.notifier).state =
                ref.read(themeProvider) == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark,
            icon: const FinIcon('sun'),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => ledger.sync(),
            icon: const FinIcon('sync'),
            tooltip: 'Sync now · ${ledger.status}',
          ),
          if (widget.screen != 'account')
            IconButton(
              onPressed: () => navigateTo(context, '/account'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  ledger.api.session?['accessToken'] is String
                      ? ClipOval(
                          child: Image.network(
                            '${ledger.api.baseUrl}${ledger.api.session?['user']?['image'] ?? '/api/v1/account/photo'}',
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
          key: PageStorageKey('fintrack-${widget.screen}'),
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
                        widget.screen == 'home'
                            ? 'Hello, ${ledger.api.session?['user']?['name'] ?? 'there'}.'
                            : widget.screen == 'account'
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
                if (widget.screen == 'plans')
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
                  '${totals['period']['start']} – ${addDays(totals['period']['end'], -1)}',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ...sections.expand((w) => [w, const SizedBox(height: 16)]),
            const Center(
              child: Text(
                'FinTrack v1.2.0 · Developed by Eucodes',
                style: TextStyle(fontSize: 12, color: Color(0xff657672)),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          ['home', 'transactions', 'plans', 'reports'].contains(widget.screen)
          ? FloatingActionButton(
              shape: const CircleBorder(),
              backgroundColor: const Color(0xffffe03d),
              foregroundColor: const Color(0xff073b3b),
              tooltip: 'Add transaction',
              onPressed: () => editRecord(context, ledger, 'transaction'),
              child: const FinIcon('plus'),
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
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: NavigationBar(
                  selectedIndex: index < 0 ? 0 : index,
                  onDestinationSelected: (i) => navigateTo(context, routes[i]),
                  destinations: const [
                    NavigationDestination(
                      icon: FinIcon('home'),
                      selectedIcon: FinIcon('home', color: Color(0xffffffff)),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: FinIcon('plans'),
                      selectedIcon: FinIcon('plans', color: Color(0xffffffff)),
                      label: 'Plans',
                    ),
                    NavigationDestination(
                      icon: FinIcon('activity'),
                      selectedIcon: FinIcon(
                        'activity',
                        color: Color(0xffffffff),
                      ),
                      label: 'Activity',
                    ),
                    NavigationDestination(
                      icon: FinIcon('reports'),
                      selectedIcon: FinIcon(
                        'reports',
                        color: Color(0xffffffff),
                      ),
                      label: 'Reports',
                    ),
                    NavigationDestination(
                      icon: FinIcon('settings'),
                      selectedIcon: FinIcon(
                        'settings',
                        color: Color(0xffffffff),
                      ),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget quickActions(Ledger ledger) => Row(
    children: [
      for (final entry in [
        ('expense', 'Expense'),
        ('income', 'Income'),
        ('plans', 'Plans'),
        ('reports', 'Reports'),
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  if (entry.$1 == 'expense' || entry.$1 == 'income') {
                    editRecord(
                      context,
                      ledger,
                      'transaction',
                      initial: Doc(const Uuid().v4(), 'transaction', {
                        'type': entry.$1,
                        'amount': 0,
                        'date': todayIndia(),
                        'description': '',
                        'categoryId': '',
                        'paymentMethodId':
                            ledger.active
                                .where((r) => r.kind == 'paymentMethod')
                                .firstOrNull
                                ?.id ??
                            '',
                      }),
                    );
                  } else {
                    navigateTo(context, '/${entry.$1}');
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      FinIcon(entry.$1),
                      const SizedBox(height: 8),
                      Text(entry.$2, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
  Widget transactionRow(Ledger ledger, Doc t, {bool editable = false}) {
    final category = ledger.active
        .where((r) => r.id == text(t.data, 'categoryId'))
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: categoryColor(
                    ledger.active,
                    text(t.data, 'categoryId'),
                  ).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: FinIcon(
                  text(t.data, 'type'),
                  color: categoryColor(
                    ledger.active,
                    text(t.data, 'categoryId'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(t.data, 'description').isEmpty
                          ? text(category?.data ?? {}, 'name', 'Transaction')
                          : text(t.data, 'description'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${text(t.data, 'date')} · ${text(category?.data ?? {}, 'name', 'Category')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (text(t.data, 'occurrenceId').isNotEmpty)
                      const Text(
                        'Planned payment',
                        style: TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${text(t.data, 'type') == 'income' ? '+' : '−'}${rupees(amount(t.data, 'amount'))}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: text(t.data, 'type') == 'income'
                        ? const Color(0xff23734c)
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (editable)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      editRecord(context, ledger, 'transaction', initial: t),
                  child: const Text('Edit'),
                ),
                if (text(t.data, 'occurrenceId').isNotEmpty)
                  TextButton(
                    onPressed: () => act(
                      () => ledger.save([
                        t.copy(data: {...t.data, 'occurrenceId': null}),
                      ]),
                    ),
                    child: const Text('Unlink'),
                  ),
                IconButton(
                  tooltip: 'Delete transaction',
                  onPressed: () => act(() => remove(ledger, t)),
                  icon: const FinIcon('trash'),
                ),
              ],
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
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.asset(
                          'assets/fintrack-icon.png',
                          fit: BoxFit.cover,
                        ),
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
