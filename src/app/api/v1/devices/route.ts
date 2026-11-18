import { z } from 'zod';
import { Prisma } from '@prisma/client';
import { prisma } from '@/lib/prisma';
import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { ApiError } from '@/lib/server/api-error';
const schema = z.object({ id: z.string().uuid(), platform: z.enum(['web', 'android']), token: z.string().min(20).max(4096).optional(), subscription: z.object({ endpoint: z.string().url(), keys: z.object({ auth: z.string().min(1), p256dh: z.string().min(1) }) }).optional() });
export async function GET(req: Request) { return api(async () => { await requireUser(req); return { publicKey: process.env.NEXT_PUBLIC_WEB_PUSH_KEY ?? null, androidConfigured: !!process.env.FIREBASE_SERVICE_ACCOUNT }; }); }
export async function POST(req: Request) { return api(async () => {
  const userId = await requireUser(req), data = schema.parse(await body(req));
  if (data.platform === 'web') {
    if (!data.subscription) throw new ApiError(400, 'Missing subscription.');
    const url = new URL(data.subscription.endpoint);
    if (url.protocol !== 'https:' || !['fcm.googleapis.com', 'updates.push.services.mozilla.com', 'web.push.apple.com', 'notify.windows.com'].some(host => url.hostname === host || url.hostname.endsWith('.' + host))) throw new ApiError(400, 'Unsupported push provider.');
  } else if (!data.token) throw new ApiError(400, 'Missing notification token.');
  const fields = { platform: data.platform, token: data.token ?? null, subscription: data.subscription ? data.subscription as Prisma.InputJsonValue : Prisma.JsonNull };
  try {
    await prisma.$transaction(async tx => {
      await tx.notificationDevice.createMany({ data: [{ id: data.id, userId, ...fields }], skipDuplicates: true });
      const updated = await tx.notificationDevice.updateMany({ where: { id: data.id, userId }, data: fields });
      if (updated.count === 0) throw new ApiError(409, 'This device is already registered.');
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw new ApiError(409, 'This device is already registered.');
    throw error;
  }
  return { success: true };
}); }
export async function DELETE(req: Request) { return api(async () => { const userId = await requireUser(req); const { id } = z.object({ id: z.string() }).parse(await body(req)); await prisma.notificationDevice.deleteMany({ where: { id, userId } }); return { success: true }; }); }
