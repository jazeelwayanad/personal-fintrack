import { requireFinanceCapability } from '@/lib/server/finance-capability';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { pull, push, ApiError } from '@/lib/server/sync';
import { Change } from '@/lib/finance/model';
const item = z.object({ syncId: z.string(), deletedAt: z.number().nullable().optional() }).passthrough();
const schema = z.object({ transactions: z.array(item).default([]), categories: z.array(item).default([]), paymentMethods: z.array(item).default([]) });
export async function POST(req: Request) { return api(async () => {
  const userId = await requireUser(req); requireFinanceCapability(req); const input = schema.parse(await body(req));
  const current = await pull(userId, 0), byId = new Map(current.records.map(r => [r.id, r]));
  const changes: Change[] = [];
  for (const c of input.categories) changes.push({ id: c.syncId, kind: 'category', baseRevision: byId.get(c.syncId)?.revision ?? 0, deleted: !!c.deletedAt, data: { name: c.name, type: c.type, color: c.color, icon: c.icon ?? '' } });
  for (const p of input.paymentMethods) changes.push({ id: p.syncId, kind: 'paymentMethod', baseRevision: byId.get(p.syncId)?.revision ?? 0, deleted: !!p.deletedAt, data: { name: p.name, icon: p.icon ?? '' } });
  for (const t of input.transactions) changes.push({ id: t.syncId, kind: 'transaction', baseRevision: byId.get(t.syncId)?.revision ?? 0, deleted: !!t.deletedAt, data: { ...byId.get(t.syncId)?.data, type: t.type, amount: Math.round(Number(t.amount) * 100), categoryId: t.categoryId, paymentMethodId: t.paymentMethodId, date: t.date, description: t.description ?? '' } });
  if (!changes.length) return { success: true };
  const result = await push(userId, { id: randomUUID(), changes });
  if (!result.accepted) throw new ApiError(409, 'Please sync and retry.');
  return { success: true };
}); }
