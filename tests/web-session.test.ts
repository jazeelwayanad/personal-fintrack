import { beforeEach, expect, it, vi } from 'vitest';
const mocks = vi.hoisted(() => ({ auth: vi.fn(), user: vi.fn() }));
vi.mock('@/auth', () => ({ auth: mocks.auth }));
vi.mock('@/lib/prisma', () => ({ prisma: { user: { findUnique: mocks.user } } }));
import { requireUser } from '../src/lib/server/mobile-auth';
beforeEach(() => { vi.clearAllMocks(); });
it('rejects a stale web account session with a recoverable 401', async () => {
  mocks.auth.mockResolvedValue({ user: { id: 'retired-account' } });
  mocks.user.mockResolvedValue(null);
  await expect(requireUser(new Request('https://fintrack.test/api/v1/sync'))).rejects.toMatchObject({ status: 401, message: 'Please sign in again.' });
});
it('keeps a valid session attached to its own account', async () => {
  mocks.auth.mockResolvedValue({ user: { id: 'current-account' } });
  mocks.user.mockResolvedValue({ id: 'current-account' });
  expect(await requireUser(new Request('https://fintrack.test/api/v1/sync'))).toBe('current-account');
  expect(mocks.user).toHaveBeenCalledWith({ where: { id: 'current-account' }, select: { id: true } });
});
