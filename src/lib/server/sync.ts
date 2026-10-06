import { Prisma } from '@prisma/client';
import { prisma } from '@/lib/prisma';
import { Data, Document, Mutation, mutationSchema, validateData, string as s, number as n } from '@/lib/finance/model';

type Tx = Prisma.TransactionClient;
export class ApiError extends Error { constructor(public status: number, message: string) { super(message) } }
const json = (value: unknown) => value as Prisma.InputJsonValue;
export function wire(r: { id: string; kind: string; data: unknown; revision: number; deleted: boolean }): Document { return { id: r.id, kind: r.kind as Document['kind'], data: r.data as Data, revision: r.revision, deleted: r.deleted } }
async function lock(tx: Tx, userId: string) { await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${userId} FOR UPDATE`; }
export async function ensureImported(userId: string) {
  await prisma.$transaction(async tx => {
    await lock(tx, userId);
    const user = await tx.user.findUniqueOrThrow({ where: { id: userId } });
    if (user.syncImported) return;
    const [transactions, categories, methods] = await Promise.all([tx.transaction.findMany({ where: { userId } }), tx.category.findMany({ where: { userId } }), tx.paymentMethod.findMany({ where: { userId } })]);
    const docs: Document[] = [
      ...categories.map(c => ({ id: c.id, kind: 'category' as const, data: { name: c.name, type: c.type, color: c.color, icon: c.icon }, revision: 1, deleted: !!c.deletedAt })),
      ...methods.map(p => ({ id: p.id, kind: 'paymentMethod' as const, data: { name: p.name, icon: p.icon }, revision: 1, deleted: !!p.deletedAt })),
      ...transactions.map(t => ({ id: t.id, kind: 'transaction' as const, data: { type: t.type, amount: Math.round(t.amount * 100), categoryId: t.categoryId, paymentMethodId: t.paymentMethodId, date: t.date, description: t.description ?? '' }, revision: 1, deleted: !!t.deletedAt })),
    ];
    for (const d of docs) await tx.financialRecord.create({ data: { ...d, userId, data: json(d.data) } });
    await tx.user.update({ where: { id: userId }, data: { syncImported: true, syncRevision: docs.length ? 1 : 0 } });
  });
}
function validateReferences(records: Document[], changed: Document[]) {
  const map = new Map(records.filter(r => !r.deleted).map(r => [r.id, r]));
  for (const r of changed) {
    if (r.deleted) {
      if (['category', 'paymentMethod'].includes(r.kind) && records.some(x => !x.deleted && (s(x.data, 'categoryId') === r.id || s(x.data, 'paymentMethodId') === r.id))) throw new ApiError(400, 'This item is still in use. Reassign its transactions and plans first.');
      continue;
    }
    const d = r.data;
    if (['transaction', 'plan', 'occurrence', 'budget'].includes(r.kind)) {
      const category = map.get(s(d, 'categoryId'));
      if (!category || category.kind !== 'category' || s(category.data, 'type') !== (r.kind === 'budget' ? 'expense' : s(d, 'type'))) throw new ApiError(400, 'Choose a valid category of the same type.');
    }
    if (r.kind === 'budget' && r.id !== `budget:${s(d, 'categoryId')}`) throw new ApiError(400, 'Invalid budget identity.');
    if (r.kind === 'preferences' && r.id !== 'preferences') throw new ApiError(400, 'Invalid preferences identity.');
    if (r.kind === 'transaction') {
      if (map.get(s(d, 'paymentMethodId'))?.kind !== 'paymentMethod') throw new ApiError(400, 'Choose a valid payment method.');
      if (s(d, 'occurrenceId')) {
        const occurrence = map.get(s(d, 'occurrenceId'));
        if (!occurrence || occurrence.kind !== 'occurrence' || s(occurrence.data, 'type') !== s(d, 'type') || s(occurrence.data, 'status') === 'skipped') throw new ApiError(400, 'Invalid scheduled payment.');
        if (records.some(t => !t.deleted && t.kind === 'transaction' && t.id !== r.id && s(t.data, 'occurrenceId') === s(d, 'occurrenceId'))) throw new ApiError(409, 'This payment has already been recorded. Sync and review it.');
      }
    }
    if (r.kind === 'occurrence') {
      if (map.get(s(d, 'planId'))?.kind !== 'plan' || r.id !== `${s(d, 'planId')}:${s(d, 'date')}`) throw new ApiError(400, 'Invalid occurrence identity.');
      if (s(d, 'status') === 'skipped' && records.some(t => !t.deleted && t.kind === 'transaction' && s(t.data, 'occurrenceId') === r.id)) throw new ApiError(400, 'Remove the linked payment before skipping this occurrence.');
    }
  }
}
async function mirror(tx: Tx, userId: string, d: Document) {
  const v = d.data, deletedAt = d.deleted ? new Date() : null, now = new Date();
  if (d.kind === 'transaction') {
    const existing = await tx.transaction.findUnique({ where: { id: d.id } });
    if (existing && existing.userId !== userId) throw new ApiError(403, 'Record belongs to another account.');
    const fields = { type: s(v, 'type'), amount: n(v, 'amount') / 100, categoryId: s(v, 'categoryId'), paymentMethodId: s(v, 'paymentMethodId'), date: s(v, 'date'), description: s(v, 'description'), updatedAt: now, deletedAt };
    await tx.transaction.upsert({ where: { id: d.id }, create: { id: d.id, userId, createdAt: now, ...fields }, update: fields });
  } else if (d.kind === 'category') {
    const existing = await tx.category.findUnique({ where: { id: d.id } });
    if (existing && existing.userId !== userId) throw new ApiError(403, 'Record belongs to another account.');
    const fields = { name: s(v, 'name'), type: s(v, 'type'), color: s(v, 'color'), icon: s(v, 'icon'), updatedAt: now, deletedAt };
    await tx.category.upsert({ where: { id: d.id }, create: { id: d.id, userId, createdAt: now, ...fields }, update: fields });
  } else if (d.kind === 'paymentMethod') {
    const existing = await tx.paymentMethod.findUnique({ where: { id: d.id } });
    if (existing && existing.userId !== userId) throw new ApiError(403, 'Record belongs to another account.');
    const fields = { name: s(v, 'name'), icon: s(v, 'icon'), updatedAt: now, deletedAt };
    await tx.paymentMethod.upsert({ where: { id: d.id }, create: { id: d.id, userId, createdAt: now, ...fields }, update: fields });
  }
}
export type SyncResult = { accepted: boolean; records: Document[]; conflicts?: string[] };
export async function push(userId: string, input: unknown): Promise<SyncResult> {
  const mutation: Mutation = mutationSchema.parse(input);
  if (new Set(mutation.changes.map(c => c.id)).size !== mutation.changes.length) throw new ApiError(400, 'Duplicate records in mutation.');
  await ensureImported(userId);
  return prisma.$transaction(async tx => {
    await lock(tx, userId);
    const previous = await tx.syncMutation.findUnique({ where: { userId_id: { userId, id: mutation.id } } });
    if (previous) return previous.result as unknown as SyncResult;
    const rows = (await tx.financialRecord.findMany({ where: { userId } })).map(wire);
    const byId = new Map(rows.map(r => [r.id, r]));
    const conflicts = mutation.changes.filter(c => (byId.get(c.id)?.revision ?? 0) !== c.baseRevision || (byId.has(c.id) && byId.get(c.id)!.kind !== c.kind)).map(c => c.id);
    if (conflicts.length) return { accepted: false, records: mutation.changes.flatMap(c => byId.has(c.id) ? [byId.get(c.id)!] : []), conflicts };
    const user = await tx.user.update({ where: { id: userId }, data: { syncRevision: { increment: 1 } } });
    const changed: Document[] = mutation.changes.map(c => ({ id: c.id, kind: c.kind, data: validateData(c.kind, c.data), deleted: c.deleted, revision: user.syncRevision }));
    for (const r of changed) byId.set(r.id, r);
    validateReferences([...byId.values()], changed);
    // Clear changed links first, allowing atomic unlink/relink without a transient unique conflict.
    await tx.financialRecord.updateMany({ where: { userId, id: { in: changed.map(r => r.id) } }, data: { occurrenceKey: null } });
    for (const r of changed) {
      const fields = { kind: r.kind, data: json(r.data), deleted: r.deleted, revision: r.revision, occurrenceKey: !r.deleted && r.kind === 'transaction' ? s(r.data, 'occurrenceId') || null : null };
      await tx.financialRecord.upsert({ where: { userId_id: { userId, id: r.id } }, create: { userId, id: r.id, ...fields }, update: fields });
      await mirror(tx, userId, r);
    }
    const result = { accepted: true, records: changed };
    await tx.syncMutation.create({ data: { userId, id: mutation.id, result: json(result) } });
    return result;
  }, { timeout: 15000 });
}
export async function pull(userId: string, since: number) {
  if (!Number.isSafeInteger(since) || since < 0) throw new ApiError(400, 'Invalid sync cursor.');
  await ensureImported(userId);
  return prisma.$transaction(async tx => {
    await lock(tx, userId);
    const user = await tx.user.findUniqueOrThrow({ where: { id: userId } });
    if (since > user.syncRevision) throw new ApiError(409, 'Sync cursor is ahead of server.');
    const records = (await tx.financialRecord.findMany({ where: { userId, revision: { gt: since } }, orderBy: { revision: 'asc' } })).map(wire);
    return { records, cursor: user.syncRevision };
  });
}
