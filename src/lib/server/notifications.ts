import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import webpush from 'web-push';
import { prisma } from '@/lib/prisma';
import { reminders, todayIndia } from '@/lib/finance/engine';
import { string as s } from '@/lib/finance/model';
import { wire, ApiError } from './sync';
export async function sendDevice(device: { platform: string; token: string | null; subscription: unknown }, title: string, body: string, url = '/plans') {
  if (device.platform === 'android') {
    if (!process.env.FIREBASE_SERVICE_ACCOUNT) throw new ApiError(503, 'Firebase notifications are not configured yet.');
    if (!getApps().length) initializeApp({ credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)) });
    await getMessaging().send({ token: device.token!, notification: { title, body }, data: { route: url }, android: { priority: 'high', notification: { channelId: 'fintrack_reminders' } } });
  } else {
    const publicKey = process.env.NEXT_PUBLIC_WEB_PUSH_KEY, privateKey = process.env.WEB_PUSH_PRIVATE_KEY;
    if (!publicKey || !privateKey || !process.env.WEB_PUSH_SUBJECT) throw new ApiError(503, 'Browser notifications are not configured yet.');
    await webpush.sendNotification(device.subscription as webpush.PushSubscription, JSON.stringify({ title, body, url }), { vapidDetails: { subject: process.env.WEB_PUSH_SUBJECT, publicKey, privateKey } });
  }
}
export async function dailyReminders(date = todayIndia()) {
  const users = await prisma.user.findMany({ where: { devices: { some: {} } }, select: { id: true } });
  let sent = 0, failed = 0;
  for (const user of users) {
    const records = (await prisma.financialRecord.findMany({ where: { userId: user.id } })).map(wire);
    const items = reminders(records, date);
    if (!items.length) continue;
    for (const device of await prisma.notificationDevice.findMany({ where: { userId: user.id } })) {
      const id = `${device.id}:${date}`;
      await prisma.notificationDelivery.createMany({ data: [{ id, userId: user.id, deviceId: device.id, date, status: 'pending' }], skipDuplicates: true });
      const claimed = await prisma.notificationDelivery.updateMany({ where: { id, status: { in: ['pending', 'failed'] }, attempts: { lt: 3 } }, data: { status: 'sending', attempts: { increment: 1 } } });
      if (!claimed.count) continue;
      try {
        await sendDevice(device, 'FinTrack payment reminders', `${items.length} payment${items.length === 1 ? '' : 's'} to review: ${items.slice(0, 3).map(o => s(o.data, 'name')).join(', ')}`, `/plans?occurrence=${encodeURIComponent(items[0].id)}`);
        await prisma.notificationDelivery.update({ where: { id }, data: { status: 'sent', lastError: null } }); sent++;
      } catch (error) {
        const e = error as { code?: string; statusCode?: number; message?: string };
        if (e.code === 'messaging/registration-token-not-registered' || e.code === 'messaging/invalid-registration-token' || e.statusCode === 404 || e.statusCode === 410) await prisma.notificationDevice.deleteMany({ where: { id: device.id } });
        await prisma.notificationDelivery.update({ where: { id }, data: { status: 'failed', lastError: (e.code ?? 'delivery-failed').slice(0, 100) } }); failed++;
      }
    }
  }
  return { sent, failed };
}
