import 'fake-indexeddb/auto';
import { afterEach, describe, expect, it } from 'vitest';
import { FinanceStore } from '../src/lib/finance/store';
import { document } from '../src/lib/finance/model';
const stores: FinanceStore[] = [];
const create = (id = crypto.randomUUID(), request: typeof fetch = async () => { throw new Error('Offline'); }) => { const s = new FinanceStore(id, request); stores.push(s); return s; };
afterEach(async () => { for (const s of stores.splice(0)) { s.stop(); await s.db.delete(); } });
describe('offline queue', () => {
  it('uploads first-run defaults before the initial sync completes', async () => {
    const remote = new Map<string, ReturnType<typeof document>>();
    let revision = 0;
    const s = create(undefined, async (_url, options) => {
      if (options?.method === 'POST') {
        const mutation = JSON.parse(String(options.body));
        const records = mutation.changes.map((c: ReturnType<typeof document>) => ({ ...c, revision: ++revision }));
        for (const record of records) remote.set(record.id, record);
        return Response.json({ accepted: true, records });
      }
      return Response.json({ records: [...remote.values()], cursor: revision });
    });
    await s.sync();
    expect(remote.size).toBeGreaterThan(0);
    expect(await s.db.pending.count()).toBe(0);
    expect(s.status).toBe('Synced');
  });
  it('uploads an edit saved while a download is in flight', async () => {
    const pref = document('preferences', 'preferences', { payday: 1, savings: 0, limitMode: 'warn', notifications: true });
    let release!: (response: Response) => void;
    let downloading!: () => void;
    const started = new Promise<void>(resolve => { downloading = resolve; });
    const uploaded: typeof pref[] = [];
    let pulls = 0;
    const s = create(undefined, async (_url, options) => {
      if (options?.method === 'POST') {
        const mutation = JSON.parse(String(options.body));
        uploaded.push(...mutation.changes.map((c: typeof pref) => ({ ...c, revision: 1 })));
        return Response.json({ accepted: true, records: uploaded });
      }
      if (++pulls === 1) {
        downloading();
        return new Promise<Response>(resolve => { release = resolve; });
      }
      return Response.json({ records: uploaded, cursor: 1 });
    });
    const syncing = s.sync();
    await started;
    await s.save([{ ...pref, data: { ...pref.data, payday: 25 } }]);
    release(Response.json({ records: [], cursor: 0 }));
    await syncing;
    expect(uploaded).toHaveLength(1);
    expect(uploaded[0].data.payday).toBe(25);
    expect(await s.db.pending.count()).toBe(0);
    expect(s.status).toBe('Synced');
  });
  it('keeps edits queued after a server failure and retries on the next sync', async () => {
    let offline = true;
    const s = create(undefined, async (_url, options) => {
      if (offline) return Response.json({ error: 'Server unavailable' }, { status: 503 });
      if (options?.method === 'POST') {
        const mutation = JSON.parse(String(options.body));
        return Response.json({ accepted: true, records: mutation.changes.map((c: ReturnType<typeof document>) => ({ ...c, revision: 1 })) });
      }
      return Response.json({ records: [], cursor: 1 });
    });
    await s.save([document('preferences', 'preferences', { payday: 25, savings: 100, limitMode: 'warn', notifications: true })], false);
    await s.sync();
    expect(await s.db.pending.count()).toBe(1);
    expect(s.status).toBe('Server unavailable');
    offline = false;
    await s.sync();
    expect(await s.db.pending.count()).toBe(0);
    expect(s.status).toBe('Synced');
  });
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
