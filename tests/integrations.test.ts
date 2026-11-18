import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { todayIndia } from '../src/lib/finance/engine';
import { parseStatement } from '../src/lib/finance/statement';

const enabled = process.env.RUN_DATABASE_TESTS === '1';
describe.skipIf(!enabled)('MCP and UPI with PostgreSQL', () => {
  let prisma: typeof import('../src/lib/prisma')['prisma'];
  let sync: typeof import('../src/lib/server/sync');
  let upi: typeof import('../src/lib/server/upi');
  let user: string;
  let other: string;
  let category: string;
  let method: string;
  const people: string[] = [];

  beforeAll(async () => {
    if (!/^postgresql:\/\/.*@(localhost|127\.0\.0\.1):55432\//.test(process.env.DATABASE_URL ?? '')) throw new Error('Use the isolated local test database.');
    vi.stubEnv('UPI_HANDOFF_ENABLED', 'true');
    vi.stubEnv('UPI_DATA_KEY', 'a0'.repeat(32));
    vi.stubEnv('MCP_STATE_KEY', 'a1'.repeat(32));
    vi.stubEnv('MCP_WRITE_ENABLED', 'true');
    prisma = (await import('../src/lib/prisma')).prisma;
    sync = await import('../src/lib/server/sync');
    upi = await import('../src/lib/server/upi');
    for (let index = 0; index < 2; index++) {
      const record = await prisma.user.create({ data: { email: randomUUID() + '@example.test', password: 'unused' } });
      people.push(record.id);
    }
    [user, other] = people;
  });
  afterAll(async () => {
    vi.unstubAllEnvs();
    if (prisma) {
      await prisma.user.deleteMany({ where: { id: { in: people } } });
      await prisma.$disconnect();
    }
  });

  it('seeds a ledger once while devices are pulling concurrently', async () => {
    const [first, second] = await Promise.all([sync.pull(user, 0, true), sync.pull(user, 0, true)]);
    expect(second.records.map(row => row.id).sort()).toEqual(first.records.map(row => row.id).sort());
    expect(first.records).toHaveLength(8);
    category = first.records.find(row => row.kind === 'category' && row.data.type === 'expense')!.id;
    method = first.records.find(row => row.kind === 'paymentMethod')!.id;
  });

  it('publishes schemas, writes through sync, and checks the grant again on each write', async () => {
    const { financeMcpServer } = await import('../src/lib/server/mcp-tools');
    const grant = await prisma.mcpGrant.create({ data: {
      userId: user, issuer: 'https://issuer.example/', subject: 'owner', clientId: 'test-connector', scopes: ['ledger:read', 'ledger:write'],
    } });
    const server = financeMcpServer(grant, true);
    const client = new Client({ name: 'test', version: '1' });
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    await server.connect(serverTransport);
    await client.connect(clientTransport);
    try {
      const listing = await client.listTools();
      expect(listing.tools.map(tool => tool.name)).toContain('list_transactions');
      expect(listing.tools.find(tool => tool.name === 'create_transaction')?.outputSchema?.properties).toHaveProperty('revision');
      const options = await client.readResource({ uri: 'fintrack://ledger/categories' });
      expect(options.contents[0]).toHaveProperty('text', expect.stringContaining(category));
      const command = { idempotencyKey: randomUUID(), date: todayIndia(), type: 'expense', amountPaise: 145, categoryId: category, paymentMethodId: method, description: 'private memo' };
      const write = () => client.callTool({ name: 'create_transaction', arguments: command });
      const [first, second] = await Promise.all([write(), write()]);
      expect(first.isError).not.toBe(true);
      expect(first.structuredContent).toEqual(second.structuredContent);
      expect((await sync.pull(user, 0)).records.filter(row => row.id === (first.structuredContent as { id: string }).id)).toHaveLength(1);
      expect((await sync.pull(other, 0)).records).toHaveLength(0);
      const date = todayIndia(), tomorrow = new Date(Date.parse(date) + 86400000).toISOString().slice(0, 10);
      const page = await client.callTool({ name: 'list_transactions', arguments: { from: date, to: tomorrow, query: 'PRIVATE MEMO' } });
      expect(page.isError).not.toBe(true);
      expect(JSON.stringify(page.structuredContent)).not.toContain('private memo');
      expect(JSON.stringify(page.structuredContent)).toContain('145');
      expect((await client.callTool({ name: 'create_transaction', arguments: { ...command, amountPaise: 150 } })).isError).toBe(true);
      expect(await prisma.mcpAuditEvent.count({ where: { userId: user, operation: 'create_transaction', outcome: 'accepted' } })).toBe(1);
      await prisma.mcpGrant.update({ where: { id: grant.id }, data: { revokedAt: new Date() } });
      expect((await write()).isError).toBe(true);
    } finally {
      await client.close();
      await server.close();
    }
  });

  it('enforces the bearer audience, connector client, owner grant and revocation on HTTP', async () => {
    const issuer = 'https://auth.fintrack-integration.test/';
    const resource = 'https://fintrack-integration.test/api/mcp';
    vi.stubEnv('MCP_READ_ENABLED', 'true');
    vi.stubEnv('MCP_URL', resource);
    vi.stubEnv('MCP_ISSUER', issuer);
    vi.stubEnv('MCP_ALLOWED_CLIENTS', 'integration-client');
    const grant = await prisma.mcpGrant.create({ data: {
      userId: user, issuer, subject: 'linked-owner', clientId: 'integration-client', scopes: ['ledger:read'],
    } });
    const { publicKey, privateKey } = await generateKeyPair('RS256');
    const jwk = await exportJWK(publicKey);
    const mockFetch = vi.spyOn(globalThis, 'fetch').mockImplementation(async request => {
      expect(String(request)).toBe(issuer + '.well-known/jwks.json');
      return Response.json({ keys: [{ ...jwk, kid: 'test-key' }] });
    });
    const { POST } = await import('../src/app/api/mcp/route');
    const signed = (audience: string, client = 'integration-client') => new SignJWT({ azp: client, scope: 'ledger:read' })
      .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setSubject('linked-owner').setIssuer(issuer).setAudience(audience).setExpirationTime('1m').sign(privateKey);
    const call = (token?: string, origin = new URL(resource).origin) => POST(new Request(resource, {
      method: 'POST', headers: { origin, accept: 'application/json,text/event-stream', 'Content-Type': 'application/json',
        ...(token ? { authorization: 'Bearer ' + token } : {}) },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {
        protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '1' },
      } }),
    }));
    try {
      const missing = await call();
      expect(missing.status).toBe(401);
      expect(missing.headers.get('WWW-Authenticate')).toContain('/.well-known/oauth-protected-resource/api/mcp');
      expect((await call(await signed(resource), 'https://other.example')).status).toBe(403);
      expect((await call(await signed('https://other.example/api/mcp'))).status).toBe(401);
      expect((await call(await signed(resource, 'other-client'))).status).toBe(403);
      const token = await signed(resource);
      const initialized = await call(token);
      expect(initialized.status).toBe(200);
      expect(await initialized.json()).toMatchObject({ result: { serverInfo: { name: 'FinTrack' } } });
      await prisma.mcpGrant.update({ where: { id: grant.id }, data: { revokedAt: new Date() } });
      expect((await call(token)).status).toBe(403);
    } finally {
      mockFetch.mockRestore();
    }
  });

  it('requires the emailed token for account changes and revokes sessions on reset', async () => {
    vi.stubEnv('ACCOUNT_VERIFICATION_ENABLED', 'true');
    vi.stubEnv('ACCOUNT_EMAIL_FROM', 'staging@example.test');
    vi.stubEnv('RESEND_API_KEY', 'synthetic');
    vi.stubEnv('AUTH_URL', 'https://fintrack-integration.test');
    const { requestEmailChange, requestPasswordReset, consumeAccountToken } = await import('../src/lib/server/account-tokens');
    const mockFetch = vi.spyOn(globalThis, 'fetch').mockImplementation(async () => Response.json({ id: 'test' }));
    function sentToken() {
      const options = mockFetch.mock.calls.at(-1)?.[1];
      const text = JSON.parse(String(options?.body)).text as string;
      return new URLSearchParams(new URL(text.split('\n')[1]).hash.slice(1)).get('token');
    }
    try {
      const before = await prisma.user.findUniqueOrThrow({ where: { id: other } });
      const newEmail = randomUUID() + '@example.test';
      await requestEmailChange(before, newEmail);
      const token = sentToken();
      expect((await prisma.user.findUniqueOrThrow({ where: { id: other } })).email).toBe(before.email);
      await expect(consumeAccountToken({ kind: 'email_change', token })).resolves.toEqual({ saved: true });
      await expect(consumeAccountToken({ kind: 'email_change', token })).rejects.toMatchObject({ status: 400 });
      const session = await prisma.mobileSession.create({ data: { userId: other, refreshHash: randomUUID(), expiresAt: new Date(Date.now() + 300_000) } });
      await requestPasswordReset({ email: newEmail });
      await consumeAccountToken({ kind: 'recovery', token: sentToken(), password: 'new-device-password' });
      expect((await prisma.mobileSession.findUniqueOrThrow({ where: { id: session.id } })).revokedAt).toBeInstanceOf(Date);
      expect((await prisma.user.findUniqueOrThrow({ where: { id: other } })).sessionVersion).toBe(before.sessionVersion + 1);
    } finally {
      mockFetch.mockRestore();
    }
  });

  it('records app outcomes as advisory and settles a manual statement debit once', async () => {
    const creation = { idempotencyKey: randomUUID(), payeeVpa: 'bill@example', amountMode: 'fixed', amountPaise: 725, categoryId: category, purpose: 'Water bill', reference: 'bill 32' };
    const attempt = await upi.createUpiAttempt(user, creation);
    expect((await upi.createUpiAttempt(user, creation)).attemptId).toBe(attempt.attemptId);
    expect((await prisma.upiPaymentAttempt.findUniqueOrThrow({ where: { id: attempt.attemptId } })).payeeVpa).not.toBe(creation.payeeVpa);
    await expect(upi.readUpiAttempt(other, attempt.attemptId)).rejects.toMatchObject({ status: 404 });
    const claimKey = randomUUID();
    expect((await upi.reportUpiOutcome(user, attempt.attemptId, { idempotencyKey: claimKey, result: 'claim' })).launchAllowed).toBe(true);
    expect((await upi.reportUpiOutcome(user, attempt.attemptId, { idempotencyKey: claimKey, result: 'claim' })).launchAllowed).toBe(false);
    const returned = await upi.reportUpiOutcome(user, attempt.attemptId, { idempotencyKey: randomUUID(), result: 'success' });
    expect(returned).toMatchObject({ evidenceStatus: 'unverified', status: 'awaiting_confirmation', ledgerId: null });
    expect(await prisma.financialRecord.count({ where: { userId: user, id: 'upi:' + attempt.attemptId } })).toBe(0);
    const date = todayIndia();
    const content = 'date,amount,direction,reference\n' + date + ',7.25,debit,BILL32';
    const preview = await upi.previewStatement(user, { content });
    expect(preview.rows[0].candidates).toEqual([expect.objectContaining({ attemptId: attempt.attemptId, referenceMatched: true })]);
    const record = { idempotencyKey: randomUUID(), expectedRevision: returned.revision, postingDate: date, paymentMethodId: method, statement: preview.rows[0].row };
    const [first, second] = await Promise.all([upi.recordUpiExpense(user, attempt.attemptId, record), upi.recordUpiExpense(user, attempt.attemptId, record)]);
    expect(first).toEqual(second);
    expect(first).toMatchObject({ evidenceStatus: 'statement', status: 'recorded_manually', reviewRequired: false });
    expect(await prisma.financialRecord.count({ where: { userId: user, id: first.ledgerId! } })).toBe(1);
    expect((await upi.previewStatement(user, { content })).rows[0].duplicate).toBe(true);
  });
});

it('parses exact INR statement amounts and rejects invalid debit rows', () => {
  expect(parseStatement('date,amount,direction,reference\n2026-10-10,7.5,debit,"UPI 321"')).toEqual([
    { date: '2026-10-10', amountPaise: 750, direction: 'debit', reference: 'UPI321' },
  ]);
  expect(() => parseStatement('date,amount,direction,reference\n2026-02-31,7.50,debit,UPI')).toThrow('Invalid debit');
});

it('rejects overlarge streamed JSON using bytes', async () => {
  const { body } = await import('../src/lib/server/http');
  await expect(body(new Request('https://fintrack.test', { method: 'POST', body: '{"value":"₹"}' }), 14)).rejects.toMatchObject({ status: 413 });
});
