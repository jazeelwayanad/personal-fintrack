import 'fake-indexeddb/auto';
import { afterEach, describe, expect, it } from 'vitest';
import { FinanceStore } from '../src/lib/finance/store';
import { document } from '../src/lib/finance/model';
const stores: FinanceStore[] = [];
const create = (id = crypto.randomUUID(), request: typeof fetch = async () => { throw new Error('Offline'); }) => { const s = new FinanceStore(id, request); stores.push(s); return s; };
afterEach(async () => { for (const s of stores.splice(0)) { s.stop(); await s.db.delete(); } });
describe('offline queue', () => {
  it('persists local edits and outgoing queue across restart, with separate accounts', async () => {
    const id = crypto.randomUUID(), first = create(id);
    await first.save([document('preferences', 'preferences', { payday: 25, savings: 100, limitMode: 'warn', notifications: true })], false);
    first.db.close(); const reopened = create(id), other = create();
    expect((await reopened.records())[0].data.payday).toBe(25);
    expect(await reopened.db.pending.count()).toBe(1); expect(await other.records()).toEqual([]);
  });
  it('keeps rejected edits available for conflict review', async () => {
    const s = create(undefined, async () => Response.json({ accepted: false, conflicts: ['preferences'], records: [{ ...document('preferences', 'preferences', { payday: 1, savings: 0, limitMode: 'warn', notifications: true }), revision: 2 }] }));
    await s.save([document('preferences', 'preferences', { payday: 25, savings: 100, limitMode: 'warn', notifications: true })], false); await s.sync();
    expect((await s.records())[0].data.payday).toBe(25); expect((await s.db.pending.toArray())[0].conflict?.[0].revision).toBe(2);
  });
});
