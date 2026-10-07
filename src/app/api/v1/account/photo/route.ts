import { createHash } from 'node:crypto';
import { prisma } from '@/lib/prisma';
import { api } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { photoLimit, savePhoto, removePhoto } from '@/lib/server/account';
import { ApiError } from '@/lib/server/sync';
import { downloadCloudinaryPhoto } from '@/lib/server/cloudinary';
export const runtime = 'nodejs';
export async function GET(req: Request) {
  try {
    const userId = await requireUser(req);
    const photo = await prisma.userProfile.findUnique({ where: { userId }, select: { photo: true, photoType: true, photoPublicId: true, photoFormat: true, updatedAt: true } });
    if ((!photo?.photoPublicId && !photo?.photo) || !photo?.photoType) return new Response(null, { status: 404, headers: { 'Cache-Control': 'no-store' } });
    const etag = `"${createHash('sha256').update(`${userId}:${photo.updatedAt.getTime()}`).digest('hex')}"`;
    const cacheHeaders = { 'Cache-Control': 'private, no-cache', 'ETag': etag, 'Vary': 'Cookie, Authorization' };
    if (req.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers: cacheHeaders });
    const image = photo.photoPublicId && photo.photoFormat ? (await downloadCloudinaryPhoto(photo.photoPublicId, photo.photoFormat)).body : new Uint8Array(photo.photo!);
    return new Response(image, { headers: { 'Content-Type': photo.photoType, ...cacheHeaders, 'X-Content-Type-Options': 'nosniff' } });
  } catch (error) { return api(async () => { throw error; }); }
}
export async function POST(req: Request) {
  return api(async () => {
    const userId = await requireUser(req);
    const reader = req.body?.getReader();
    if (!reader) throw new ApiError(400, 'Choose a photo first.');
    const chunks: Uint8Array[] = []; let size = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read(); if (done) break;
        size += value.byteLength;
        if (size > photoLimit) { await reader.cancel(); throw new ApiError(413, 'Choose a smaller photo.'); }
        chunks.push(value);
      }
    } finally { reader.releaseLock(); }
    return savePhoto(userId, Buffer.concat(chunks), req.headers.get('content-type')?.split(';')[0] ?? '');
  });
}
export async function DELETE(req: Request) { return api(async () => removePhoto(await requireUser(req))); }
