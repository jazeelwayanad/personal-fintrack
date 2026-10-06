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
export interface Occurrence extends Document { paid: boolean; transactionId?: string; state: 'paid' | 'received' | 'skipped' | 'overdue' | 'due' | 'upcoming' }
export function occurrences(records: Document[], today: string, through: string): Occurrence[] {
  const active = records.filter(r => !r.deleted), map = new Map<string, Document>();
  for (const plan of active.filter(r => r.kind === 'plan')) {
    const p = plan.data, start = s(p, 'startDate');
    const base = new Date(start + 'T00:00:00Z');
    if (!start || !Number.isFinite(base.getTime())) continue;
    for (let i = 0; i < 1213; i++) {
      const recurrence = s(p, 'recurrence');
      if (i > 0 && recurrence === 'once') break;
      const date = day(base.getUTCFullYear() + (recurrence === 'yearly' ? i : 0), base.getUTCMonth() + (recurrence === 'monthly' ? i : 0), base.getUTCDate());
      if (date > through || (s(p, 'endDate') && date > s(p, 'endDate')) || (s(p, 'pausedAt') && date > s(p, 'pausedAt'))) break;
      const id = `${plan.id}:${date}`;
      map.set(id, { id, kind: 'occurrence', revision: 0, deleted: false, data: { planId: plan.id, name: s(p, 'name'), type: s(p, 'type'), amount: n(p, 'amount'), categoryId: s(p, 'categoryId'), date, reminders: p.reminders !== false, status: 'pending' } });
    }
  }
  for (const item of active.filter(r => r.kind === 'occurrence' && s(r.data, 'date') <= through)) map.set(item.id, item);
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
  const commitments = upcoming.filter(r => !r.paid && r.state !== 'skipped' && s(r.data, 'type') === 'expense').reduce((v, r) => v + n(r.data, 'amount'), 0);
  const budgets = active.filter(r => r.kind === 'budget').map(r => {
    const categoryId = s(r.data, 'categoryId');
    const spent = transactions.filter(t => s(t.data, 'type') === 'expense' && !s(t.data, 'occurrenceId') && s(t.data, 'categoryId') === categoryId && s(t.data, 'date') >= period.start && s(t.data, 'date') < period.end).reduce((v, t) => v + n(t.data, 'amount'), 0);
    return { id: r.id, categoryId, amount: n(r.data, 'amount'), spent, remaining: Math.max(0, n(r.data, 'amount') - spent) };
  });
  const reservedBudgets = budgets.reduce((v, b) => v + b.remaining, 0), savings = n(preferences, 'savings');
  const periodTransactions = transactions.filter(t => s(t.data, 'date') >= period.start && s(t.data, 'date') < period.end);
  return { period, preferences, balance, commitments, savings, reservedBudgets, budgets, upcoming, unallocated: balance - commitments - savings - reservedBudgets, income: periodTransactions.filter(t => s(t.data, 'type') === 'income').reduce((v, t) => v + n(t.data, 'amount'), 0), expenses: periodTransactions.filter(t => s(t.data, 'type') === 'expense').reduce((v, t) => v + n(t.data, 'amount'), 0) };
}
export function checkSpending(records: Document[], today: string, amount: number, categoryId: string) {
  const totals = summary(records, today), budget = totals.budgets.find(b => b.categoryId === categoryId);
  const cashAllowance = totals.unallocated + (budget?.remaining ?? 0);
  const maximum = Math.max(0, budget ? Math.min(budget.remaining, cashAllowance) : cashAllowance);
  return { maximum, allowed: amount > 0 && amount <= maximum, shortfall: Math.max(0, amount - maximum), remaining: maximum - amount, balanceAfter: totals.balance - amount, budgetRemaining: budget?.remaining ?? null };
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
