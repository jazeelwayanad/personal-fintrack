'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { rupees } from '@/lib/finance/engine';
import { number as n, string as s } from '@/lib/finance/model';
import { buttonClass, Field, inputClass } from './finance-forms';
import { useFinance } from './finance-provider';

type Statement = { date: string; amountPaise: number; direction: 'debit'; reference: string };
type Candidate = { attemptId: string; revision: number; purpose: string; categoryId: string; referenceMatched: boolean };
type Row = { row: Statement; duplicate: boolean; candidates: Candidate[] };

async function post(path: string, payload: object) {
  const response = await fetch('/api/v1/upi/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error ?? 'Could not process the statement.');
  return data;
}

export function StatementReview() {
  const { records, store } = useFinance();
  const router = useRouter();
  const [rows, setRows] = useState<Row[]>();
  const [rowIndex, setRowIndex] = useState('');
  const [attemptId, setAttemptId] = useState('');
  const [method, setMethod] = useState('');
  const [existingExpenseId, setExistingExpenseId] = useState('');
  const [key, setKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const selected = rowIndex === '' ? undefined : rows?.[Number(rowIndex)];
  const candidate = selected?.candidates.find(value => value.attemptId === attemptId);
  const existing = records.find(record => !record.deleted && record.id === existingExpenseId && record.kind === 'transaction');

  function resetRecord() {
    setAttemptId(''); setMethod(''); setExistingExpenseId(''); setKey('');
  }
  async function preview(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const file = new FormData(event.currentTarget).get('statement');
    if (!(file instanceof File) || file.size < 1 || file.size > 150_000) {
      setError('Choose a CSV file up to 150 KB.'); return;
    }
    setBusy(true); setError(''); setMessage('');
    try {
      const data = await post('statement-preview', { content: await file.text() });
      setRows(data.rows); setRowIndex(''); resetRecord();
    } catch (failure) {
      setRows(undefined);
      setError(failure instanceof Error ? failure.message : 'Could not read this statement.');
    } finally { setBusy(false); }
  }
  async function commit(event: FormEvent) {
    event.preventDefault();
    if (!selected || !candidate || (!method && !existing)) return;
    const requestKey = key || crypto.randomUUID();
    setKey(requestKey); setBusy(true); setError('');
    try {
      await post('attempts/' + candidate.attemptId + '/record', {
        idempotencyKey: requestKey, expectedRevision: candidate.revision, statement: selected.row,
        paymentMethodId: existing ? s(existing.data, 'paymentMethodId') : method,
        ...(existing ? { existingExpenseId } : { postingDate: selected.row.date }),
      });
      setRows(values => values?.map((value, index) => index === Number(rowIndex)
        ? { ...value, duplicate: true, candidates: [] }
        : { ...value, candidates: value.candidates.filter(item => item.attemptId !== attemptId) }));
      setRowIndex(''); resetRecord();
      setMessage('Expense reconciled with your uploaded statement.');
      void store.sync();
      router.refresh();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Could not record this expense.');
    } finally { setBusy(false); }
  }

  return <section className="fin-panel mt-6 space-y-4 p-5">
    <h2 className="text-base font-semibold">Match a bank statement</h2>
    <p className="text-sm">Upload a CSV with columns <code>date,amount,direction,reference</code>. Use ISO dates, INR amounts, and <code>debit</code> or <code>credit</code>. Matches require your review.</p>
    <form onSubmit={preview} className="flex flex-wrap items-end gap-3">
      <Field label="Statement CSV"><input className={inputClass} type="file" name="statement" accept=".csv,text/csv" required/></Field>
      <button className={buttonClass} disabled={busy}>Preview matches</button>
    </form>
    {rows && <p role="status" className="text-sm">{rows.filter(value => value.candidates.length).length} debits with possible matches · {rows.filter(value => value.duplicate).length} duplicates · {rows.filter(value => !value.duplicate && !value.candidates.length).length} unmatched.</p>}
    {!!rows?.some(value => value.candidates.length) && <form className="max-w-lg space-y-3" onSubmit={commit}>
      <Field label="Statement debit"><select className={inputClass} value={rowIndex} onChange={event => { setRowIndex(event.target.value); resetRecord(); }} required>
        <option value="">Choose a debit</option>
        {rows.map((value, index) => value.candidates.length ? <option key={index} value={index}>{value.row.date} · {rupees(value.row.amountPaise)} · Reference ending {value.row.reference.slice(-4)}</option> : null)}
      </select></Field>
      {selected && <Field label="Payment attempt"><select className={inputClass} value={attemptId} onChange={event => { setAttemptId(event.target.value); setKey(''); }} required>
        <option value="">Choose the matching attempt</option>
        {selected.candidates.map(value => <option key={value.attemptId} value={value.attemptId}>{value.purpose}{value.referenceMatched ? ' · Reference matches' : ''}</option>)}
      </select></Field>}
      {candidate && <>
        <Field label="Expense to link"><select className={inputClass} value={existingExpenseId} onChange={event => { setExistingExpenseId(event.target.value); setKey(''); }}>
          <option value="">Record a new expense</option>
          {records.filter(record => !record.deleted && record.kind === 'transaction' && record.revision > 0 && s(record.data, 'type') === 'expense'
            && s(record.data, 'categoryId') === candidate.categoryId && s(record.data, 'date') === selected!.row.date && n(record.data, 'amount') === selected!.row.amountPaise)
            .map(record => <option key={record.id} value={record.id}>{s(record.data, 'description') || record.id}</option>)}
        </select></Field>
        {!existingExpenseId && <Field label="Payment method"><select className={inputClass} value={method} onChange={event => { setMethod(event.target.value); setKey(''); }} required>
          <option value="">Choose a payment method</option>
          {records.filter(record => !record.deleted && record.kind === 'paymentMethod').map(record => <option key={record.id} value={record.id}>{s(record.data, 'name')}</option>)}
        </select></Field>}
        <button className={buttonClass} disabled={busy || (!method && !existing)}>Confirm statement match</button>
      </>}
    </form>}
    {message && <p role="status">{message}</p>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </section>;
}
