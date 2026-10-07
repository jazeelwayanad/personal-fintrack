import { Data, Document, defaults, number as n, string as s } from './model';
export const todayIndia = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
export function day(year: number, month: number, date: number): string {
  const last = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  return new Date(Date.UTC(year, month, Math.min(date, last))).toISOString().slice(0, 10);
}
export function cycle(today: string, payday: number) {
  const d = new Date(today + 'T00:00:00Z'), y = d.getUTCFullYear(), m = d.getUTCMonth();
  const thisPayday = day(y, m, payday);
  return today >= thisPayday ? { start: thisPayday, end: day(y, m + 1, payday) } : { start: day(y, m - 1, payday), end: thisPayday };
}
export function addDays(date: string, count: number): string { return new Date(new Date(date + 'T00:00:00Z').getTime() + count * 86400000).toISOString().slice(0, 10); }
export interface Occurrence extends Document { paid: boolean; transactionId?: string; state: 'paid' | 'received' | 'skipped' | 'overdue' | 'due' | 'upcoming' }
export function occurrences(records: Document[], today: string, through: string): Occurrence[] {
  const active = records.filter(r => !r.deleted), map = new Map<string, Document>();
  for (const plan of active.filter(r => r.kind === 'plan')) {
    const p = plan.data, start = s(p, 'startDate');
    const base = new Date(start + 'T00:00:00Z');
    if (!start || !Number.isFinite(base.getTime())) continue;
    const recurrence = s(p, 'recurrence'), recharge = s(p, 'planType') === 'recharge';
    const interval = recurrence === 'weekly' ? 7 : n(p, 'intervalDays', 1);
    let anchor = start;
    if (recharge) {
      const paidDates = active.filter(r => r.kind === 'transaction' && s(r.data, 'occurrenceId').startsWith(`${plan.id}:`)).map(r => s(r.data, 'date')).sort();
      if (paidDates.length) anchor = addDays(paidDates.at(-1)!, interval);
      const skipped = new Set(active.filter(r => r.kind === 'occurrence' && s(r.data, 'planId') === plan.id && s(r.data, 'status') === 'skipped').map(r => s(r.data, 'date')));
      while (skipped.has(anchor)) anchor = addDays(anchor, interval);
    }
    for (let i = 0; i <= 36890; i++) {
      if (i > 0 && recurrence === 'once') break;
      const date = recurrence === 'custom' || recurrence === 'weekly'
        ? (recharge && i > 0 ? addDays(anchor < today ? today : anchor, interval * i) : addDays(anchor, interval * i))
        : day(base.getUTCFullYear() + (recurrence === 'yearly' ? i : 0), base.getUTCMonth() + (recurrence === 'monthly' ? i : 0), base.getUTCDate());
      if (date > through || date > '2100-12-31' || (s(p, 'endDate') && date > s(p, 'endDate')) || (s(p, 'pausedAt') && date > s(p, 'pausedAt'))) break;
      const id = `${plan.id}:${date}`;
      map.set(id, { id, kind: 'occurrence', revision: 0, deleted: false, data: { planId: plan.id, name: s(p, 'name'), type: s(p, 'type'), amount: n(p, 'amount'), categoryId: s(p, 'categoryId'), date, reminders: p.reminders !== false, status: 'pending' } });
    }
  }
  for (const item of active.filter(r => r.kind === 'occurrence' && s(r.data, 'date') <= through)) { const plan = active.find(p => p.id === s(item.data, 'planId') && p.kind === 'plan'); if (s(plan?.data ?? {}, 'planType') !== 'recharge' || s(item.data, 'status') === 'skipped' || active.some(t => t.kind === 'transaction' && s(t.data, 'occurrenceId') === item.id) || map.has(item.id)) map.set(item.id, item); }
  const payments = new Map(active.filter(r => r.kind === 'transaction' && s(r.data, 'occurrenceId')).map(r => [s(r.data, 'occurrenceId'), r]));
  return [...map.values()].map(item => {
    const transaction = payments.get(item.id), date = s(item.data, 'date');
    const paid = !!transaction;
    const state: Occurrence['state'] = paid ? (s(item.data, 'type') === 'income' ? 'received' : 'paid') : s(item.data, 'status') === 'skipped' ? 'skipped' : date < today ? 'overdue' : date === today ? 'due' : 'upcoming';
    return { ...item, paid, transactionId: transaction?.id, state };
  }).sort((a, b) => s(a.data, 'date').localeCompare(s(b.data, 'date')) || a.id.localeCompare(b.id));
}
export function summary(records: Document[], today: string) {
  const active = records.filter(r => !r.deleted);
  const preferences = active.find(r => r.kind === 'preferences')?.data ?? defaults;
  const period = cycle(today, n(preferences, 'payday', 1));
  const transactions = active.filter(r => r.kind === 'transaction' && s(r.data, 'date') <= today);
  const balance = transactions.reduce((v, r) => v + n(r.data, 'amount') * (s(r.data, 'type') === 'income' ? 1 : -1), 0) + active.filter(r => r.kind === 'adjustment' && s(r.data, 'date') <= today).reduce((v, r) => v + n(r.data, 'amount'), 0);
  const upcoming = occurrences(records, today, period.end);
  const outstanding = upcoming.filter(r => !r.paid && r.state !== 'skipped' && s(r.data, 'type') === 'expense' && s(r.data, 'date') < period.end);
  const commitments = outstanding.reduce((v, r) => v + n(r.data, 'amount'), 0);
  const manual = active.filter(r => r.kind === 'budget');
  const categoryIds = new Set([...manual.map(r => s(r.data, 'categoryId')), ...active.filter(r => r.kind === 'plan' && s(r.data, 'type') === 'expense').map(r => s(r.data, 'categoryId'))]);
  const budgets = [...categoryIds].map(categoryId => {
    const entry = manual.find(r => s(r.data, 'categoryId') === categoryId);
    const planned = upcoming.filter(o => o.state !== 'skipped' && s(o.data, 'type') === 'expense' && s(o.data, 'categoryId') === categoryId && s(o.data, 'date') >= period.start && s(o.data, 'date') < period.end).reduce((v, o) => v + n(o.data, 'amount'), 0);
    const spent = transactions.filter(t => s(t.data, 'type') === 'expense' && s(t.data, 'categoryId') === categoryId && s(t.data, 'date') >= period.start && s(t.data, 'date') < period.end).reduce((v, t) => v + n(t.data, 'amount'), 0);
    const outstandingAmount = outstanding.filter(o => s(o.data, 'categoryId') === categoryId).reduce((v, o) => v + n(o.data, 'amount'), 0);
    const amount = Math.max(n(entry?.data ?? {}, 'amount'), planned), remaining = amount - spent;
    return { id: `budget:${categoryId}`, categoryId, amount, manual: entry ? n(entry.data, 'amount') : null, source: entry ? 'manual' : 'plans', planned, spent, remaining, outstanding: outstandingAmount, reserve: Math.max(0, remaining - outstandingAmount) };
  });
  const reservedBudgets = budgets.reduce((v, b) => v + b.reserve, 0), savings = n(preferences, 'savings');
  const periodTransactions = transactions.filter(t => s(t.data, 'date') >= period.start && s(t.data, 'date') < period.end);
  return { period, preferences, balance, commitments, savings, reservedBudgets, budgets, upcoming, unallocated: balance - commitments - savings - reservedBudgets, income: periodTransactions.filter(t => s(t.data, 'type') === 'income').reduce((v, t) => v + n(t.data, 'amount'), 0), expenses: periodTransactions.filter(t => s(t.data, 'type') === 'expense').reduce((v, t) => v + n(t.data, 'amount'), 0) };
}
export function checkSpending(records: Document[], today: string, amount: number, categoryId: string) {
  const totals = summary(records, today), budget = totals.budgets.find(b => b.categoryId === categoryId);
  const cashAllowance = totals.unallocated + (budget?.reserve ?? 0);
  const maximum = Math.max(0, budget ? Math.min(budget.reserve, cashAllowance) : cashAllowance);
  return { maximum, allowed: amount > 0 && amount <= maximum, shortfall: Math.max(0, amount - maximum), remaining: maximum - amount, balanceAfter: totals.balance - amount, budgetRemaining: budget?.remaining ?? null };
}
export function monthlyForecast(records: Document[], today: string, month: string) {
  const start = month + '-01', d = new Date(start + 'T00:00:00Z'), end = day(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
  const items = occurrences(records, today, end).filter(o => o.state !== 'skipped' && s(o.data, 'date') >= start && s(o.data, 'date') < end);
  return { start, end, items, count: items.length, expenses: items.filter(o => s(o.data, 'type') === 'expense').reduce((sum, o) => sum + n(o.data, 'amount'), 0), income: items.filter(o => s(o.data, 'type') === 'income').reduce((sum, o) => sum + n(o.data, 'amount'), 0) };
}
export function reminders(records: Document[], today: string) {
  if (records.find(r => !r.deleted && r.kind === 'preferences')?.data.notifications === false) return [];
  const inThreeDays = new Date(new Date(today + 'T00:00:00Z').getTime() + 3 * 86400000).toISOString().slice(0, 10);
  return occurrences(records, today, inThreeDays).filter(r => !r.paid && r.state !== 'skipped' && r.data.reminders !== false && (s(r.data, 'date') <= today || s(r.data, 'date') === inThreeDays));
}
export const rupees = (paise: number) => new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 }).format(paise / 100);
export function snapshotPast(records: Document[], planId: string, today: string): Document[] { return occurrences(records, today, today).filter(o => s(o.data, 'planId') === planId && !records.some(r => r.id === o.id)).map(({ id, kind, data, revision, deleted }) => ({ id, kind, data, revision, deleted })); }
export function seedRecords(makeId: () => string): Document[] {
  const doc = (kind: Document['kind'], data: Data) => ({ id: makeId(), kind, data, revision: 0, deleted: false });
  return [doc('category', { name: 'Salary', type: 'income', color: '#22c55e', icon: '' }), ...['Food', 'Transport', 'Shopping', 'Bills'].map(name => doc('category', { name, type: 'expense', color: '#8b5cf6', icon: '' })), ...['Cash', 'Bank account', 'Card'].map(name => doc('paymentMethod', { name, icon: '' }))];
}
