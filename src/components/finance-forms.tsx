'use client';
import { useState } from 'react';
import { Data, Document, Kind, document, defaults, string as s, number as n } from '@/lib/finance/model';
import { checkSpending, occurrences, snapshotPast, todayIndia, rupees } from '@/lib/finance/engine';
import { useFinance } from './finance-provider';
import { toast } from 'sonner';
import { useConfirm } from './confirm-dialog';
export const inputClass = 'w-full rounded-2xl border border-border bg-[#f8faf8] px-4 py-3 text-sm outline-none focus:border-[#71ae91] focus:ring-2 focus:ring-[#71ae91]/25 dark:bg-secondary';
export const buttonClass = 'rounded-2xl bg-primary px-5 py-3 text-sm font-semibold text-primary-foreground transition-transform hover:-translate-y-0.5 disabled:opacity-40';
export function Field({ label, children }: { label: string; children: React.ReactNode }) { return <label className="grid gap-1.5 text-sm font-medium">{label}{children}</label>; }
export function Editor({ kind, initial, close, occurrenceId }: { kind: Kind; initial?: Document; close: () => void; occurrenceId?: string }) {
  const { store, records } = useFinance();
  const ask = useConfirm();
  const [data, setData] = useState<Data>(initial?.data ?? (kind === 'preferences' ? { ...defaults } : { type: kind === 'plan' ? 'income' : 'expense', planType: 'salary', recurrence: 'monthly', date: todayIndia(), startDate: todayIndia(), reminders: true, color: '#74aa89', amount: 0, name: '', description: '' }));
  const [alreadySpent, setAlreadySpent] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const set = (key: string, value: unknown) => setData(d => ({ ...d, [key]: value }));
  const categories = records.filter(r => !r.deleted && r.kind === 'category' && s(r.data, 'type') === (kind === 'budget' ? 'expense' : s(data, 'type')));
  const methods = records.filter(r => !r.deleted && r.kind === 'paymentMethod');
  const field = (key: string, label: string, type = 'text', required = true) => <Field label={label}><input className={inputClass} type={type} required={required} value={s(data, key)} onChange={e => set(key, e.target.value || null)}/></Field>;
  const money = (key: string, label: string) => <Field label={label}><input className={inputClass} type="number" step="0.01" min={kind === 'adjustment' ? undefined : 0} required value={n(data, key) / 100 || ''} onChange={e => set(key, Math.round(Number(e.target.value) * 100))}/></Field>;
  const select = (key: string, label: string, options: { id: string; label: string }[]) => <Field label={label}><select className={inputClass} required value={s(data, key)} onChange={e => { setData(d => ({ ...d, [key]: e.target.value, ...(key === 'type' ? { categoryId: '', planType: e.target.value === 'income' ? 'income' : 'expense' } : {}) })); }}><option value="">Choose…</option>{options.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}</select></Field>;
  const check = checkSpending(records.filter(r => r.id !== initial?.id), todayIndia(), n(data, 'amount'), s(data, 'categoryId'));
  const isExisting = !!initial && records.some(r => r.id === initial.id && !r.deleted);
  const isExpense = kind === 'transaction' && s(data, 'type') === 'expense' && !occurrenceId && !s(data, 'occurrenceId');
  async function submit(e: React.FormEvent) {
    e.preventDefault(); setBusy(true); setError('');
    try {
      if ((kind === 'transaction' || kind === 'adjustment') && s(data, 'date') > todayIndia()) throw new Error('Use a plan for future income or expenses.');
      if (isExpense && !alreadySpent && !check.allowed) {
        const mode = records.find(r => !r.deleted && r.kind === 'preferences')?.data.limitMode;
        if (mode === 'block') throw new Error('Above your spending limit. Adjust your budget or choose Already spent.');
        if (!await ask({ title: 'Over your limit', message: `This exceeds your allowance by ${rupees(check.shortfall)}.`, action: 'Record anyway' })) return;
      }
      const id = kind === 'preferences' ? 'preferences' : kind === 'budget' ? `budget:${s(data, 'categoryId')}` : initial?.id ?? crypto.randomUUID();
      const docs = kind === 'plan' && initial ? snapshotPast(records, initial.id, todayIndia()) : [];
      docs.push(document(id, kind, data));
      if (kind === 'plan' && s(data, 'planType') === 'salary') { const pref = records.find(r => r.kind === 'preferences' && !r.deleted); docs.push(document('preferences', 'preferences', { ...defaults, ...pref?.data, payday: Number(s(data, 'startDate').slice(8)) })); }
      if (occurrenceId) {
        const occ = occurrences(records, todayIndia(), '2100-12-31').find(o => o.id === occurrenceId);
        if (!occ) throw new Error('Payment no longer exists.');
        docs[docs.length - 1].data.occurrenceId = occurrenceId;
        docs[docs.length - 1].id = initial?.id ?? `payment:${occurrenceId}`;
        docs.push(document(occ.id, 'occurrence', occ.data));
      }
      await store.save(docs); toast.success('Saved'); close();
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not save'); } finally { setBusy(false); }
  }
  return <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true" aria-label={`${isExisting ? 'Edit' : 'Add'} ${kind}`}><form onSubmit={submit} className="fin-panel max-h-[90vh] w-full max-w-lg space-y-4 overflow-y-auto p-6 sm:p-7"><div className="flex justify-between"><h2 className="text-xl font-bold">{isExisting ? 'Edit' : 'Add'} {kind === 'paymentMethod' ? 'payment method' : kind}</h2><button type="button" onClick={close} aria-label="Close">✕</button></div>
    {['category', 'paymentMethod', 'plan'].includes(kind) && field('name', 'Name')}
    {['transaction', 'category', 'plan'].includes(kind) && select('type', 'Type', ['income', 'expense'].map(id => ({ id, label: id })))}
    {kind === 'plan' && select('planType', 'Plan type', (s(data, 'type') === 'income' ? ['salary', 'income'] : ['emi', 'subscription', 'expense']).map(id => ({ id, label: id === 'emi' ? 'EMI' : id })))}
    {['transaction', 'plan', 'budget', 'adjustment'].includes(kind) && money('amount', kind === 'adjustment' ? 'Adjustment (₹; negative reduces balance)' : 'Amount (₹)')}
    {['transaction', 'plan', 'budget'].includes(kind) && select('categoryId', 'Category', categories.map(r => ({ id: r.id, label: s(r.data, 'name') })))}
    {kind === 'transaction' && select('paymentMethodId', 'Payment method', methods.map(r => ({ id: r.id, label: s(r.data, 'name') })))}
    {['transaction', 'adjustment'].includes(kind) && field('date', 'Date', 'date')}
    {['transaction', 'adjustment'].includes(kind) && field('description', 'Note', 'text', false)}
    {kind === 'category' && field('color', 'Color', 'color')}
    {kind === 'plan' && <>{field('startDate', 'First due date / payday', 'date')}{field('endDate', 'Final payment date (optional)', 'date', false)}{select('recurrence', 'Repeat', ['once', 'monthly', 'yearly'].map(id => ({ id, label: id })))}<label className="flex gap-2"><input type="checkbox" checked={data.reminders !== false} onChange={e => set('reminders', e.target.checked)}/>Payment reminders</label></>}
    {kind === 'preferences' && <><Field label="Monthly payday"><input className={inputClass} type="number" min="1" max="31" value={n(data, 'payday', 1)} onChange={e => set('payday', Number(e.target.value))}/></Field>{money('savings', 'Protected savings / emergency money (₹)')}{select('limitMode', 'When spending exceeds the limit', [{ id: 'warn', label: 'Warn and allow confirmation' }, { id: 'block', label: 'Block planned spending' }])}<label className="flex gap-2"><input type="checkbox" checked={data.notifications !== false} onChange={e => set('notifications', e.target.checked)}/>Daily reminders</label></>}
    {isExpense && <div className="rounded-xl bg-muted p-3 text-sm"><p>Available for this category: <strong>{rupees(check.maximum)}</strong></p>{!check.allowed && n(data, 'amount') > 0 && <p className="text-red-500">Shortfall: {rupees(check.shortfall)}</p>}<label className="mt-3 flex gap-2"><input type="checkbox" checked={alreadySpent} onChange={e => setAlreadySpent(e.target.checked)}/>Already spent — record the actual expense</label></div>}
    {error && <p role="alert" className="text-sm text-red-500">{error}</p>}<button className={buttonClass} disabled={busy}>Save</button></form></div>;
}
