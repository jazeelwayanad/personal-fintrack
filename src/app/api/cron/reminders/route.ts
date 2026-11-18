import { measure } from '@/lib/server/metrics';
import { prisma } from '@/lib/prisma';
import { retryFeedbackEmails } from '@/lib/server/feedback-email';
import { api } from '@/lib/server/http';
import { ApiError } from '@/lib/server/api-error';
import { dailyReminders } from '@/lib/server/notifications';
export const runtime = 'nodejs';
export const maxDuration = 60;
export async function GET(req: Request) { return api(() => measure('cron.reminders', async () => { if (!process.env.CRON_SECRET || req.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) throw new ApiError(401, 'Unauthorized.'); const [reminders] = await Promise.all([dailyReminders(), retryFeedbackEmails(), prisma.authAttempt.deleteMany({ where: { expiresAt: { lt: new Date() } } }), prisma.accountToken.deleteMany({ where: { expiresAt: { lt: new Date() } } })]); return reminders; })); }
