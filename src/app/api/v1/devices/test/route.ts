import { prisma } from '@/lib/prisma';
import { api } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { sendDevice } from '@/lib/server/notifications';
import { ApiError } from '@/lib/server/sync';
export async function POST(req: Request) { return api(async () => { const userId = await requireUser(req); const devices = await prisma.notificationDevice.findMany({ where: { userId } }); if (!devices.length) throw new ApiError(400, 'Enable notifications on a device first.'); for (const d of devices) await sendDevice(d, 'FinTrack', 'Your payment reminders are ready.'); return { success: true }; }); }
