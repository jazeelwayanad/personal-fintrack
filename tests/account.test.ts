import { beforeAll, afterAll, describe, expect, it, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
vi.mock('@/auth', () => ({ auth: async () => null }));
const enabled = process.env.RUN_DATABASE_TESTS === '1';

describe.skipIf(!enabled)('Private account profile', () => {
  let prisma: typeof import('../src/lib/prisma')['prisma'];
  let account: typeof import('../src/lib/server/account');
  let route: typeof import('../src/app/api/v1/account/route');
  let photoRoute: typeof import('../src/app/api/v1/account/photo/route');
  let mobile: typeof import('../src/lib/server/mobile-auth');
  let id: string, otherId: string, token: string;
  const email = `profile-${randomUUID()}@example.test`;
  const otherEmail = `profile-${randomUUID()}@example.test`;
  const password = 'profile-test-password';
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL7kAAAAASUVORK5CYII=', 'base64');
  beforeAll(async () => {
    vi.stubEnv('CLOUDINARY_CLOUD_NAME', 'test-cloud'); vi.stubEnv('CLOUDINARY_API_KEY', 'test-key'); vi.stubEnv('CLOUDINARY_API_SECRET', 'test-secret');
    if (!/^postgresql:\/\/.*@(localhost|127\.0\.0\.1):55432\//.test(process.env.DATABASE_URL ?? '')) throw new Error('Use the isolated local database only.');
    prisma = (await import('../src/lib/prisma')).prisma;
    account = await import('../src/lib/server/account'); mobile = await import('../src/lib/server/mobile-auth');
    route = await import('../src/app/api/v1/account/route'); photoRoute = await import('../src/app/api/v1/account/photo/route');
    id = (await prisma.user.create({ data: { email, name: 'Profile Test', password: await bcrypt.hash(password, 4) } })).id;
    otherId = (await prisma.user.create({ data: { email: otherEmail, password: 'unused' } })).id;
    token = (await mobile.login({ email, password }, false)).accessToken;
  });
  afterAll(async () => { if (prisma) { await prisma.authAttempt.deleteMany({ where: { key: `profile-email:${id}` } }); await prisma.user.deleteMany({ where: { id: { in: [id, otherId].filter(Boolean) } } }); await prisma.$disconnect(); } vi.unstubAllEnvs(); vi.restoreAllMocks(); });
  const request = (path: string, method = 'GET', data?: unknown) => new Request(`http://localhost/api/v1/account${path}`, { method, headers: { authorization: `Bearer ${token}`, ...(data ? { 'content-type': 'application/json' } : {}) }, ...(data ? { body: JSON.stringify(data) } : {}) });
  it('requires authentication and rejects cross-origin cookie mutations', async () => {
    expect((await route.GET(new Request('http://localhost/api/v1/account'))).status).toBe(401);
    expect((await route.PATCH(new Request('http://localhost/api/v1/account', { method: 'PATCH', headers: { origin: 'https://elsewhere.test' }, body: '{}' }))).status).toBe(403);
    expect((await photoRoute.GET(new Request('http://localhost/api/v1/account/photo'))).status).toBe(401);
  });
  it('persists name and phone for the owner without exposing password or affecting others', async () => {
    const response = await route.PATCH(request('', 'PATCH', { name: 'Updated Name', email, phone: '+91 98765 43210' }));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ name: 'Updated Name', email, phone: '+91 98765 43210', image: null, photoUploadEnabled: true });
    expect(await account.readAccount(otherId)).toMatchObject({ email: otherEmail, phone: '', image: null });
    expect((await prisma.user.findUniqueOrThrow({ where: { id } })).password).not.toBe(password);
    await expect(account.updateAccount(id, { name: 'Name', email, phone: 'not a phone' })).rejects.toThrow();
    await expect(account.updateAccount(id, { name: 'Name', email, phone: '', userId: otherId })).rejects.toThrow();
  });
  it('requires current password for email changes and rejects duplicate emails', async () => {
    await expect(account.updateAccount(id, { name: 'Name', email: otherEmail, phone: '' })).rejects.toThrow('current password');
    await expect(account.updateAccount(id, { name: 'Name', email: otherEmail, phone: '', currentPassword: 'wrong' })).rejects.toThrow('incorrect');
    await expect(account.updateAccount(id, { name: 'Name', email: otherEmail, phone: '', currentPassword: password })).rejects.toThrow('already in use');
    const changed = `changed-${randomUUID()}@example.test`;
    expect(await account.updateAccount(id, { name: 'Name', email: changed, phone: '', currentPassword: password })).toMatchObject({ email: changed });
    expect((await mobile.login({ email: changed, password }, false)).user.id).toBe(id);
  });
  it('stores photos on Cloudinary, serves them privately, and removes them', async () => {
    const cloudFetch = vi.spyOn(globalThis, 'fetch').mockImplementation(async (url, options) => {
      if (String(url).includes('/upload')) {
        const form = options?.body as FormData;
        expect(form.get('type')).toBe('authenticated'); expect(form.get('signature')).toMatch(/^[a-f0-9]{64}$/);
        return Response.json({ public_id: form.get('public_id'), format: 'png', type: 'authenticated' });
      }
      if (String(url).includes('/download')) { expect(String(url)).toContain('type=authenticated'); return new Response(png); }
      if (String(url).includes('/destroy')) return Response.json({ result: 'ok' });
      throw new Error('Unexpected external request');
    });
    const upload = await photoRoute.POST(new Request('http://localhost/api/v1/account/photo', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'image/png' }, body: png }));
    expect(upload.status).toBe(200);
    expect((await upload.json()).image).toMatch(/^\/api\/v1\/account\/photo\?v=/);
    const stored = await prisma.userProfile.findUniqueOrThrow({ where: { userId: id } });
    expect(stored.photo).toBeNull(); expect(stored.photoPublicId).toMatch(/^fintrack\/profiles\//);
    const response = await photoRoute.GET(request('/photo'));
    expect(response.headers.get('content-type')).toBe('image/png');
    expect(response.headers.get('cache-control')).toBe('private, no-store');
    expect(Buffer.from(await response.arrayBuffer())).toEqual(png);
    expect(await account.readAccount(otherId)).toMatchObject({ image: null });
    expect((await photoRoute.DELETE(request('/photo', 'DELETE'))).status).toBe(200);
    expect((await photoRoute.GET(request('/photo'))).status).toBe(404);
    expect(cloudFetch).toHaveBeenCalledTimes(3); cloudFetch.mockRestore();
  });
  it('reports missing Cloudinary configuration without losing profile details', async () => {
    vi.stubEnv('CLOUDINARY_API_SECRET', '');
    expect((await account.readAccount(id)).photoUploadEnabled).toBe(false);
    await expect(account.savePhoto(id, png, 'image/png')).rejects.toThrow('not configured');
    vi.stubEnv('CLOUDINARY_API_SECRET', 'test-secret');
  });
  it('rejects unsupported, mismatched and oversized photo uploads', async () => {
    expect(() => account.validatePhoto(Buffer.from('<svg/>'), 'image/svg+xml')).toThrow('JPG');
    expect(() => account.validatePhoto(png, 'image/jpeg')).toThrow('JPG');
    const oversized = new Uint8Array(account.photoLimit + 1);
    const response = await photoRoute.POST(new Request('http://localhost/api/v1/account/photo', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'image/png' }, body: oversized }));
    expect(response.status).toBe(413);
    expect(await account.readAccount(id)).toMatchObject({ image: null });
  });
});
