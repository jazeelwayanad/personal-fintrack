import { createHash, randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { Prisma, type User } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '@/lib/prisma';
import { ApiError } from './api-error';
import { authenticate, findCredentialUser, rateLimit } from './credentials';
import { lockLedger, type Tx } from './sync';

const digest = (value: string) => createHash('sha256').update(value).digest('hex');
export const accountVerificationEnabled = () => process.env.ACCOUNT_VERIFICATION_ENABLED === 'true';
const accountEmailConfigured = () => accountVerificationEnabled() && !!process.env.RESEND_API_KEY && !!process.env.ACCOUNT_EMAIL_FROM && !!process.env.AUTH_URL;
type Recipient = Pick<User, 'id' | 'email' | 'sessionVersion'>;

async function deliver(recipient: Recipient, kind: 'recovery' | 'email_change', newEmail?: string) {
  if (!accountEmailConfigured()) throw new ApiError(503, 'Account verification is temporarily unavailable.');
  const url = new URL('/recover', process.env.AUTH_URL);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname))) throw new Error('Invalid account email URL');
  const secret = randomBytes(32).toString('base64url');
  const hash = digest(secret);
  url.hash = new URLSearchParams({ token: secret, kind }).toString();
  const expiresAt = new Date(Date.now() + 30 * 60_000);
  await prisma.$transaction(async tx => {
    await lockLedger(tx, recipient.id);
    const current = await tx.user.findUniqueOrThrow({ where: { id: recipient.id }, select: { email: true, sessionVersion: true } });
    if (current.email !== recipient.email || current.sessionVersion !== recipient.sessionVersion) throw new ApiError(409, 'Account changed. Please try again.');
    await tx.accountToken.deleteMany({ where: { userId: recipient.id, kind } });
    await tx.accountToken.create({ data: {
      userId: recipient.id, hash, kind, originalEmail: recipient.email, sessionVersion: recipient.sessionVersion, expiresAt, newEmail,
    } });
  });
  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST', signal: AbortSignal.timeout(8000), redirect: 'error',
      headers: { Authorization: 'Bearer ' + process.env.RESEND_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: process.env.ACCOUNT_EMAIL_FROM,
        to: [newEmail ?? recipient.email],
        subject: kind === 'recovery' ? 'Reset your FinTrack password' : 'Verify your new FinTrack email',
        text: ['Open this link to continue:', url.href, 'The link expires in 30 minutes and can be used once.'].join('\n'),
      }),
    });
    if (!response.ok) throw new Error('Email provider unavailable');
  } catch {
    await prisma.accountToken.deleteMany({ where: { hash } });
    throw new ApiError(503, 'Could not send a verification email. Try again later.');
  }
}

export async function requestEmailChange(user: Recipient, email: string) {
  await rateLimit('email-confirm:' + user.id, 5, 3_600_000);
  await deliver(user, 'email_change', email);
}

export async function requestPasswordReset(input: unknown) {
  if (!accountEmailConfigured()) throw new ApiError(404, 'Password recovery is temporarily unavailable.');
  const { email } = z.strictObject({ email: z.string().trim().toLowerCase().email().max(254) }).parse(input);
  await rateLimit('recovery:' + digest(email), 5, 3_600_000);
  const user = await findCredentialUser(email);
  if (user) await deliver(user, 'recovery').catch(() => {});
  return { received: true };
}

async function revokeSessions(tx: Tx, userId: string, password?: string) {
  await tx.user.update({ where: { id: userId }, data: { password, sessionVersion: { increment: 1 } } });
  await tx.mobileSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
  await tx.accountToken.deleteMany({ where: { userId } });
}

export async function signOutEverywhere(userId: string, input: unknown, req: Request) {
  const { password } = z.strictObject({ password: z.string().min(8).max(200) }).parse(input);
  const owner = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true } });
  const authenticated = await authenticate({ email: owner.email, password }, req);
  if (authenticated.id !== userId) throw new ApiError(403, 'Confirm your current password.');
  return prisma.$transaction(async tx => {
    await lockLedger(tx, userId);
    const current = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { sessionVersion: true } });
    if (current.sessionVersion !== authenticated.sessionVersion) throw new ApiError(409, 'Account changed. Sign in again.');
    await revokeSessions(tx, userId);
    return { revoked: true };
  });
}

const token = z.string().regex(/^[a-zA-Z0-9_-]{43}$/);
const complete = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('email_change'), token }),
  z.strictObject({ kind: z.literal('recovery'), token, password: z.string().min(8).refine(value => Buffer.byteLength(value) <= 72, 'Use at most 72 UTF-8 bytes.') }),
]);
export async function consumeAccountToken(input: unknown) {
  if (!accountVerificationEnabled()) throw new ApiError(404, 'Account verification is unavailable.');
  const command = complete.parse(input);
  const hash = digest(command.token);
  const invalid = () => new ApiError(400, 'This link is invalid, expired, or already used.');
  const candidate = await prisma.accountToken.findUnique({ where: { hash } });
  if (!candidate || candidate.kind !== command.kind || candidate.expiresAt <= new Date()) throw invalid();
  const password = command.kind === 'recovery' ? await bcrypt.hash(command.password, 12) : undefined;
  try {
    return await prisma.$transaction(async tx => {
      await lockLedger(tx, candidate.userId);
      const credential = await tx.accountToken.findUnique({ where: { hash } });
      const user = await tx.user.findUnique({ where: { id: candidate.userId } });
      if (!credential || !user || credential.expiresAt <= new Date() || credential.originalEmail !== user.email || credential.sessionVersion !== user.sessionVersion) throw invalid();
      if (command.kind === 'email_change') {
        const email = credential.newEmail;
        if (!email) throw invalid();
        const conflict = await tx.user.findFirst({ where: { id: { not: user.id }, email: { equals: email, mode: 'insensitive' } }, select: { id: true } });
        if (conflict) throw new ApiError(409, 'This email is already in use.');
        await tx.user.update({ where: { id: user.id }, data: { email } });
      } else {
        await revokeSessions(tx, user.id, password);
        await tx.mcpGrant.updateMany({ where: { userId: user.id, revokedAt: null }, data: { revokedAt: new Date() } });
      }
      await tx.accountToken.deleteMany({ where: { userId: user.id } });
      return { saved: true };
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw new ApiError(409, 'This email is already in use.');
    throw error;
  }
}
