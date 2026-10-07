import type { Occurrence } from './engine';
import { string as s } from './model';

/** Display one oldest unpaid occurrence per plan. Never use this subset for reservations. */
export function nextPaymentPerPlan(items: Occurrence[]): Occurrence[] {
  const selected = new Map<string, Occurrence>();
  for (const item of [...items].sort((a, b) => s(a.data, 'date').localeCompare(s(b.data, 'date')) || a.id.localeCompare(b.id))) {
    if (item.paid || item.state === 'paid' || item.state === 'received' || item.state === 'skipped') continue;
    const planId = s(item.data, 'planId') || item.id;
    if (!selected.has(planId)) selected.set(planId, item);
  }
  return [...selected.values()];
}
