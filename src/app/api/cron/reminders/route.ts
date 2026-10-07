import { retryFeedbackEmails } from '@/lib/server/feedback-email';
import { api } from '@/lib/server/http';
import { ApiError } from '@/lib/server/sync';
import { dailyReminders } from '@/lib/server/notifications';
export const runtime = 'nodejs';
export const maxDuration = 60;
export async function GET(req: Request) { return api(async () => { if (!process.env.CRON_SECRET || req.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) throw new ApiError(401, 'Unauthorized.'); const [reminders] = await Promise.all([dailyReminders(), retryFeedbackEmails()]); return reminders; }); }
