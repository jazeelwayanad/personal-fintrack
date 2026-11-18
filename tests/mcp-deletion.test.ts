import { randomUUID } from 'node:crypto';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import type { McpGrant } from '@prisma/client';
import { kinds, type Document } from '../src/lib/finance/model';
import { ApiError } from '../src/lib/server/api-error';

const mocks = vi.hoisted(() => ({
  grant: vi.fn(), row: vi.fn(), rows: vi.fn(), previous: vi.fn(), saveResult: vi.fn(),
  linked: vi.fn(), apply: vi.fn(), audit: vi.fn(), ledger: vi.fn(), imported: vi.fn(),
}));
vi.mock('@/lib/prisma', () => ({ prisma: {
  mcpGrant: { findFirst: mocks.grant }, financialRecord: { findMany: mocks.rows }, mcpAuditEvent: { create: mocks.audit },
} }));
vi.mock('@/lib/server/sync', () => ({
  withLedger: mocks.ledger, applyLedgerMutation: mocks.apply, ensureImported: mocks.imported,
  wire: (row: Document) => ({ id: row.id, kind: row.kind, data: row.data, revision: row.revision, deleted: row.deleted }),
}));
import { financeMcpServer, writeTools } from '../src/lib/server/mcp-tools';

const grant = { id: 'grant', userId: 'owner', scopes: ['ledger:read', 'ledger:write'] } as McpGrant;
const sessions: { client: Client; server: ReturnType<typeof financeMcpServer> }[] = [];
async function connect(write = true) {
  const server = financeMcpServer(grant, write);
  const client = new Client({ name: 'deletion-test', version: '1' });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(b);
  await client.connect(a);
  sessions.push({ client, server });
  return client;
}
const command = () => ({ idempotencyKey: randomUUID(), id: 'record', expectedRevision: 4 });
const row = (kind: Document['kind'] = 'category'): Document => ({ id: 'record', kind, data: { name: 'Example' }, revision: 4, deleted: false });
beforeEach(() => {
  vi.resetAllMocks();
  vi.stubEnv('MCP_WRITE_ENABLED', 'true');
  vi.stubEnv('MCP_STATE_KEY', 'a1'.repeat(32));
  mocks.grant.mockResolvedValue({ id: grant.id });
  mocks.audit.mockResolvedValue({});
  mocks.row.mockResolvedValue(row());
  mocks.rows.mockResolvedValue([]);
  mocks.previous.mockResolvedValue(null);
  mocks.linked.mockResolvedValue(null);
  mocks.ledger.mockImplementation(async (_userId, run) => run({
    mcpGrant: { findFirst: mocks.grant }, financialRecord: { findFirst: mocks.row },
    syncMutation: { findUnique: mocks.previous, update: mocks.saveResult },
    upiPaymentAttempt: { findUnique: mocks.linked }, mcpAuditEvent: { create: mocks.audit },
  }));
  mocks.apply.mockImplementation(async (_tx, _userId, mutation) => ({
    accepted: true, records: mutation.changes.map((change: Document) => ({ ...change, revision: 5 })),
  }));
});
afterEach(async () => {
  for (const { client, server } of sessions.splice(0)) { await client.close(); await server.close(); }
  vi.unstubAllEnvs();
});

it('exposes deletion only to writers and marks it destructive for client confirmation', async () => {
  const reader = await connect(false), writer = await connect();
  expect((await reader.listTools()).tools.some(tool => tool.name === 'delete_ledger_record')).toBe(false);
  expect((await writer.listTools()).tools.find(tool => tool.name === 'delete_ledger_record')?.annotations)
    .toMatchObject({ readOnlyHint: false, destructiveHint: true, idempotentHint: true });
  expect(writeTools.has('delete_ledger_record')).toBe(true);
});

it('deletes every ledger kind through the account-scoped sync mutation, preserving data and auditing once', async () => {
  const client = await connect();
  for (const kind of kinds) {
    const record = row(kind);
    mocks.row.mockResolvedValue(record);
    const result = await client.callTool({ name: 'delete_ledger_record', arguments: command() });
    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toEqual({ id: record.id, kind, revision: 5, deleted: true });
    expect(mocks.apply.mock.calls.at(-1)?.slice(1)).toEqual(['owner', expect.objectContaining({
      changes: [expect.objectContaining({ ...record, deleted: true, baseRevision: 4 })],
    })]);
    expect(mocks.row.mock.calls.at(-1)?.[0]).toEqual({ where: { userId: 'owner', id: 'record', deleted: false } });
  }
  expect(mocks.audit.mock.calls.filter(([arg]) => arg.data.operation === 'delete_ledger_record' && arg.data.outcome === 'accepted')).toHaveLength(kinds.length);
});

it('rejects stale revisions, missing/foreign records, linked payments and revoked write access', async () => {
  const client = await connect();
  mocks.row.mockResolvedValue({ ...row(), revision: 6 });
  expect((await client.callTool({ name: 'delete_ledger_record', arguments: command() })).isError).toBe(true);
  mocks.row.mockResolvedValue(null);
  expect((await client.callTool({ name: 'delete_ledger_record', arguments: command() })).isError).toBe(true);
  mocks.row.mockResolvedValue({ ...row('transaction'), data: { occurrenceId: 'paid-occurrence' } });
  expect((await client.callTool({ name: 'delete_ledger_record', arguments: command() })).isError).toBe(true);
  mocks.row.mockResolvedValue(row('transaction'));
  mocks.linked.mockResolvedValue({ id: 'upi-attempt' });
  expect((await client.callTool({ name: 'delete_ledger_record', arguments: command() })).isError).toBe(true);
  mocks.grant.mockResolvedValue(null);
  expect((await client.callTool({ name: 'delete_ledger_record', arguments: command() })).isError).toBe(true);
  expect(mocks.apply).not.toHaveBeenCalled();
});

it('returns reference-validation errors and retries an accepted deletion without applying it twice', async () => {
  const client = await connect();
  mocks.apply.mockRejectedValueOnce(new ApiError(400, 'This item is still in use.'));
  const failed = await client.callTool({ name: 'delete_ledger_record', arguments: command() });
  expect(failed.isError).toBe(true);
  expect(failed.content).toEqual([expect.objectContaining({ text: expect.stringContaining('still in use') })]);
  const input = command();
  const first = await client.callTool({ name: 'delete_ledger_record', arguments: input });
  mocks.previous.mockResolvedValue({ result: mocks.saveResult.mock.calls.at(-1)![0].data.result });
  const second = await client.callTool({ name: 'delete_ledger_record', arguments: input });
  expect(second.structuredContent).toEqual(first.structuredContent);
  expect(mocks.apply).toHaveBeenCalledTimes(2);
  expect((await client.callTool({ name: 'delete_ledger_record', arguments: { ...input, id: 'different-record' } })).isError).toBe(true);
});

it('lists owner-scoped records and rejects pagination cursors reused for another kind', async () => {
  const client = await connect(false);
  mocks.rows.mockResolvedValue([row('plan'), { ...row('plan'), id: 'second' }]);
  const first = await client.callTool({ name: 'list_ledger_records', arguments: { kind: 'plan', limit: 1 } });
  expect(first.isError).not.toBe(true);
  const page = first.structuredContent as { items: unknown[]; nextCursor: string };
  expect(page.items).toHaveLength(1);
  expect(mocks.rows).toHaveBeenCalledWith({ where: { userId: 'owner', deleted: false, kind: 'plan' }, orderBy: { id: 'asc' }, take: 2 });
  expect((await client.callTool({ name: 'list_ledger_records', arguments: { kind: 'category', limit: 1, cursor: page.nextCursor } })).isError).toBe(true);
});
