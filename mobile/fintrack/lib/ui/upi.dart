import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../data/ledger.dart';
import '../domain/finance.dart';
import '../domain/upi.dart';

const upiPilot = bool.fromEnvironment('FINTRACK_UPI_PILOT');
const _attempts = '/api/v1/upi/attempts';
const _ids = Uuid();

class UpiPaymentsPage extends StatefulWidget {
  final Ledger ledger;
  const UpiPaymentsPage({super.key, required this.ledger});

  @override
  State<UpiPaymentsPage> createState() => _UpiPaymentsPageState();
}

class _UpiPaymentsPageState extends State<UpiPaymentsPage> {
  List<Data> items = [];
  String? cursor;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool next = false}) async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final path = next
          ? '$_attempts?cursor=${Uri.encodeQueryComponent(cursor!)}'
          : _attempts;
      final result = await widget.ledger.api.request(path);
      final rows = (result['items'] as List).cast<Data>();
      if (!mounted) return;
      setState(() {
        items = [if (next) ...items, ...rows];
        cursor = result['nextCursor'] as String?;
      });
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openPayment() async {
    await openUpiPayment(context, widget.ledger);
    if (mounted) await load();
  }

  Future<void> record(Data item) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _RecordUpiPage(ledger: widget.ledger, item: item),
      ),
    );
    if (mounted) await load();
  }

  String label(Data item) => switch (item['status']) {
    'ready' => 'Prepared',
    'launch_failed' => 'Could not open a UPI app',
    'recorded_manually' => 'Recorded manually',
    _ => 'Awaiting confirmation',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('UPI payments')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: loading || error != null ? null : openPayment,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan a payee QR'),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: load, child: const Text('Retry')),
          ],
          if (!loading && error == null && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Payment attempts will appear here.'),
            ),
          for (final item in items)
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    title: Text(
                      '${text(item, 'purpose')} · ${rupees(amount(item, 'amountPaise'))}',
                    ),
                    subtitle: Text(
                      [
                        widget.ledger.active
                                .where((row) => row.id == item['categoryId'])
                                .map((row) => text(row.data, 'name'))
                                .firstOrNull ??
                            'Category unavailable',
                        text(item, 'createdAt').split('T').first,
                        label(item),
                        if (item['payeeMasked'] case final String payee) payee,
                        if (item['evidenceStatus'] == 'statement')
                          'Matched to an uploaded statement',
                        if (item['evidenceStatus'] == 'unverified')
                          'No independent payment confirmation',
                        if (item['reportedOutcome'] != null)
                          'Reported by UPI app: ${item['reportedOutcome']}',
                        if (item['reviewRequired'] == true)
                          'The linked expense changed. Review it in Transactions.',
                      ].join('\n'),
                    ),
                  ),
                  if (item['status'] == 'awaiting_confirmation')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextButton(
                        onPressed: () => record(item),
                        child: const Text('Record or link expense'),
                      ),
                    ),
                ],
              ),
            ),
          if (cursor != null)
            TextButton(
              onPressed: loading ? null : () => load(next: true),
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
  );
}

Future<void> openUpiPayment(
  BuildContext context,
  Ledger ledger, {
  Occurrence? occurrence,
}) => Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (_) => _UpiDraftPage(ledger: ledger, occurrence: occurrence),
  ),
);

class _UpiDraftPage extends StatefulWidget {
  final Ledger ledger;
  final Occurrence? occurrence;
  const _UpiDraftPage({required this.ledger, this.occurrence});

  @override
  State<_UpiDraftPage> createState() => _UpiDraftPageState();
}

class _UpiDraftPageState extends State<_UpiDraftPage> {
  final form = GlobalKey<FormState>();
  final payload = TextEditingController();
  final amountField = TextEditingController();
  final purpose = TextEditingController();
  final reference = TextEditingController();
  final createKey = _ids.v4();
  UpiQr? qr;
  String? category;
  String? attemptId;
  Data? draft;
  String? message;
  bool busy = false;
  bool launched = false;
  bool camera = false;

  @override
  void initState() {
    super.initState();
    final occurrence = widget.occurrence;
    if (occurrence != null) {
      category = text(occurrence.doc.data, 'categoryId');
      purpose.text = text(occurrence.doc.data, 'name');
      final paise = amount(occurrence.doc.data, 'amount');
      amountField.text = (paise / 100).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    for (final controller in [payload, amountField, purpose, reference]) {
      controller.dispose();
    }
    super.dispose();
  }

  void review(String value) {
    try {
      final parsed = UpiQr.parse(value);
      setState(() {
        qr = parsed;
        message = null;
        camera = false;
      });
    } on FormatException catch (error) {
      setState(() => message = error.message);
    } on ArgumentError {
      setState(() => message = 'Enter a supported INR UPI payment QR.');
    }
  }

  Future<void> chooseImage() async {
    final scanner = MobileScannerController(autoStart: false);
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final capture = await scanner.analyzeImage(
        image.path,
        formats: [BarcodeFormat.qrCode],
      );
      final codes =
          capture?.barcodes
              .map((barcode) => barcode.rawValue)
              .nonNulls
              .toSet() ??
          {};
      if (!mounted) return;
      if (codes.length == 1) {
        review(codes.single);
      } else {
        setState(() => message = 'Choose an image containing one UPI QR code.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Could not read the image. Try scanning or pasting the UPI link.',
        );
      }
    } finally {
      await scanner.dispose();
    }
  }

  Future<void> openApp() async {
    if (busy || launched || !(form.currentState?.validate() ?? false)) return;
    final payment = qr!;
    final paise =
        payment.fixedPaise ?? UpiQr.parsePaise(amountField.text.trim())!;
    final api = widget.ledger.api;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      draft ??= {
        'idempotencyKey': createKey,
        'payeeVpa': payment.vpa,
        if (payment.name != null) 'payeeName': payment.name,
        'amountMode': payment.fixedPaise == null ? 'open' : 'fixed',
        'amountPaise': paise,
        'categoryId': category,
        if (widget.occurrence case final occurrence?)
          'occurrenceId': occurrence.doc.id,
        'purpose': purpose.text.trim(),
        if (reference.text.trim().isNotEmpty)
          'reference': reference.text.trim(),
      };
      attemptId ??=
          (await api.request(
                _attempts,
                method: 'POST',
                body: draft,
              ))['attemptId']
              as String;
      if (!mounted) return;
      final resultPath = '$_attempts/$attemptId/outcome';
      final claim = await api.request(
        resultPath,
        method: 'POST',
        body: {'idempotencyKey': _ids.v4(), 'result': 'claim'},
      );
      if (!mounted) return;
      if (claim['launchAllowed'] != true) {
        setState(() {
          launched = true;
          message = 'Check this attempt in your payment history.';
        });
        return;
      }
      launched = true;
      final result =
          await const MethodChannel(
            'fintrack/upi',
          ).invokeMethod<String>('open', payment.forHandoff(paise)) ??
          'unknown';
      await api.request(
        resultPath,
        method: 'POST',
        body: {'idempotencyKey': _ids.v4(), 'result': result},
      );
      if (!mounted) return;
      if (result == 'launch_failed') {
        setState(() {
          launched = false;
          message =
              'No UPI app could open this payment. Check the payee and amount above.';
        });
      } else {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message = launched
              ? 'Check your UPI app and payment history before paying again.'
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final payment = qr;
    final locked = draft != null || busy;
    final expenseCategories = widget.ledger.active.where(
      (record) =>
          record.kind == 'category' && text(record.data, 'type') == 'expense',
    );
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            payment == null ? 'Scan a payee QR' : 'Review UPI payment',
          ),
        ),
        body: SafeArea(
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (payment == null) ...[
                  if (camera)
                    SizedBox(
                      height: 280,
                      child: MobileScanner(
                        onDetect: (capture) {
                          if (qr != null) return;
                          final codes = capture.barcodes
                              .map((barcode) => barcode.rawValue)
                              .nonNulls
                              .toSet();
                          if (codes.length == 1) review(codes.single);
                        },
                        errorBuilder: (_, _) => const Center(
                          child: Text(
                            'Camera unavailable. Choose an image or paste a UPI link.',
                          ),
                        ),
                      ),
                    ),
                  if (!camera)
                    FilledButton.icon(
                      onPressed: () => setState(() => camera = true),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Open camera'),
                    ),
                  OutlinedButton(
                    onPressed: chooseImage,
                    child: const Text('Choose QR image'),
                  ),
                  TextFormField(
                    controller: payload,
                    decoration: const InputDecoration(
                      labelText: 'UPI payment link',
                    ),
                    maxLength: 4096,
                  ),
                  TextButton(
                    onPressed: () => review(payload.text),
                    child: const Text('Review pasted link'),
                  ),
                ] else ...[
                  Text(
                    payment.name?.isNotEmpty == true ? payment.name! : 'Payee',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SelectableText(payment.vpa),
                  if (payment.fixedPaise != null)
                    Text('Amount: ${rupees(payment.fixedPaise!)}'),
                  if (payment.fixedPaise == null)
                    TextFormField(
                      controller: amountField,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) =>
                          UpiQr.parsePaise(value?.trim() ?? '') == null
                          ? 'Enter a valid amount'
                          : null,
                    ),
                  if (payment.fixedPaise == null && payment.preservePayload)
                    const Text(
                      'Enter and review this amount in your UPI app as well.',
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Expense category',
                    ),
                    items: [
                      for (final record in expenseCategories)
                        DropdownMenuItem(
                          value: record.id,
                          child: Text(
                            text(record.data, 'name'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: locked || widget.occurrence != null
                        ? null
                        : (value) => setState(() => category = value),
                    validator: requiredText,
                  ),
                  TextFormField(
                    controller: purpose,
                    enabled: !locked,
                    maxLength: 200,
                    validator: requiredText,
                    decoration: const InputDecoration(
                      labelText: 'Payment purpose',
                    ),
                  ),
                  TextFormField(
                    controller: reference,
                    enabled: !locked,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Bill reference (optional)',
                    ),
                  ),
                  FilledButton(
                    onPressed: busy || launched ? null : openApp,
                    child: const Text('Pay with UPI'),
                  ),
                ],
                if (busy) const LinearProgressIndicator(),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordUpiPage extends StatefulWidget {
  final Ledger ledger;
  final Data item;
  const _RecordUpiPage({required this.ledger, required this.item});

  @override
  State<_RecordUpiPage> createState() => _RecordUpiPageState();
}

class _RecordUpiPageState extends State<_RecordUpiPage> {
  String? expenseId;
  String? method;
  String date = todayIndia();
  String? error;
  bool busy = false;

  Future<void> save() async {
    if (busy || (expenseId == null && method == null)) return;
    final item = widget.item;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record a paid expense?'),
        content: const Text(
          'Confirm that you checked the debit in your UPI app or bank statement. This is a manual record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record manually'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final expense = widget.ledger.active
          .where((row) => row.id == expenseId)
          .firstOrNull;
      await widget.ledger.api.request(
        '$_attempts/${item['attemptId']}/record',
        method: 'POST',
        body: {
          'idempotencyKey': _ids.v4(),
          'expectedRevision': item['revision'],
          'paymentMethodId': expense == null
              ? method
              : text(expense.data, 'paymentMethodId'),
          if (expense == null)
            'postingDate': date
          else
            'existingExpenseId': expense.id,
        },
      );
      await widget.ledger.sync();
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.ledger.active;
    final item = widget.item;
    final matches = records.where(
      (row) =>
          row.kind == 'transaction' &&
          row.revision > 0 &&
          text(row.data, 'type') == 'expense' &&
          row.data['categoryId'] == item['categoryId'] &&
          row.data['amount'] == item['amountPaise'],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Record UPI expense')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${text(item, 'purpose')} · ${rupees(amount(item, 'amountPaise'))}',
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: expenseId ?? '',
              decoration: const InputDecoration(labelText: 'Expense to link'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Create a new expense'),
                ),
                for (final row in matches)
                  DropdownMenuItem(
                    value: row.id,
                    child: Text(
                      '${text(row.data, 'date')} · ${text(row.data, 'description')}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) =>
                        setState(() => expenseId = value == '' ? null : value),
            ),
            if (expenseId == null) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: [
                  for (final row in records.where(
                    (row) => row.kind == 'paymentMethod',
                  ))
                    DropdownMenuItem(
                      value: row.id,
                      child: Text(
                        text(row.data, 'name'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => method = value),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final today = DateTime.parse(todayIndia());
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: DateTime.parse(date),
                          firstDate: DateTime(2000),
                          lastDate: today,
                        );
                        if (chosen != null && mounted) {
                          setState(
                            () => date = chosen
                                .toIso8601String()
                                .split('T')
                                .first,
                          );
                        }
                      },
                child: Text('Posting date: $date'),
              ),
            ],
            FilledButton(
              onPressed: busy || (expenseId == null && method == null)
                  ? null
                  : save,
              child: const Text('Review and record'),
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    );
  }
}
