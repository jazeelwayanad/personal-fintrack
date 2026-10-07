import { z } from 'zod';
import { prisma } from '@/lib/prisma';
import { ApiError } from './sync';
const schema = z.object({
  id: z.string().uuid(),
  topic: z.enum(['suggestion', 'issue', 'other']),
  message: z.string().trim().min(10, 'Please write at least 10 characters.').max(3000, 'Keep feedback under 3,000 characters.'),
  appVersion: z.string().trim().min(1).max(30),
}).strict();
export async function submitFeedback(userId: string, value: unknown) {
  const data = schema.parse(value);
  // Retries reuse the same submission ID, including after a lost response.
  if (await prisma.feedback.findUnique({ where: { userId_id: { userId, id: data.id } } })) return { received: true };
  const count = await prisma.feedback.count({ where: { userId, createdAt: { gte: new Date(Date.now() - 3600000) } } });
  if (count >= 5) throw new ApiError(429, 'You have sent several messages. Please try again in an hour.');
  await prisma.feedback.upsert({ where: { userId_id: { userId, id: data.id } }, create: { userId, ...data }, update: {} });
  return { received: true };
}
