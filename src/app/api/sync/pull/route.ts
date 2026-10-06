import { prisma } from '@/lib/prisma';
import { api } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { ApiError, ensureImported } from '@/lib/server/sync';
export async function GET(req: Request) { return api(async () => {
  const userId = await requireUser(req); await ensureImported(userId);
  const value = Number(new URL(req.url).searchParams.get('since') ?? 0);
  if (!Number.isFinite(value) || value < 0) throw new ApiError(400, 'Invalid cursor.');
  const since = new Date(value), serverTime = Date.now();
  const where = { userId, updatedAt: { gt: since, lte: new Date(serverTime) } };
  const [transactions, categories, paymentMethods] = await Promise.all([prisma.transaction.findMany({ where }), prisma.category.findMany({ where }), prisma.paymentMethod.findMany({ where })]);
  const mapped = (r: { id: string; createdAt: Date; updatedAt: Date; deletedAt: Date | null }) => ({ ...r, syncId: r.id, createdAt: r.createdAt.getTime(), updatedAt: r.updatedAt.getTime(), deletedAt: r.deletedAt?.getTime() ?? null });
  return { transactions: transactions.map(mapped), categories: categories.map(mapped), paymentMethods: paymentMethods.map(mapped), serverTime };
}); }
