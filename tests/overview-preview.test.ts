import { describe, expect, it } from 'vitest';
import { occurrences, summary } from '../src/lib/finance/engine';
import { document, type Document } from '../src/lib/finance/model';
import { sampleRecords, previewToday } from '../design-preview/data';
import { nextPaymentPerPlan } from '../src/lib/finance/presentation';

const today = '2026-10-07';
function plan(id: string, extra: Record<string, unknown> = {}) {
  return document(id, 'plan', { name: id, type: 'expense', planType: 'subscription', amount: 10000, categoryId: 'bills', startDate: '2026-09-05', recurrence: 'monthly', reminders: true, ...extra });
}
function payment(planId: string, date: string) {
  return document(`${planId}-paid-${date}`, 'transaction', { type: 'expense', amount: 10000, categoryId: 'bills', paymentMethodId: 'cash', date, description: '', occurrenceId: `${planId}:${date}` });
}
const schedule = (records: Document[]) => occurrences(records, today, '2026-12-31');

describe('Payment schedule: one next unpaid occurrence per plan', () => {
  it('selects the oldest overdue occurrence and keeps different plans separate', () => {
    const items = schedule([plan('rent'), plan('internet', { startDate: today }), plan('salary', { startDate: '2026-11-01', type: 'income', planType: 'salary' })]);
    expect(nextPaymentPerPlan([...items].reverse()).map(item => [item.data.planId, item.data.date, item.state])).toEqual([
      ['rent', '2026-09-05', 'overdue'], ['internet', today, 'due'], ['salary', '2026-11-01', 'upcoming'],
    ]);
  });
  it('advances after payment and skipping, excluding paid/received occurrences', () => {
    const records = [plan('rent'), payment('rent', '2026-09-05')];
    expect(nextPaymentPerPlan(schedule(records))[0].data.date).toBe('2026-10-05');
    const occurrence = schedule(records).find(item => item.id === 'rent:2026-10-05')!;
    records.push(document(occurrence.id, 'occurrence', { ...occurrence.data, status: 'skipped' }));
    expect(nextPaymentPerPlan(schedule(records))[0].data.date).toBe('2026-11-05');
    const incomeRecords = [plan('salary', { startDate: '2026-10-01', type: 'income', planType: 'salary' }), document('salary-paid', 'transaction', { type: 'income', amount: 10000, categoryId: 'salary', paymentMethodId: 'bank', date: '2026-10-01', occurrenceId: 'salary:2026-10-01' })];
    expect(nextPaymentPerPlan(schedule(incomeRecords))[0].data.date).toBe('2026-11-01');
  });
  it('does not invent future occurrences for paused plans, but keeps unpaid past payments', () => {
    const unpaid = [plan('paused', { pausedAt: '2026-09-15' })];
    expect(nextPaymentPerPlan(schedule(unpaid)).map(item => item.data.date)).toEqual(['2026-09-05']);
    expect(nextPaymentPerPlan(schedule([...unpaid, payment('paused', '2026-09-05')]))).toEqual([]);
  });
  it('omits completed one-off and ended plans when all occurrences are paid', () => {
    expect(nextPaymentPerPlan(schedule([plan('once', { recurrence: 'once' }), payment('once', '2026-09-05'), plan('ended', { endDate: '2026-09-30' }), payment('ended', '2026-09-05')]))).toEqual([]);
  });
  it('filters presentation without mutating full occurrences or financial totals', () => {
    const records = [plan('rent'), plan('internet', { startDate: today })];
    const items = schedule(records), before = structuredClone(items), totals = summary(records, today);
    expect(nextPaymentPerPlan(items)).toHaveLength(2);
    expect(items).toEqual(before);
    expect(summary(records, today)).toEqual(totals);
    expect(totals.commitments).toBe(30000); // Both overdue rent bills remain reserved.
  });
  it('keeps sample figures coherent and shows exactly four distinct plans', () => {
    expect(summary(sampleRecords, previewToday)).toMatchObject({ balance: 6540000, commitments: 1354800, savings: 800000, reservedBudgets: 440000, unallocated: 3945200 });
    const next = nextPaymentPerPlan(occurrences(sampleRecords, previewToday, '2100-12-31'));
    expect(next).toHaveLength(4);
    expect(new Set(next.map(item => item.data.planId)).size).toBe(4);
  });
});
