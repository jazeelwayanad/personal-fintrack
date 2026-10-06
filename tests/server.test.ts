import { beforeAll, afterAll, describe, it, expect, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
vi.mock('@/auth', () => ({ auth: async () => null }));
const enabled = process.env.RUN_DATABASE_TESTS === '1';
describe.skipIf(!enabled)('PostgreSQL sync and mobile authentication', () => {
  let prisma: typeof import('../src/lib/prisma')['prisma'];
  let sync: typeof import('../src/lib/server/sync');
  let auth: typeof import('../src/lib/server/mobile-auth');
  const users: string[] = [];
  const email = `test-${randomUUID()}@example.test`;
  beforeAll(async () => {
    const url = process.env.DATABASE_URL ?? '';
    if (!/^postgresql:\/\/.*@(localhost|127\.0\.0\.1):55432\//.test(url)) throw new Error('Database tests only run against the isolated local database on port 55432.');
    prisma = (await import('../src/lib/prisma')).prisma; sync = await import('../src/lib/server/sync'); auth = await import('../src/lib/server/mobile-auth');
  });
  afterAll(async () => { if (prisma) { await prisma.user.deleteMany({ where: { id: { in: users } } }); await prisma.$disconnect(); } });
  it('rotates refresh tokens and revokes access on logout', async () => {
    const login = await auth.login({ email, password: 'a-test-password', name: 'Test' }, true); users.push(login.user.id);
    expect(await auth.requireUser(new Request('http://localhost/api', { headers: { authorization: `Bearer ${login.accessToken}` } }))).toBe(login.user.id);
    const next = await auth.refresh({ refreshToken: login.refreshToken });
    await expect(auth.refresh({ refreshToken: login.refreshToken })).rejects.toThrow('Session expired');
    await auth.logout({ refreshToken: next.refreshToken });
    await expect(auth.requireUser(new Request('http://localhost/api', { headers: { authorization: `Bearer ${next.accessToken}` } }))).rejects.toThrow('Please sign in');
  });
  it('records one concurrent bill payment, rejects stale changes and isolates accounts', async () => {
    const userId = users[0];
    const cat = randomUUID(), method = randomUUID(), plan = randomUUID();
    const change = (id: string, kind: string, data: unknown, baseRevision = 0) => ({ id, kind, data, baseRevision, deleted: false });
    const initial = await sync.push(userId, { id: randomUUID(), changes: [change(cat, 'category', { name: 'Bills', type: 'expense', color: '#123456' }), change(method, 'paymentMethod', { name: 'Bank' }), change(plan, 'plan', { name: 'EMI', planType: 'emi', type: 'expense', amount: 10000, categoryId: cat, startDate: '2026-10-10', recurrence: 'monthly', reminders: true })] });
    expect(initial.accepted).toBe(true);
    const oid = `${plan}:2026-10-10`;
    const changes = [change(oid, 'occurrence', { planId: plan, name: 'EMI', type: 'expense', amount: 10000, categoryId: cat, date: '2026-10-10', reminders: true, status: 'pending' }), change(`payment:${oid}`, 'transaction', { type: 'expense', amount: 10000, categoryId: cat, paymentMethodId: method, date: '2026-10-10', occurrenceId: oid })];
    const mutation = { id: randomUUID(), changes };
    const results = await Promise.all([sync.push(userId, mutation), sync.push(userId, { ...mutation, id: randomUUID() })]);
    expect(results.filter(r => r.accepted)).toHaveLength(1);
    expect((await sync.push(userId, mutation)).accepted).toBe(results[0].accepted);
    expect(await prisma.transaction.count({ where: { userId } })).toBe(1);
    const snapshot = await sync.pull(userId, 0); expect(snapshot.records.filter(r => r.kind === 'transaction')).toHaveLength(1);
    expect((await sync.pull(userId, snapshot.cursor)).records).toEqual([]);
    const other = await prisma.user.create({ data: { email: `test-${randomUUID()}@example.test`, password: 'unused' } }); users.push(other.id);
    expect((await sync.pull(other.id, 0)).records).toEqual([]);
    await expect(sync.push(other.id, { id: randomUUID(), changes: [change(cat, 'category', { name: 'Stolen', type: 'expense', color: '#123456' })] })).rejects.toThrow('another account');
    expect((await prisma.category.findUniqueOrThrow({ where: { id: cat } })).name).toBe('Bills');
    await expect(sync.push(userId, { id: randomUUID(), changes: [change(randomUUID(), 'transaction', { type: 'expense', amount: 100, categoryId: 'missing', paymentMethodId: method, date: '2026-10-10' })] })).rejects.toThrow('valid category');
  });
});
