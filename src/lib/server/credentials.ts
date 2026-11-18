import { createHash } from 'node:crypto';
import { isIP } from 'node:net';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { prisma } from '@/lib/prisma';
import { ApiError } from './api-error';

export const credentials = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  password: z.string().min(8).max(200),
  name: z.string().trim().max(120).optional(),
});

export async function rateLimit(key: string, max: number, windowMs: number) {
  const now = new Date();
  const expiresAt = new Date(now.getTime() + windowMs);
  const [row] = await prisma.$queryRaw<{ count: number }[]>`
    INSERT INTO "AuthAttempt" ("key", "count", "expiresAt") VALUES (${key}, 1, ${expiresAt})
    ON CONFLICT ("key") DO UPDATE SET
      "count" = CASE WHEN "AuthAttempt"."expiresAt" <= ${now} THEN 1 ELSE "AuthAttempt"."count" + 1 END,
      "expiresAt" = CASE WHEN "AuthAttempt"."expiresAt" <= ${now} THEN ${expiresAt} ELSE "AuthAttempt"."expiresAt" END
    RETURNING "count"
  `;
  if (row.count > max) throw new ApiError(429, 'Too many requests. Please try again later.');
}

export async function accountAttempt(email: string, req?: Request) {
  // On non-Vercel deployments set trusted proxy limits at the ingress.
  const ip = process.env.VERCEL === '1' ? req?.headers.get('x-vercel-forwarded-for')?.trim() : undefined;
  if (ip && isIP(ip)) await rateLimit('auth-ip:' + ip, 90, 900_000);
  const key = createHash('sha256').update(email).digest('hex');
  await rateLimit(key, 15, 900_000);
  return key;
}

export async function findCredentialUser(email: string, presented = email) {
  // Preserve access to older mixed-case addresses while refusing ambiguous matches.
  const exact = await prisma.user.findUnique({ where: { email: presented } });
  if (exact) return exact;
  const candidates = await prisma.user.findMany({ where: { email: { equals: email, mode: 'insensitive' } }, take: 2 });
  return candidates.length === 1 ? candidates[0] : null;
}

export async function authenticate(input: unknown, req?: Request) {
  const data = credentials.parse(input);
  const key = await accountAttempt(data.email, req);
  const presented = z.object({ email: z.string().trim() }).parse(input).email;
  const user = await findCredentialUser(data.email, presented);
  if (!user || !await bcrypt.compare(data.password, user.password)) throw new ApiError(401, 'Incorrect email or password.');
  await prisma.authAttempt.deleteMany({ where: { key } });
  return user;
}
