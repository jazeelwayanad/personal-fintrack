import { prisma } from '@/lib/prisma';
import { api } from '@/lib/server/http';
import { ApiError } from '@/lib/server/api-error';
import { requireUser } from '@/lib/server/mobile-auth';

export async function GET(request: Request) {
  return api(async () => {
    const userId = await requireUser(request);
    const operators = (process.env.FINTRACK_OPERATOR_IDS ?? '').split(',').map(id => id.trim()).filter(Boolean);
    if (!operators.includes(userId)) throw new ApiError(404, 'Not found.');
    const recent = new Date(Date.now() - 86400000);
    const [failedReminders, stuckReminders, mcpFailures, unresolvedUpi, overdueUpi, discrepancies] = await Promise.all([
      prisma.notificationDelivery.count({ where: { status: 'failed', updatedAt: { gte: recent } } }),
      prisma.notificationDelivery.count({ where: { status: 'sending', updatedAt: { lt: new Date(Date.now() - 300000) } } }),
      prisma.mcpAuditEvent.count({ where: { createdAt: { gte: recent }, outcome: { not: 'accepted' } } }),
      prisma.upiPaymentAttempt.count({ where: { status: 'awaiting_confirmation' } }),
      prisma.upiPaymentAttempt.count({ where: { status: 'awaiting_confirmation', createdAt: { lt: recent } } }),
      prisma.$queryRaw<{ count: number }[]>`
        SELECT count(*)::int AS count
        FROM "UpiPaymentAttempt" a
        LEFT JOIN "FinancialRecord" f ON f."userId" = a."userId" AND f."id" = a."ledgerId" AND NOT f."deleted"
        WHERE a."ledgerId" IS NOT NULL AND f."revision" IS DISTINCT FROM a."recordedLedgerRevision"
      `,
    ]);
    return { failedReminders, stuckReminders, mcpFailures, unresolvedUpi, overdueUpi, upiLedgerDiscrepancies: discrepancies[0].count };
  });
}
