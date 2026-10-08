import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation.dart';
import 'patterns.dart';
import 'motion.dart';
import 'package:intl/intl.dart';
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
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            title: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Give feedback',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
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
                          const Text(
                            'Topic',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: topic,
                            decoration: const InputDecoration(
                              hintText: 'Topic',
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
                          const Text(
                            'Your feedback',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: message,
                            enabled: !busy,
                            minLines: 4,
                            maxLines: 6,
                            maxLength: 3000,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(24),
                                ),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(24),
                                ),
                                borderSide: BorderSide.none,
                              ),
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
              if (sent)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              if (!sent)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffffe03d),
                      foregroundColor: const Color(0xff073b3b),
                    ),
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
                                  'appVersion': '1.2.1',
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

  String dateLabel(String date) =>
      DateFormat('d MMM yyyy').format(DateTime.parse(date));

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
          if (title != 'Can I spend this?')
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (title == 'Next payments' || title == 'Recent activity')
                  TextButton(
                    onPressed: () => navigateTo(
                      context,
                      title == 'Next payments' ? '/plans' : '/transactions',
                    ),
                    child: Text(
                      title == 'Next payments' ? 'Manage plans' : 'View all',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (title == 'Your budgets')
                  const Text('This cycle', style: TextStyle(fontSize: 12)),
              ],
            ),
          if (title != 'Can I spend this?') const SizedBox(height: 16),
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
      borderRadius: BorderRadius.circular(hero ? 28 : 24),
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
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: .1),
                ),
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
            fontSize: hero ? 40 : 24,
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
            '${dateLabel(summary(ref.read(ledgerProvider).records, todayIndia())['period']['start'])} – ${dateLabel(addDays(summary(ref.read(ledgerProvider).records, todayIndia())['period']['end'], -1))} · INR',
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
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
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
                : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: categoryColor(
                          ledger.active,
                          text(o.doc.data, 'categoryId'),
                        ).withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: FinIcon(
                          'plans',
                          size: 20,
                          color: categoryColor(
                            ledger.active,
                            text(o.doc.data, 'categoryId'),
                          ),
                        ),
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
                          dateLabel(text(o.doc.data, 'date')),
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
    final titles = [
          'Home',
          'Plans & budgets',
          'Transactions',
          'Reports',
          'Settings',
        ],
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
        balanceBreakdown(totals),
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
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xffbbddc4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: Color(0xff214b43),
                ),
              ),
            ),
            title: const Text(
              'Can I spend this?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Check before you checkout.',
              style: TextStyle(fontSize: 11),
            ),
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
      sections.add(
        panel('Your budgets', [
          const Text(
            'Small limits. A little more breathing room.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...budgetRows(ledger, totals),
        ]),
      );
      sections.add(
        panel('Next payments', [
          const Text(
            'The oldest unpaid payment for each plan, including overdue bills.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
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
        ]),
      );
      sections.add(spending);
    }
    if (widget.screen == 'plans') {
      sections.add(
        panel('Scheduled income and expenses', [
          Wrap(
            spacing: 2,
            runSpacing: 8,
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
                          label: Text(
                            v == 'emi' ? 'EMIs' : v,
                            style: TextStyle(
                              fontSize: 12,
                              color: planFilter == v
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : null,
                            ),
                          ),
                          selected: planFilter == v,
                          onSelected: (_) => setState(() => planFilter = v),
                        ),
                      ),
                    )
                    .toList(),
          ),
          if (!active.any(
            (r) =>
                r.kind == 'plan' &&
                (planFilter == 'all' || text(r.data, 'planType') == planFilter),
          ))
            const FinEmpty(
              'No plans yet. Add a plan to reserve money for future payments.',
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
          const Text(
            'Share of recorded expenses this cycle',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (amount(totals, 'expenses') == 0)
            const FinEmpty('No expenses recorded in this cycle.'),
          for (final c in active.where(
            (r) => r.kind == 'category' && text(r.data, 'type') == 'expense',
          ))
            categoryReport(ledger, c, totals, today),
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
          const Text('Version 1.2.1'),
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
    if (widget.screen == 'settings') {
      final about = sections.removeAt(0);
      sections.insert(sections.length - 1, about);
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
        leading: widget.screen != 'home'
            ? IconButton(
                onPressed: () => navigateBack(context),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to home',
              )
            : null,
        titleSpacing: widget.screen == 'home' ? 16 : 0,
        toolbarHeight: 64,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
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
                    'FinTrack.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
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
            onPressed: ledger.status == 'Syncing' ? null : () => ledger.sync(),
            icon: const FinIcon('sync', size: 18),
            tooltip: 'Sync now · ${ledger.status}',
          ),
          IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLow,
            ),
            tooltip: 'Toggle theme',
            onPressed: () => ref.read(themeProvider.notifier).state =
                ref.read(themeProvider) == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark,
            icon: const FinIcon('sun', size: 18),
          ),
          if (widget.screen != 'account')
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: () => navigateTo(context, '/account'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  ledger.api.session?['accessToken'] is String
                      ? ClipOval(
                          child: Image.network(
                            '${ledger.api.baseUrl}${ledger.api.session?['user']?['image'] ?? '/api/v1/account/photo'}',
                            width: 40,
                            height: 40,
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
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ledger.status == 'Synced'
                            ? const Color(0xff10b981)
                            : RegExp(
                                'could not|failed|unavailable|sign in|conflict',
                                caseSensitive: false,
                              ).hasMatch(ledger.status)
                            ? Colors.red
                            : Colors.amber,
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
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 100),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.screen != 'home')
                        Text(
                          'YOUR FINANCES, IN FOCUS',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
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
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1.2,
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
                    label: const Text('Add plan'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.screen == 'home')
              const Text(
                'Let’s make room for what matters.',
                style: TextStyle(fontSize: 14),
              )
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _headerChip(
                    Icons.calendar_month_outlined,
                    widget.screen == 'settings'
                        ? 'Make FinTrack work for you'
                        : widget.screen == 'transactions'
                        ? 'Browse recorded income and expenses · INR'
                        : '${dateLabel(totals['period']['start'])} – ${dateLabel(addDays(totals['period']['end'], -1))} · INR',
                  ),
                ],
              ),
            if (widget.screen == 'home') ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Text(
                          'Overview',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => navigateTo(context, '/plans'),
                        child: const Text(
                          'Budgets',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            sectionLayout(sections),
            const Center(
              child: Text(
                'FinTrack v1.2.1 · Developed by Eucodes',
                style: TextStyle(fontSize: 12, color: Color(0xff657672)),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          [
                'home',
                'transactions',
                'plans',
                'reports',
              ].contains(widget.screen) &&
              MediaQuery.viewInsetsOf(context).bottom == 0
          ? FinPress(
              child: FloatingActionButton(
                heroTag: null,
                shape: const CircleBorder(),
                backgroundColor: const Color(0xffffe03d),
                foregroundColor: const Color(0xff073b3b),
                tooltip: 'Add transaction',
                onPressed: () => editRecord(context, ledger, 'transaction'),
                child: const FinIcon('plus'),
              ),
            )
          : null,
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : FinDock(
              selected: index < 0 ? 0 : index,
              onSelected: (i) => navigateTo(context, routes[i]),
            ),
    );
  }

  Widget sectionLayout(List<Widget> sections) => LayoutBuilder(
    builder: (context, constraints) {
      Widget column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .expand((w) => [w, const SizedBox(height: 20)])
            .toList(),
      );
      Widget pair(List<Widget> left, List<Widget> right) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: column(left)),
          const SizedBox(width: 20),
          Expanded(child: column(right)),
        ],
      );
      if (constraints.maxWidth < 720) {
        if (widget.screen == 'reports') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sections[0]),
                  const SizedBox(width: 12),
                  Expanded(child: sections[1]),
                ],
              ),
              const SizedBox(height: 12),
              column(sections.sublist(2)),
            ],
          );
        }
        return column(sections);
      }
      if (widget.screen == 'home') {
        return pair(
          sections.sublist(0, sections.length - 3),
          sections.sublist(sections.length - 3),
        );
      }
      if (widget.screen == 'plans') {
        return Column(
          children: [
            pair([sections[0]], [sections[1]]),
            column(sections.sublist(2)),
          ],
        );
      }
      if (widget.screen == 'reports') {
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: sections[i]),
                ],
              ],
            ),
            const SizedBox(height: 20),
            pair([sections[3]], [sections[4]]),
            column(sections.sublist(5)),
          ],
        );
      }
      if (widget.screen == 'settings') {
        return pair(
          [for (var i = 0; i < sections.length; i += 2) sections[i]],
          [for (var i = 1; i < sections.length; i += 2) sections[i]],
        );
      }
      return column(sections);
    },
  );

  Widget categoryReport(
    Ledger ledger,
    Doc category,
    Data totals,
    String today,
  ) {
    final spent = ledger.active
        .where(
          (t) =>
              t.kind == 'transaction' &&
              text(t.data, 'type') == 'expense' &&
              text(t.data, 'categoryId') == category.id &&
              text(t.data, 'date').compareTo(totals['period']['start']) >= 0 &&
              text(t.data, 'date').compareTo(totals['period']['end']) < 0 &&
              text(t.data, 'date').compareTo(today) <= 0,
        )
        .fold(0, (v, t) => v + amount(t.data, 'amount'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(text(category.data, 'name'))),
              const SizedBox(width: 12),
              Text(
                rupees(spent),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin: 0,
              end: amount(totals, 'expenses') == 0
                  ? 0
                  : (spent / amount(totals, 'expenses')).clamp(0, 1),
            ),
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              borderRadius: BorderRadius.circular(100),
              color: categoryColor(ledger.active, category.id),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLow,
            ),
          ),
        ],
      ),
    );
  }

  Widget balanceBreakdown(Data totals) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(24),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = MediaQuery.sizeOf(context).width < 375 ? 2 : 3;
          return Wrap(
            spacing: 10,
            runSpacing: 20,
            children: [
              for (final item in [
                ('Current balance', 'balance'),
                ('Bills reserved', 'commitments'),
                ('Protected savings', 'savings'),
              ])
                SizedBox(
                  width: (constraints.maxWidth - 10 * (columns - 1)) / columns,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hideBalances
                            ? '••••••'
                            : rupees(amount(totals, item.$2)),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

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
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const {
                            'expense': Color(0xfff2d8c9),
                            'income': Color(0xffbbddc4),
                            'plans': Color(0xfff7edc3),
                            'reports': Color(0xffe1e7f2),
                          }[entry.$1],
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: FinIcon(
                            entry.$1,
                            size: 20,
                            color: const Color(0xff214b43),
                          ),
                        ),
                      ),
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

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
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
  }

  Widget field(String label, Widget input) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      input,
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/fintrack-icon.png',
                      width: 56,
                      height: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FinTrack',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your personal finance tracker',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AutofillGroup(
                      child: Form(
                        key: form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  for (final entry in [
                                    (false, 'Sign In'),
                                    (true, 'Create Account'),
                                  ])
                                    Expanded(
                                      child: Semantics(
                                        selected: register == entry.$1,
                                        child: AnimatedContainer(
                                          duration: reduceMotion(context)
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 160,
                                                ),
                                          decoration: BoxDecoration(
                                            color: register == entry.$1
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.surface
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => setState(() {
                                                    register = entry.$1;
                                                    error = null;
                                                  }),
                                            child: Text(
                                              entry.$2,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (register) ...[
                              field(
                                'Name',
                                TextFormField(
                                  controller: name,
                                  enabled: !busy,
                                  autofillHints: const [AutofillHints.name],
                                  decoration: const InputDecoration(
                                    hintText: 'Your name',
                                  ),
                                  validator: (v) => (v ?? '').trim().isEmpty
                                      ? 'Enter your name'
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            field(
                              'Email',
                              TextFormField(
                                controller: email,
                                enabled: !busy,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  hintText: 'you@example.com',
                                ),
                                validator: (v) =>
                                    !RegExp(
                                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                    ).hasMatch(v ?? '')
                                    ? 'Enter a valid email'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            field(
                              'Password',
                              TextFormField(
                                controller: password,
                                enabled: !busy,
                                obscureText: obscure,
                                autofillHints: [
                                  register
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                onFieldSubmitted: (_) => submit(),
                                decoration: InputDecoration(
                                  hintText: 'Min. 8 characters',
                                  suffixIcon: IconButton(
                                    tooltip: obscure
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () =>
                                        setState(() => obscure = !obscure),
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                validator: (v) => (v?.length ?? 0) < 8
                                    ? 'Use at least 8 characters'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (error != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            FinPress(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xffffe03d),
                                  foregroundColor: const Color(0xff073b3b),
                                ),
                                onPressed: busy ? null : submit,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      busy
                                          ? 'Please wait...'
                                          : register
                                          ? 'Create Account'
                                          : 'Sign In',
                                    ),
                                    if (!busy) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward, size: 20),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
