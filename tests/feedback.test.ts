import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
vi.mock('@/auth', () => ({ auth: async () => null }));
describe.skipIf(process.env.RUN_DATABASE_TESTS !== '1')('Feedback inbox', () => {
  let prisma: typeof import('../src/lib/prisma')['prisma'];
  let submit: typeof import('../src/lib/server/feedback')['submitFeedback'];
  let id: string, otherId: string;
  beforeAll(async () => {
    if (!/^postgresql:\/\/.*@(localhost|127\.0\.0\.1):55432\//.test(process.env.DATABASE_URL ?? '')) throw new Error('Use the isolated database only.');
    prisma = (await import('../src/lib/prisma')).prisma;
    submit = (await import('../src/lib/server/feedback')).submitFeedback;
    id = (await prisma.user.create({ data: { email: `feedback-${randomUUID()}@example.test`, password: 'unused' } })).id;
    otherId = (await prisma.user.create({ data: { email: `feedback-${randomUUID()}@example.test`, password: 'unused' } })).id;
  });
  afterAll(async () => { if (prisma) { await prisma.user.deleteMany({ where: { id: { in: [id, otherId].filter(Boolean) } } }); await prisma.$disconnect(); } });
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllEnvs(); });
  const message = () => ({ id: randomUUID(), topic: 'suggestion', message: 'Please improve the payment list.', appVersion: '1.1.1' });
  it('requires authentication', async () => {
    const { POST } = await import('../src/app/api/v1/feedback/route');
    expect((await POST(new Request('http://localhost/api/v1/feedback', { method: 'POST', headers: { origin: 'http://localhost' }, body: '{}' }))).status).toBe(401);
  });
  it('validates and rejects unexpected ledger data', async () => {
    await expect(submit(id, { ...message(), message: 'short' })).rejects.toThrow();
    await expect(submit(id, { ...message(), records: [] })).rejects.toThrow();
  });
  it('stores once on retry and keeps submission IDs scoped to the user', async () => {
    const value = message(); await submit(id, value); await submit(id, value); await submit(otherId, value);
    expect(await prisma.feedback.count({ where: { userId: id } })).toBe(1);
    expect(await prisma.feedback.count({ where: { userId: otherId } })).toBe(1);
  });
  it('limits repeated submissions but allows retrying a received message', async () => {
    const value = message(); await submit(id, value);
    for (let i = 0; i < 3; i++) await submit(id, message());
    await expect(submit(id, message())).rejects.toThrow('Please try again in an hour');
    expect(await submit(id, value)).toEqual({ received: true });
  });
  it('emails the saved feedback with one idempotency key and does not resend after success', async () => {
    vi.stubEnv('RESEND_API_KEY', 'test-key'); vi.stubEnv('FEEDBACK_EMAIL_FROM', 'FinTrack <feedback@example.test>'); vi.stubEnv('FEEDBACK_EMAIL_TO', 'developer@example.test');
    const value = message(); await submit(otherId, value);
    const send = vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ id: 'test-email' }));
    const { deliverFeedback } = await import('../src/lib/server/feedback-email');
    await deliverFeedback(otherId, value.id); await deliverFeedback(otherId, value.id);
    expect(send).toHaveBeenCalledTimes(1);
    const options = send.mock.calls[0][1]!;
    expect(JSON.parse(String(options.body))).toMatchObject({ to: ['developer@example.test'], text: expect.stringContaining(value.message) });
    expect(options.headers).toHaveProperty('Idempotency-Key', `feedback-${otherId}-${value.id}`);
    expect((await prisma.feedback.findUniqueOrThrow({ where: { userId_id: { userId: otherId, id: value.id } } })).emailSentAt).not.toBeNull();
  });
  it('keeps feedback and retries email after a provider failure', async () => {
    vi.stubEnv('RESEND_API_KEY', 'test-key'); vi.stubEnv('FEEDBACK_EMAIL_FROM', 'feedback@example.test'); vi.stubEnv('FEEDBACK_EMAIL_TO', 'developer@example.test');
    const value = message(); await submit(otherId, value);
    const send = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(null, { status: 503 })).mockResolvedValueOnce(Response.json({ id: 'retry-email' }));
    const { deliverFeedback } = await import('../src/lib/server/feedback-email');
    await deliverFeedback(otherId, value.id);
    expect(await prisma.feedback.findUniqueOrThrow({ where: { userId_id: { userId: otherId, id: value.id } } })).toMatchObject({ message: value.message, emailSentAt: null, emailAttempts: 1 });
    await deliverFeedback(otherId, value.id);
    expect(send).toHaveBeenCalledTimes(2);
    expect((await prisma.feedback.findUniqueOrThrow({ where: { userId_id: { userId: otherId, id: value.id } } })).emailSentAt).not.toBeNull();
  });

});
