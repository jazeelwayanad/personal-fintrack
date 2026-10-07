import bcrypt from 'bcryptjs';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '@/lib/prisma';
import { ApiError } from './sync';
import { cloudinaryEnabled, uploadCloudinaryPhoto, deleteCloudinaryPhoto } from './cloudinary';

const fields = { id: true, name: true, email: true, profile: { select: { phone: true, photoType: true, updatedAt: true } } } as const;
const profileInput = z.object({
  name: z.string().trim().min(1, 'Enter your name.').max(120),
  email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254),
  phone: z.string().trim().max(30).refine(value => !value || (/^[+\d\s().-]+$/.test(value) && value.replace(/\D/g, '').length >= 7 && value.replace(/\D/g, '').length <= 15), 'Enter a valid phone number, including the country code.'),
  currentPassword: z.string().max(200).optional(),
}).strict();

export async function readAccount(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: fields });
  if (!user) throw new ApiError(401, 'Please sign in again.');
  return { name: user.name ?? '', email: user.email, phone: user.profile?.phone ?? '', photoUploadEnabled: cloudinaryEnabled(), image: user.profile?.photoType ? `/api/v1/account/photo?v=${user.profile.updatedAt.getTime()}` : null };
}
export async function updateAccount(userId: string, input: unknown) {
  const data = profileInput.parse(input);
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true, password: true } });
  if (!user) throw new ApiError(401, 'Please sign in again.');
  if (data.email !== user.email) {
    if (!data.currentPassword) throw new ApiError(400, 'Enter your current password to change your email.');
    const key = `profile-email:${userId}`, now = new Date();
    const attempt = await prisma.$transaction(async tx => {
      await tx.authAttempt.upsert({ where: { key }, create: { key, count: 0, expiresAt: new Date(now.getTime() + 900000) }, update: {} });
      await tx.authAttempt.updateMany({ where: { key, expiresAt: { lt: now } }, data: { count: 0, expiresAt: new Date(now.getTime() + 900000) } });
      return tx.authAttempt.update({ where: { key }, data: { count: { increment: 1 } } });
    });
    if (attempt.count > 10) throw new ApiError(429, 'Too many attempts. Try again in 15 minutes.');
    if (!await bcrypt.compare(data.currentPassword, user.password)) throw new ApiError(400, 'Your current password is incorrect.');
    const existing = await prisma.user.findFirst({ where: { email: { equals: data.email, mode: 'insensitive' }, id: { not: userId } }, select: { id: true } });
    if (existing) throw new ApiError(409, 'This email is already in use.');
  }
  try {
    await prisma.user.update({ where: { id: userId }, data: { name: data.name, email: data.email, profile: { upsert: { create: { phone: data.phone || null }, update: { phone: data.phone || null } } } } });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw new ApiError(409, 'This email is already in use.');
    throw error;
  }
  if (data.email !== user.email) await prisma.authAttempt.deleteMany({ where: { key: `profile-email:${userId}` } });
  return readAccount(userId);
}
export const photoLimit = 512 * 1024;
export function validatePhoto(bytes: Uint8Array, type: string) {
  if (!bytes.length || bytes.length > photoLimit) throw new ApiError(413, 'Choose a photo smaller than 512 KB after resizing.');
  const signature = type === 'image/jpeg' ? bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255
    : type === 'image/png' ? Buffer.from(bytes.subarray(0, 8)).equals(Buffer.from([137,80,78,71,13,10,26,10]))
    : type === 'image/webp' ? Buffer.from(bytes.subarray(0,4)).toString() === 'RIFF' && Buffer.from(bytes.subarray(8,12)).toString() === 'WEBP' : false;
  if (!signature) throw new ApiError(400, 'Choose a JPG, PNG, or WebP photo.');
}
export async function savePhoto(userId: string, bytes: Uint8Array, type: string) {
  validatePhoto(bytes, type);
  const uploaded = await uploadCloudinaryPhoto(bytes, type);
  let previous: string | null;
  try {
    previous = await prisma.$transaction(async tx => {
      await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${userId} FOR UPDATE`;
      const old = await tx.userProfile.findUnique({ where: { userId }, select: { photoPublicId: true } });
      const data = { photo: null, photoPublicId: uploaded.publicId, photoFormat: uploaded.format, photoType: uploaded.type };
      await tx.userProfile.upsert({ where: { userId }, create: { userId, ...data }, update: data });
      return old?.photoPublicId ?? null;
    });
  } catch (error) {
    await deleteCloudinaryPhoto(uploaded.publicId).catch(() => console.error('[Profile photo] Failed to clean up an unused upload.'));
    throw error;
  }
  if (previous) await deleteCloudinaryPhoto(previous).catch(() => console.error('[Profile photo] Failed to clean up a replaced photo.'));
  return readAccount(userId);
}
export async function removePhoto(userId: string) {
  await prisma.$transaction(async tx => {
    await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${userId} FOR UPDATE`;
    const photo = await tx.userProfile.findUnique({ where: { userId }, select: { photoPublicId: true } });
    if (photo?.photoPublicId) await deleteCloudinaryPhoto(photo.photoPublicId);
    await tx.userProfile.updateMany({ where: { userId }, data: { photo: null, photoType: null, photoPublicId: null, photoFormat: null } });
  }, { timeout: 25000 });
  return readAccount(userId);
}
