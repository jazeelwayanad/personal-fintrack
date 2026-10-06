import Dexie, { type Table } from 'dexie';
import { Document, Mutation, validateData } from './model';
import { seedRecords } from './engine';
export interface Pending { id: string; sequence?: number; mutation: Mutation; conflict?: Document[]; error?: string }
export class FinanceDatabase extends Dexie {
  documents!: Table<Document, string>;
  pending!: Table<Pending, number>;
  meta!: Table<{ key: string; value: string | number }, string>;
  constructor(userId: string) {
    super(`FinTrack-v3-${userId}`);
    this.version(1).stores({ documents: 'id,kind,revision', pending: '++sequence,id', meta: 'key' });
  }
}
export class FinanceStore {
  db: FinanceDatabase;
  status = 'Ready';
  private running?: Promise<void>;
  private stopped = false;
  private listeners = new Set<() => void>();
  constructor(userId: string, private request: typeof fetch = (...args) => fetch(...args)) { this.db = new FinanceDatabase(userId); }
  listen(fn: () => void) { this.listeners.add(fn); return () => { this.listeners.delete(fn); }; }
  private notify() { this.listeners.forEach(fn => fn()); }
  async records() { return this.db.documents.toArray(); }
  async save(records: Document[], autoSync = true) {
    const mutation: Mutation = { id: crypto.randomUUID(), changes: [] };
    await this.db.transaction('rw', this.db.documents, this.db.pending, async () => {
      for (const record of records) {
        const existing = await this.db.documents.get(record.id);
        const data = validateData(record.kind, record.data);
        const doc = { ...record, data, revision: existing?.revision ?? 0 };
        mutation.changes.push({ id: doc.id, kind: doc.kind, data, deleted: doc.deleted, baseRevision: doc.revision });
        await this.db.documents.put(doc);
      }
      await this.db.pending.add({ id: mutation.id, mutation });
    });
    this.notify();
    if (autoSync) void this.sync();
  }
  async resolve(sequence: number, keepLocal: boolean) {
    await this.db.transaction('rw', this.db.pending, this.db.documents, async () => {
      const pending = await this.db.pending.get(sequence);
      if (!pending) return;
      const remote = new Map((pending.conflict ?? []).map(r => [r.id, r]));
      if (keepLocal) {
        pending.mutation.id = crypto.randomUUID(); pending.id = pending.mutation.id;
        pending.mutation.changes = pending.mutation.changes.map(c => ({ ...c, baseRevision: remote.get(c.id)?.revision ?? 0 }));
        delete pending.conflict; delete pending.error;
        await this.db.pending.put(pending);
      } else {
        const ids = new Set(pending.mutation.changes.map(c => c.id));
        const queue = await this.db.pending.toArray();
        // Dependent local edits must be discarded together, never silently replayed.
        for (const q of queue) if (q.sequence! >= sequence && q.mutation.changes.some(c => ids.has(c.id))) {
          q.mutation.changes.forEach(c => ids.add(c.id)); await this.db.pending.delete(q.sequence!);
        }
        // Reload a full server snapshot; preserve unrelated queued documents.
        for (const id of ids) await this.db.documents.delete(id);
      }
    });
    await this.db.meta.put({ key: 'cursor', value: 0 });
    await this.sync(); this.notify();
  }
  sync(): Promise<void> {
    if (this.stopped) return Promise.resolve();
    if (this.running) return this.running;
    this.running = this.performSync().finally(() => { this.running = undefined; this.notify(); });
    return this.running;
  }
  private async performSync() {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) { this.status = 'Offline · changes saved on this device'; return; }
    this.status = 'Syncing'; this.notify();
    try {
      for (;;) {
        if (this.stopped) return;
        const pending = await this.db.pending.orderBy('sequence').first();
        if (!pending) break;
        if (pending.conflict || pending.error) { this.status = 'Review a sync conflict in Settings'; return; }
        const response = await this.request('/api/v1/sync', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(pending.mutation) });
        const result = await response.json();
        if (!response.ok) {
          if (response.status === 400 || response.status === 409) { await this.db.pending.update(pending.sequence!, { error: result.error, conflict: result.records ?? [] }); }
          throw new Error(result.error ?? 'Sync failed');
        }
        if (!result.accepted) { await this.db.pending.update(pending.sequence!, { conflict: result.records }); this.status = 'Review a sync conflict in Settings'; return; }
        await this.db.transaction('rw', this.db.documents, this.db.pending, async () => {
          await this.db.pending.delete(pending.sequence!);
          const later = await this.db.pending.toArray();
          for (const record of result.records as Document[]) {
            let hasLater = false;
            for (const q of later) {
              let changed = false;
              for (const c of q.mutation.changes) if (c.id === record.id) { c.baseRevision = record.revision; changed = true; hasLater = true; }
              if (changed) await this.db.pending.put(q);
            }
            if (hasLater) await this.db.documents.update(record.id, { revision: record.revision });
            else await this.db.documents.put(record);
          }
        });
      }
      const cursor = (await this.db.meta.get('cursor'))?.value ?? 0;
      const response = await this.request(`/api/v1/sync?since=${cursor}`);
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? 'Sync failed');
      await this.db.transaction('rw', this.db.documents, this.db.pending, this.db.meta, async () => {
        const pendingIds = new Set((await this.db.pending.toArray()).flatMap(p => p.mutation.changes.map(c => c.id)));
        for (const record of result.records as Document[]) if (!pendingIds.has(record.id)) await this.db.documents.put(record);
        await this.db.meta.bulkPut([{ key: 'cursor', value: result.cursor }, { key: 'lastSync', value: Date.now() }]);
      });
      if (await this.db.documents.count() === 0) { await this.save(seedRecords(() => crypto.randomUUID()), false); this.status = 'Initial categories ready'; }
      else this.status = 'Synced';
    } catch (e) { this.status = e instanceof Error ? e.message : 'Sync unavailable'; }
  }
  stop() { this.stopped = true; }
}
