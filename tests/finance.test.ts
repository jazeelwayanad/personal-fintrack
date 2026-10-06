import { describe, expect, it } from 'vitest';
import cases from '../fixtures/finance.json';
import { checkSpending, cycle, occurrences, reminders, summary } from '../src/lib/finance/engine';
import { Document, validateData } from '../src/lib/finance/model';
describe('shared financial scenarios', () => {
  for (const scenario of cases) it(scenario.name, () => {
    const records = scenario.records as Document[];
    expect(summary(records, scenario.today)).toMatchObject(scenario.expected);
    if (scenario.check) expect(checkSpending(records, scenario.today, scenario.check.amount, scenario.check.categoryId)).toMatchObject({ maximum: scenario.check.maximum, allowed: scenario.check.allowed, shortfall: scenario.check.shortfall });
    if (scenario.dates) expect(occurrences(records, scenario.today, scenario.through!).map(o => o.data.date)).toEqual(scenario.dates);
  });
  it('clamps payday on short months', () => { expect(cycle('2026-02-28', 31)).toEqual({ start: '2026-02-28', end: '2026-03-31' }); expect(cycle('2026-02-27', 31)).toEqual({ start: '2026-01-31', end: '2026-02-28' }); });
  it('reminds three days before and stops after payment', () => {
    expect(reminders(cases[0].records as Document[], '2026-10-07')).toHaveLength(1);
    expect(reminders(cases[0].records as Document[], '2026-10-08')).toHaveLength(0);
    expect(reminders(cases[2].records as Document[], '2026-10-10')).toHaveLength(0);
  });
  it('rejects invalid dates and fractional paise', () => { expect(() => validateData('adjustment', { amount: 1, date: '2026-02-30' })).toThrow(); expect(() => validateData('adjustment', { amount: 1, date: '2026-13-01' })).toThrow(); expect(() => validateData('budget', { amount: .5, categoryId: 'food' })).toThrow(); });
});
