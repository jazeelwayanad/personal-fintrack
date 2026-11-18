import { lockLedger } from './sync';
import { Prisma } from '@prisma/client';
import { accountAttempt, authenticate, credentials } from './credentials';
import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { prisma } from '@/lib/prisma';
import { auth } from '@/auth';
import { ApiError } from '@/lib/server/api-error';
const hash = (v: string) => createHash('sha256').update(v).digest('hex');
const secret = () => { const value = process.env.MOBILE_AUTH_SECRET || process.env.AUTH_SECRET; if (!value || value.length < 32) throw new Error('Set MOBILE_AUTH_SECRET to at least 32 characters'); return new TextEncoder().encode(value); };
async function access(userId: string, sessionId: string) { return new SignJWT({ sid: sessionId }).setProtectedHeader({ alg: 'HS256' }).setSubject(userId).setIssuer('fintrack').setAudience('fintrack-mobile').setIssuedAt().setExpirationTime('15m').sign(secret()); }
export async function requireUser(req: Request) {
  const bearer = req.headers.get('authorization');
  if (bearer?.startsWith('Bearer ')) {
    try {
      const { payload } = await jwtVerify(bearer.slice(7), secret(), { issuer: 'fintrack', audience: 'fintrack-mobile', algorithms: ['HS256'] });
      const session = await prisma.mobileSession.findUnique({ where: { id: String(payload.sid) } });
      if (!session || session.userId !== payload.sub || session.revokedAt || session.expiresAt <= new Date()) throw new Error('Expired');
      return session.userId;
    } catch { throw new ApiError(401, 'Please sign in again.'); }
  }
  if (req.method !== 'GET') {
    const origin = req.headers.get('origin');
    const targetHost = req.headers.get('host') ?? new URL(req.url).host;
    if (!origin || new URL(origin).host !== targetHost || new URL(origin).protocol !== new URL(req.url).protocol) throw new ApiError(403, 'Invalid request origin.');
  }
  const session = await auth();
  if (!session?.user?.id) throw new ApiError(401, 'Please sign in.');
  const user = await prisma.user.findUnique({ where: { id: session.user.id }, select: { id: true } });
  if (!user) throw new ApiError(401, 'Please sign in again.');
  return session.user.id;
}
export async function login(input: unknown, register: boolean, req?: Request) {
  const user = register ? await registerUser(input, req) : await authenticate(input, req);
  const refreshToken = randomBytes(48).toString('base64url');
  const session = await prisma.$transaction(async tx => {
    await lockLedger(tx, user.id);
    const current = await tx.user.findUniqueOrThrow({ where: { id: user.id }, select: { sessionVersion: true } });
    if (current.sessionVersion !== user.sessionVersion) throw new ApiError(401, 'Please sign in again.');
    return tx.mobileSession.create({ data: { userId: user.id, refreshHash: hash(refreshToken), expiresAt: new Date(Date.now() + 30 * 86400000) } });
  });
  return { accessToken: await access(user.id, session.id), refreshToken, user: { id: user.id, email: user.email, name: user.name } };
}
async function registerUser(input: unknown, req?: Request) {
  const data = credentials.parse(input);
  if (Buffer.byteLength(data.password) > 72) throw new ApiError(400, 'Use at most 72 UTF-8 bytes for your password.');
  const key = await accountAttempt(data.email, req);
  const existing = await prisma.user.findFirst({ where: { email: { equals: data.email, mode: 'insensitive' } }, select: { id: true } });
  if (existing) throw new ApiError(409, 'An account already exists for this email.');
  try {
    const user = await prisma.user.create({ data: { ...data, password: await bcrypt.hash(data.password, 12) } });
    await prisma.authAttempt.deleteMany({ where: { key } });
    return user;
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw new ApiError(409, 'An account already exists for this email.');
    throw error;
  }
}
export async function refresh(input: unknown) {
  const { refreshToken } = z.object({ refreshToken: z.string().min(20).max(200) }).parse(input);
  const next = randomBytes(48).toString('base64url');
  const session = await prisma.mobileSession.findUnique({ where: { refreshHash: hash(refreshToken) } });
  if (!session || session.revokedAt || session.expiresAt <= new Date()) throw new ApiError(401, 'Session expired.');
  const result = await prisma.mobileSession.updateMany({ where: { id: session.id, refreshHash: hash(refreshToken), revokedAt: null, expiresAt: { gt: new Date() } }, data: { refreshHash: hash(next), expiresAt: new Date(Date.now() + 30 * 86400000) } });
  if (result.count !== 1) throw new ApiError(401, 'Session already refreshed.');
  return { accessToken: await access(session.userId, session.id), refreshToken: next };
}
export async function logout(input: unknown) { const { refreshToken } = z.object({ refreshToken: z.string() }).parse(input); await prisma.mobileSession.updateMany({ where: { refreshHash: hash(refreshToken) }, data: { revokedAt: new Date() } }); return { success: true }; }
