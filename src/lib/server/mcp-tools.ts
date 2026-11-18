import { createHash } from 'node:crypto';
import type { FinancialRecord, McpGrant } from '@prisma/client';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { prisma } from '@/lib/prisma';
import { checkSpending, monthlyForecast, occurrences, summary, todayIndia } from '@/lib/finance/engine';
import { dateSchema, kinds, type Document, type Mutation, number as n, string as s } from '@/lib/finance/model';
import { ApiError } from './api-error';
import { fingerprint, secretKey } from './integration-secret';
import { readCursor, signCursor } from './cursor';
import { listUpiAttempts, upiEnabled } from './upi';
import { mcpWritesEnabled, paymentsScope, readScope } from './mcp-auth';
import { applyLedgerMutation, ensureImported, wire, withLedger } from './sync';

const type = z.enum(['income', 'expense']);
const id = z.string().min(1).max(200);
const paise = z.number().int();
const positivePaise = paise.positive().max(1_000_000_000_000);
const timestamp = z.iso.datetime();
const windowFields = {
  from: dateSchema, to: dateSchema, limit: z.number().int().min(1).max(100).default(25),
  cursor: z.string().max(1000).optional(),
};
const windowValid = ({ from, to }: { from: string; to: string }) => from < to
  && Date.parse(to) - Date.parse(from) <= 366 * 86400000;
const page = <T extends z.ZodType>(item: T) => z.strictObject({ items: z.array(item), nextCursor: z.string().nullable(), syncedAt: timestamp });
const optionOutput = z.strictObject({
  categories: z.array(z.strictObject({ id, name: z.string(), type })),
  paymentMethods: z.array(z.strictObject({ id, name: z.string() })),
  syncedAt: timestamp,
});
const transactionOutput = z.strictObject({
  id, revision: z.number().int(), date: dateSchema, type, amountPaise: paise,
  categoryId: id, paymentMethodId: id, description: z.string().optional(),
});
const scheduleState = z.enum(['paid', 'received', 'skipped', 'overdue', 'due', 'upcoming']);

async function readLedger(userId: string) {
  await ensureImported(userId);
  const rows = await prisma.financialRecord.findMany({ where: { userId, deleted: false } });
  return { records: rows.map(wire), syncedAt: new Date().toISOString() };
}

async function readTransactionWindow(userId: string, from: string, to: string) {
  await ensureImported(userId);
  const rows = await prisma.$queryRaw<FinancialRecord[]>`
    SELECT * FROM "FinancialRecord"
    WHERE "userId" = ${userId} AND NOT "deleted"
      AND ("kind" IN ('category', 'paymentMethod')
        OR ("kind" = 'transaction' AND "data"->>'date' >= ${from} AND "data"->>'date' < ${to}))
  `;
  return { records: rows.map(wire), syncedAt: new Date().toISOString() };
}
function ledgerOptions(records: Document[], kind?: string) {
  return {
    categories: records.filter(r => r.kind === 'category' && (!kind || s(r.data, 'type') === kind))
      .map(r => ({ id: r.id, type: s(r.data, 'type'), name: s(r.data, 'name') })),
    paymentMethods: records.filter(r => r.kind === 'paymentMethod').map(r => ({ id: r.id, name: s(r.data, 'name') })),
  };
}
function orderedPage<T extends { id: string; date: string }>(
  rows: T[], userId: string, operation: string, input: { limit: number; cursor?: string },
) {
  const { limit, cursor, ...filter } = input;
  const context = { userId, operation, filter };
  const anchor = cursor ? readCursor(cursor, z.strictObject({ id, date: dateSchema }), context) : undefined;
  const compare = (a: { id: string; date: string }, b: { id: string; date: string }) =>
    a.date.localeCompare(b.date) || a.id.localeCompare(b.id);
  const candidates = rows.sort(compare).filter(row => !anchor || compare(row, anchor) > 0);
  const items = candidates.slice(0, limit);
  const last = items.at(-1);
  if (!last || candidates.length <= limit) return { items, nextCursor: null };
  return { items, nextCursor: signCursor({ id: last.id, date: last.date }, context) };
}
function result(value: Record<string, unknown>) {
  return { structuredContent: value, content: [{ type: 'text' as const, text: JSON.stringify(value) }] };
}
function issue(error: unknown) {
  const status = error instanceof ApiError ? error.status : error instanceof z.ZodError ? 400 : 500;
  const code = ({ 400: 'invalid_input', 403: 'not_found', 404: 'not_found', 409: 'conflict', 429: 'rate_limited' } as Record<number, string>)[status] ?? 'temporarily_unavailable';
  const message = error instanceof ApiError ? error.message : 'The request could not be completed.';
  return { code, message };
}
function audit(grant: McpGrant, operation: string, outcome: string, objectId?: string) {
  return { userId: grant.userId, clientId: grant.clientId, grantId: grant.id, operation, outcome, objectId };
}

export const writeTools = new Set(['create_transaction', 'update_transaction', 'delete_ledger_record']);
const patch = z.strictObject({ categoryId: id.optional(), paymentMethodId: id.optional(), description: z.string().max(1000).optional() });
const create = z.strictObject({
  idempotencyKey: z.uuid(), date: dateSchema, type, amountPaise: positivePaise,
  categoryId: id, paymentMethodId: id, description: z.string().max(1000).default(''),
});
const update = z.strictObject({
  idempotencyKey: z.uuid(), id, expectedRevision: z.number().int().positive(), patch,
}).refine(value => Object.keys(value.patch).length > 0, 'Supply at least one field to update.');
const remove = z.strictObject({ idempotencyKey: z.uuid(), id, expectedRevision: z.number().int().positive() });

async function writeTransaction(grant: McpGrant, operation: string, input: z.infer<typeof create> | z.infer<typeof update> | z.infer<typeof remove>) {
  const { userId } = grant;
  const requestHash = fingerprint(secretKey(process.env.MCP_STATE_KEY), input);
  const mutationId = 'mcp:' + createHash('sha256').update(JSON.stringify([userId, grant.id, operation, input.idempotencyKey])).digest('hex');
  return withLedger(userId, async tx => {
    const active = await tx.mcpGrant.findFirst({ where: { id: grant.id, userId, revokedAt: null, scopes: { has: 'ledger:write' } }, select: { id: true } });
    if (!active || !mcpWritesEnabled()) throw new ApiError(403, 'The write grant is unavailable.');
    const previous = await tx.syncMutation.findUnique({ where: { userId_id: { userId, id: mutationId } } });
    if (previous) {
      const saved = z.object({ requestHash: z.string(), response: z.record(z.string(), z.unknown()) }).parse(previous.result);
      if (saved.requestHash !== requestHash) throw new ApiError(409, 'This request key was already used.');
      return saved.response;
    }

    let change: Mutation['changes'][number];
    const deleting = operation === 'delete_ledger_record';
    if ('id' in input) {
      const row = await tx.financialRecord.findFirst({ where: { userId, id: input.id, ...(!deleting && { kind: 'transaction' }), deleted: false } });
      if (!row) throw new ApiError(404, 'Record not found.');
      if (!deleting && s(wire(row).data, 'date') > todayIndia()) throw new ApiError(400, 'Use a plan for future income or expenses.');
      if (row.revision !== input.expectedRevision) throw new ApiError(409, 'Record changed. Read it again before changing it.');
      if (row.kind === 'transaction' && (s(wire(row).data, 'occurrenceId') || await tx.upiPaymentAttempt.findUnique({ where: { userId_ledgerId: { userId, ledgerId: row.id } }, select: { id: true } }))) {
        throw new ApiError(409, 'Edit linked payments in FinTrack.');
      }
      change = { ...wire(row), baseRevision: row.revision, data: { ...wire(row).data, ...('patch' in input ? input.patch : {}) }, deleted: deleting };
    } else {
      if (input.date > todayIndia()) throw new ApiError(400, 'Choose a date on or before today.');
      const { date, type, amountPaise, categoryId, paymentMethodId, description } = input;
      change = {
        id: mutationId, kind: 'transaction', baseRevision: 0, deleted: false,
        data: { date, type, amount: amountPaise, categoryId, paymentMethodId, description },
      };
    }

    const mutation = await applyLedgerMutation(tx, userId, { id: mutationId, changes: [change] });
    if (!mutation.accepted) throw new ApiError(409, 'The transaction changed.');
    const [record] = mutation.records;
    const response = deleting
      ? { id: record.id, kind: record.kind, revision: record.revision, deleted: true }
      : 'patch' in input
      ? { id: record.id, revision: record.revision, categoryId: s(record.data, 'categoryId'), paymentMethodId: s(record.data, 'paymentMethodId'), source: 'manual' }
      : { id: record.id, revision: record.revision, date: s(record.data, 'date'), type: s(record.data, 'type'), amountPaise: n(record.data, 'amount'), source: 'manual' };
    await tx.syncMutation.update({ where: { userId_id: { userId, id: mutationId } }, data: { result: { requestHash, response } } });
    await tx.mcpAuditEvent.create({ data: audit(grant, operation, 'accepted', record.id) });
    return response;
  });
}

export function financeMcpServer(grant: McpGrant, write: boolean, payments = false) {
  const server = new McpServer({ name: 'FinTrack', version: '1.0.0' });
  function tool<I extends z.ZodObject, O extends z.ZodObject>(
    name: string, description: string, inputSchema: I, outputSchema: O, run: (input: z.output<I>) => Promise<unknown>,
  ) {
    const readOnly = !writeTools.has(name);
    server.registerTool<z.ZodObject, z.ZodObject>(name, {
      description, inputSchema, outputSchema,
      annotations: { readOnlyHint: readOnly, destructiveHint: name === 'delete_ledger_record', idempotentHint: true, openWorldHint: false },
    }, async (raw: unknown) => {
      try {
        const scope = name === 'list_upi_attempts' ? paymentsScope : readScope;
        const active = await prisma.mcpGrant.findFirst({ where: { id: grant.id, userId: grant.userId, revokedAt: null, scopes: { has: scope } }, select: { id: true } });
        if (!active) throw new ApiError(403, 'The connector grant is unavailable.');
        const parsed = outputSchema.parse(await run(z.parse(inputSchema, raw)));
        if (readOnly) await prisma.mcpAuditEvent.create({ data: audit(grant, name, 'accepted') });
        return result(parsed as Record<string, unknown>);
      } catch (error) {
        const failure = issue(error);
        await prisma.mcpAuditEvent.create({ data: audit(grant, name, failure.code) }).catch(() => {});
        return { isError: true, content: [{ type: 'text' as const, text: JSON.stringify(failure) }] };
      }
    });
  }

  tool('list_ledger_options', 'Find your income and expense categories and payment methods.', z.strictObject({ type: type.optional() }), optionOutput, async input => {
    const { records, syncedAt } = await readLedger(grant.userId);
    return { ...ledgerOptions(records, input.type), syncedAt };
  });
  tool('list_ledger_records', 'Find synced ledger records of any kind, with IDs and revisions needed before deletion. Amounts in record data are in paise.', z.strictObject({
    kind: z.enum(kinds).optional(), limit: z.number().int().min(1).max(100).default(25), cursor: z.string().max(1000).optional(),
  }), page(z.strictObject({ id, kind: z.enum(kinds), revision: z.number().int(), data: z.record(z.string(), z.unknown()) })), async input => {
    await ensureImported(grant.userId);
    const context = { userId: grant.userId, operation: 'ledger-records', filter: { kind: input.kind, limit: input.limit } };
    const after = input.cursor ? readCursor(input.cursor, id, context) : undefined;
    const rows = await prisma.financialRecord.findMany({
      where: { userId: grant.userId, deleted: false, ...(input.kind && { kind: input.kind }), ...(after && { id: { gt: after } }) },
      orderBy: { id: 'asc' }, take: input.limit + 1,
    });
    const items = rows.slice(0, input.limit).map(row => ({ id: row.id, kind: row.kind, revision: row.revision, data: row.data }));
    return { items, nextCursor: rows.length > input.limit ? signCursor(items.at(-1)!.id, context) : null, syncedAt: new Date().toISOString() };
  });
  tool('list_transactions', 'Search synced entries within an inclusive start and exclusive end, up to 366 days.', z.strictObject({
    ...windowFields, type: type.optional(), categoryId: id.optional(), paymentMethodId: id.optional(),
    query: z.string().trim().min(1).max(120).optional(), includeDescriptions: z.boolean().default(false),
  }).refine(windowValid, 'Choose a valid date window of up to 366 days.'), page(transactionOutput), async input => {
    const { records, syncedAt } = await readTransactionWindow(grant.userId, input.from, input.to);
    const labels = new Map(records.filter(row => row.kind === 'category' || row.kind === 'paymentMethod').map(row => [row.id, s(row.data, 'name')]));
    const query = input.query?.toLowerCase();
    const matches = records.filter(row => {
      if (row.kind !== 'transaction') return false;
      const date = s(row.data, 'date'), category = s(row.data, 'categoryId'), method = s(row.data, 'paymentMethodId');
      return date >= input.from && date < input.to && (!input.type || input.type === s(row.data, 'type'))
        && (!input.categoryId || input.categoryId === category) && (!input.paymentMethodId || input.paymentMethodId === method)
        && (!query || [s(row.data, 'description'), labels.get(category), labels.get(method)].some(value => value?.toLowerCase().includes(query)));
    }).map(row => ({
      id: row.id, revision: row.revision, date: s(row.data, 'date'), type: s(row.data, 'type'), amountPaise: n(row.data, 'amount'),
      categoryId: s(row.data, 'categoryId'), paymentMethodId: s(row.data, 'paymentMethodId'),
      ...(input.includeDescriptions ? { description: s(row.data, 'description') } : {}),
    }));
    return { ...orderedPage(matches, grant.userId, 'transactions', input), syncedAt };
  });
  tool('get_finance_summary', 'Read payday-cycle totals, budgets, optional calendar forecast and spending check.', z.strictObject({
    forecastMonth: z.string().regex(/^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$/).optional(),
    categoryId: id.optional(), checkAmountPaise: positivePaise.optional(),
  }).refine(value => !!value.categoryId === !!value.checkAmountPaise, 'Supply both category and amount for a spending check.'), z.strictObject({
    currency: z.literal('INR'), cycle: z.strictObject({ start: dateSchema, end: dateSchema }),
    balancePaise: paise, incomePaise: paise, expensePaise: paise, commitmentsPaise: paise, savingsPaise: paise, reservedBudgetsPaise: paise, availablePaise: paise,
    budgets: z.array(z.strictObject({ categoryId: id, plannedPaise: paise, spentPaise: paise, remainingPaise: paise })),
    forecast: z.strictObject({ month: z.string(), incomePaise: paise, expensePaise: paise, count: z.number().int() }).optional(),
    spendingCheck: z.strictObject({ allowed: z.boolean(), maximumPaise: paise, shortfallPaise: paise }).optional(), syncedAt: timestamp,
  }), async input => {
    const { records, syncedAt } = await readLedger(grant.userId);
    const today = todayIndia();
    const totals = summary(records, today);
    const forecast = input.forecastMonth ? monthlyForecast(records, today, input.forecastMonth) : undefined;
    if (input.categoryId && !records.some(row => row.id === input.categoryId && row.kind === 'category' && row.data.type === 'expense')) {
      throw new ApiError(404, 'Expense category not found.');
    }
    const check = input.categoryId && input.checkAmountPaise ? checkSpending(records, today, input.checkAmountPaise, input.categoryId) : undefined;
    return {
      currency: 'INR', cycle: totals.period, balancePaise: totals.balance, incomePaise: totals.income, expensePaise: totals.expenses,
      commitmentsPaise: totals.commitments, savingsPaise: totals.savings, reservedBudgetsPaise: totals.reservedBudgets, availablePaise: totals.unallocated,
      budgets: totals.budgets.map(budget => ({ categoryId: budget.categoryId, plannedPaise: budget.planned, spentPaise: budget.spent, remainingPaise: budget.remaining })),
      ...(forecast && { forecast: { month: input.forecastMonth, incomePaise: forecast.income, expensePaise: forecast.expenses, count: forecast.count } }),
      ...(check && { spendingCheck: { allowed: check.allowed, maximumPaise: check.maximum, shortfallPaise: check.shortfall } }), syncedAt,
    };
  });
  tool('list_scheduled_payments', 'Read scheduled entries and their ledger-derived status.', z.strictObject({
    ...windowFields, type: type.optional(), state: scheduleState.optional(),
  }).refine(windowValid, 'Choose a valid date window of up to 366 days.'), page(z.strictObject({
    occurrenceId: id, planId: id, name: z.string(), dueDate: dateSchema, type, amountPaise: paise, categoryId: id, state: scheduleState, transactionId: id.optional(),
  })), async input => {
    const { records, syncedAt } = await readLedger(grant.userId);
    const matches = occurrences(records, todayIndia(), input.to).filter(row => {
      const date = s(row.data, 'date');
      return date >= input.from && date < input.to && (!input.type || input.type === row.data.type) && (!input.state || input.state === row.state);
    }).map(row => ({
      id: row.id, date: s(row.data, 'date'),
      value: {
        occurrenceId: row.id, planId: s(row.data, 'planId'), name: s(row.data, 'name'), dueDate: s(row.data, 'date'),
        type: s(row.data, 'type'), amountPaise: n(row.data, 'amount'), categoryId: s(row.data, 'categoryId'),
        state: row.state, transactionId: row.transactionId,
      },
    }));
    const listing = orderedPage(matches, grant.userId, 'schedule', input);
    return { items: listing.items.map(row => row.value), nextCursor: listing.nextCursor, syncedAt };
  });
  if (payments && upiEnabled()) {
    tool('list_upi_attempts', 'Read your payment attempts and evidence status. A reported app outcome does not verify a debit.', z.strictObject({
      ...windowFields,
      status: z.enum(['ready', 'awaiting_confirmation', 'launch_failed', 'recorded_manually']).optional(),
      evidence: z.enum(['unverified', 'manual', 'statement']).optional(),
    }).refine(windowValid, 'Choose a valid date window of up to 366 days.'), page(z.strictObject({
      attemptId: z.uuid(), amountPaise: paise, date: dateSchema, categoryId: id,
      status: z.enum(['ready', 'awaiting_confirmation', 'launch_failed', 'recorded_manually']),
      evidence: z.enum(['unverified', 'manual', 'statement']), ledgerId: id.nullable(), reviewRequired: z.boolean(),
    })), async input => {
      const { cursor, ...filter } = input;
      const context = { userId: grant.userId, operation: 'upi', filter };
      const after = cursor ? readCursor(cursor, z.uuid(), context) : undefined;
      const params = new URLSearchParams({ from: input.from, to: input.to, limit: String(input.limit) });
      if (input.status) params.set('status', input.status);
      if (input.evidence) params.set('evidence', input.evidence);
      if (after) params.set('cursor', after);
      const listing = await listUpiAttempts(grant.userId, params, false);
      return {
        items: listing.items.map(item => ({
          attemptId: item.attemptId, amountPaise: item.amountPaise,
          date: new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(item.createdAt)),
          categoryId: item.categoryId, status: item.status, evidence: item.evidenceStatus,
          ledgerId: item.ledgerId, reviewRequired: item.reviewRequired,
        })),
        nextCursor: listing.nextCursor ? signCursor(listing.nextCursor, context) : null,
        syncedAt: new Date().toISOString(),
      };
    });
  }
  if (write) {
    tool('create_transaction', 'Record income already received or an expense already paid. Does not move money.', create, z.strictObject({
      id, revision: z.number().int(), date: dateSchema, type, amountPaise: paise, source: z.literal('manual'),
    }), input => writeTransaction(grant, 'create_transaction', input));
    tool('update_transaction', 'Correct the classification or note on an unlinked manual transaction.', update, z.strictObject({
      id, revision: z.number().int(), categoryId: id, paymentMethodId: id, source: z.literal('manual'),
    }), input => writeTransaction(grant, 'update_transaction', input));
    tool('delete_ledger_record', 'Delete one ledger record after explicit user confirmation. First read its ID and revision with list_ledger_records. Preserves a sync tombstone and audit history. Rejects records still in use, plans with payment history, and linked payment transactions. Does not move money.', remove, z.strictObject({
      id, kind: z.enum(kinds), revision: z.number().int(), deleted: z.literal(true),
    }), input => writeTransaction(grant, 'delete_ledger_record', input));
  }

  for (const kind of ['categories', 'paymentMethods'] as const) {
    const uri = 'fintrack://ledger/' + (kind === 'categories' ? 'categories' : 'payment-methods');
    server.registerResource(kind, uri, { mimeType: 'application/json' }, async () => {
      const active = await prisma.mcpGrant.findFirst({ where: { id: grant.id, userId: grant.userId, revokedAt: null, scopes: { has: readScope } }, select: { id: true } });
      if (!active) throw new ApiError(403, 'The connector grant is unavailable.');
      const { records, syncedAt } = await readLedger(grant.userId);
      await prisma.mcpAuditEvent.create({ data: audit(grant, 'resource:' + kind, 'accepted') });
      return { contents: [{ uri, mimeType: 'application/json', text: JSON.stringify({ items: ledgerOptions(records)[kind], syncedAt }) }] };
    });
  }
  return server;
}
