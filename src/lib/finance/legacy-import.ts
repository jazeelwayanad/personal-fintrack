import { db } from '@/lib/db';
import { FinanceStore } from './store';
import { document, Document } from './model';
export async function importLegacy(store: FinanceStore) {
  const existing = new Set((await store.records()).map(r => r.id));
  const docs: Document[] = [];
  for (const c of await db.categories.toArray()) if (!c.deletedAt && !existing.has(c.syncId)) docs.push(document(c.syncId, 'category', { name: c.name, type: c.type, color: c.color, icon: c.icon }));
  for (const p of await db.paymentMethods.toArray()) if (!p.deletedAt && !existing.has(p.syncId)) docs.push(document(p.syncId, 'paymentMethod', { name: p.name, icon: p.icon }));
  for (const t of await db.transactions.toArray()) if (!t.deletedAt && !existing.has(t.syncId)) docs.push(document(t.syncId, 'transaction', { type: t.type, amount: Math.round(t.amount * 100), categoryId: t.categoryId, paymentMethodId: t.paymentMethodId, date: t.date, description: t.description ?? '' }));
  for (let i = 0; i < docs.length; i += 400) await store.save(docs.slice(i, i + 400));
  return docs.length;
}
