import { normalizeStatementReference, parseStatement, statementRow } from '@/lib/finance/statement';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { UpiPaymentAttempt } from '@prisma/client';
import { prisma } from '@/lib/prisma';
import { dateSchema, type Change, number as n, string as s } from '@/lib/finance/model';
import { addDays, occurrences, todayIndia } from '@/lib/finance/engine';
import { ApiError } from './api-error';
import { fingerprint, openSealed, seal, secretKey } from './integration-secret';
import { applyLedgerMutation, type Tx, wire, withLedger } from './sync';

export const upiEnabled = () => process.env.UPI_HANDOFF_ENABLED === 'true';
function dataKey() {
  if (!upiEnabled()) throw new ApiError(404, 'UPI payments are unavailable.');
  return secretKey(process.env.UPI_DATA_KEY);
}
const id = z.string().min(1).max(200);
const key = z.uuid();
const states = ['ready', 'awaiting_confirmation', 'launch_failed', 'recorded_manually'] as const;
const appResults = ['success', 'failed', 'cancelled', 'pending', 'unknown'] as const;
const createInput = z.strictObject({
  idempotencyKey: key,
  payeeVpa: z.string().max(255).regex(/^[a-zA-Z0-9._+-]+@[a-zA-Z0-9.-]+$/),
  payeeName: z.string().trim().max(120).optional(),
  amountMode: z.enum(['fixed', 'open']),
  amountPaise: z.number().int().positive().max(1_000_000_000_000),
  categoryId: id,
  purpose: z.string().trim().min(1).max(200),
  reference: z.string().trim().max(120).optional(),
  occurrenceId: id.optional(),
});
const outcomeInput = z.strictObject({
  idempotencyKey: key,
  result: z.enum(['claim', 'launch_failed', ...appResults]),
});
const recordInput = z.strictObject({
  idempotencyKey: key,
  expectedRevision: z.number().int().positive(),
  paymentMethodId: id,
  existingExpenseId: id.optional(),
  postingDate: dateSchema.optional(),
  statement: statementRow.optional(),
}).refine(value => !!value.existingExpenseId !== !!value.postingDate, 'Choose an expense or posting date.');
const filters = z.strictObject({
  from: dateSchema.optional(),
  to: dateSchema.optional(),
  status: z.enum(states).optional(),
  reportedOutcome: z.enum(appResults).optional(),
  category: id.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(25),
  cursor: z.uuid().optional(),
}).refine(value => !value.from || !value.to || value.from < value.to, 'Invalid date range.');

function view(attempt: UpiPaymentAttempt, currentLedgerRevision?: number) {
  return {
    attemptId: attempt.id, revision: attempt.revision, status: attempt.status, createdAt: attempt.createdAt.toISOString(),
    updatedAt: attempt.updatedAt.toISOString(), amountMode: attempt.amountMode, amountPaise: Number(attempt.amountPaise),
    categoryId: attempt.categoryId, purpose: attempt.purpose, occurrenceId: attempt.occurrenceId, ledgerId: attempt.ledgerId,
    reportedOutcome: attempt.reportedOutcome, evidenceStatus: attempt.evidenceStatus,
    reviewRequired: !!attempt.ledgerId && attempt.recordedLedgerRevision !== currentLedgerRevision,
  };
}
async function attemptFor(db: Pick<Tx, 'upiPaymentAttempt'>, userId: string, id: string) {
  const attempt = await db.upiPaymentAttempt.findFirst({ where: { id, userId } });
  if (!attempt) throw new ApiError(404, 'Payment attempt not found.');
  return attempt;
}
async function revisions(userId: string, attempts: UpiPaymentAttempt[], secret: Buffer) {
  const ids = attempts.flatMap(a => a.ledgerId ? [a.ledgerId] : []);
  const rows = ids.length ? await prisma.financialRecord.findMany({ where: { userId, id: { in: ids }, deleted: false }, select: { id: true, revision: true } }) : [];
  const byId = new Map(rows.map(row => [row.id, row.revision]));
  return attempts.map(attempt => {
    const vpa = openSealed(secret, attempt.payeeVpa, userId + ':' + attempt.id + ':vpa');
    const [local, domain] = vpa.split('@');
    return {
      ...view(attempt, attempt.ledgerId ? byId.get(attempt.ledgerId) : undefined),
      payeeMasked: local.slice(0, 2) + '•••@' + domain,
    };
  });
}
async function expenseCategory(tx: Tx, userId: string, categoryId: string) {
  const category = await tx.financialRecord.findFirst({ where: { userId, id: categoryId, kind: 'category', deleted: false } });
  if (!category || s(wire(category).data, 'type') !== 'expense') throw new ApiError(400, 'Choose an expense category.');
}
async function scheduledExpense(tx: Tx, userId: string, occurrenceId: string, categoryId: string) {
  const today = todayIndia();
  const date = dateSchema.safeParse(occurrenceId.slice(-10));
  if (!date.success) throw new ApiError(400, 'Invalid scheduled payment.');
  const rows = await tx.financialRecord.findMany({ where: { userId, deleted: false, kind: { in: ['plan', 'occurrence', 'transaction'] } } });
  const occurrence = occurrences(rows.map(wire), today, date.data).find(o => o.id === occurrenceId);
  if (!occurrence || occurrence.state === 'skipped' || s(occurrence.data, 'type') !== 'expense' || s(occurrence.data, 'categoryId') !== categoryId) {
    throw new ApiError(400, 'Choose a valid scheduled expense.');
  }
  return occurrence;
}

export async function createUpiAttempt(userId: string, input: unknown) {
  const secret = dataKey();
  const { idempotencyKey, payeeVpa, reference, ...data } = createInput.parse(input);
  const requestHash = fingerprint(secret, { ...data, payeeVpa, reference });
  return withLedger(userId, async tx => {
    const previous = await tx.upiPaymentAttempt.findUnique({ where: { userId_createKey: { userId, createKey: idempotencyKey } } });
    if (previous) {
      if (previous.requestHash !== requestHash) throw new ApiError(409, 'This request key was already used.');
      return view(previous, previous.recordedLedgerRevision ?? undefined);
    }
    await expenseCategory(tx, userId, data.categoryId);
    if (data.occurrenceId) {
      const payment = await scheduledExpense(tx, userId, data.occurrenceId, data.categoryId);
      if (payment.paid) throw new ApiError(409, 'This scheduled payment already has an expense.');
    }
    const attemptId = randomUUID();
    const context = userId + ':' + attemptId;
    const attempt = await tx.upiPaymentAttempt.create({ data: {
      ...data, id: attemptId, userId, createKey: idempotencyKey, requestHash,
      amountPaise: BigInt(data.amountPaise),
      payeeName: data.payeeName ? seal(secret, data.payeeName, context + ':name') : undefined,
      payeeVpa: seal(secret, payeeVpa, context + ':vpa'),
      reference: reference ? seal(secret, reference, context + ':reference') : undefined,
      referenceMatchKey: reference ? referenceKey(secret, userId, reference) : undefined,
    } });
    return view(attempt);
  });
}

export async function listUpiAttempts(userId: string, params: URLSearchParams) {
  const secret = dataKey();
  const input = filters.parse(Object.fromEntries(params));
  const where = {
    userId, status: input.status, reportedOutcome: input.reportedOutcome, categoryId: input.category,
    createdAt: {
      gte: input.from ? new Date(input.from + 'T00:00:00+05:30') : undefined,
      lt: input.to ? new Date(input.to + 'T00:00:00+05:30') : undefined,
    },
  };
  if (input.cursor && !await prisma.upiPaymentAttempt.findFirst({ where: { ...where, id: input.cursor }, select: { id: true } })) {
    throw new ApiError(400, 'Invalid history cursor.');
  }
  const rows = await prisma.upiPaymentAttempt.findMany({
    where, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: input.limit + 1,
    ...(input.cursor ? { cursor: { id: input.cursor }, skip: 1 } : {}),
  });
  const page = rows.slice(0, input.limit);
  return { items: await revisions(userId, page, secret), nextCursor: rows.length > input.limit ? page.at(-1)!.id : null };
}

export async function readUpiAttempt(userId: string, attemptId: string) {
  const secret = dataKey();
  const [result] = await revisions(userId, [await attemptFor(prisma, userId, attemptId)], secret);
  return result;
}

async function replayEvidence(tx: Tx, attemptId: string, source: string, requestKey: string, requestHash: string) {
  const event = await tx.upiPaymentEvidence.findUnique({ where: { attemptId_source_requestKey: { attemptId, source, requestKey } } });
  if (event && event.requestHash !== requestHash) throw new ApiError(409, 'This request key was already used.');
  return event;
}

export async function reportUpiOutcome(userId: string, attemptId: string, input: unknown) {
  const secret = dataKey();
  const { idempotencyKey, result } = outcomeInput.parse(input);
  const requestHash = fingerprint(secret, result);
  return withLedger(userId, async tx => {
    const attempt = await attemptFor(tx, userId, attemptId);
    const event = await replayEvidence(tx, attemptId, 'app', idempotencyKey, requestHash);
    if (event) return { ...view(attempt, attempt.recordedLedgerRevision ?? undefined), launchAllowed: false };
    const claiming = result === 'claim';
    if (claiming ? !['ready', 'launch_failed'].includes(attempt.status) : attempt.status !== 'awaiting_confirmation') {
      throw new ApiError(409, 'Check the status in your UPI app before continuing.');
    }
    const updated = await tx.upiPaymentAttempt.update({ where: { id: attemptId }, data: {
      revision: { increment: 1 },
      status: result === 'launch_failed' ? 'launch_failed' : 'awaiting_confirmation',
      reportedOutcome: claiming || result === 'launch_failed' ? null : result,
    } });
    await tx.upiPaymentEvidence.create({ data: { attemptId, source: 'app', requestKey: idempotencyKey, requestHash, result } });
    return { ...view(updated), launchAllowed: claiming };
  });
}

export async function recordUpiExpense(userId: string, attemptId: string, input: unknown) {
  const secret = dataKey();
  const { idempotencyKey, ...data } = recordInput.parse(input);
  const requestHash = fingerprint(secret, data);
  return withLedger(userId, async tx => {
    const attempt = await attemptFor(tx, userId, attemptId);
    const event = await replayEvidence(tx, attemptId, 'manual', idempotencyKey, requestHash);
    if (event) return view(attempt, attempt.recordedLedgerRevision ?? undefined);
    if (attempt.ledgerId || attempt.revision !== data.expectedRevision) throw new ApiError(409, 'This attempt changed. Refresh its history.');
    if (attempt.status !== 'awaiting_confirmation') throw new ApiError(409, 'Open the payment app before recording this attempt.');
    await expenseCategory(tx, userId, attempt.categoryId);
    const method = await tx.financialRecord.findFirst({ where: { userId, id: data.paymentMethodId, kind: 'paymentMethod', deleted: false } });
    if (!method) throw new ApiError(400, 'Choose a valid payment method.');

    const ledgerId = data.existingExpenseId ?? 'upi:' + attempt.id;
    const binding = await tx.upiPaymentAttempt.findUnique({ where: { userId_ledgerId: { userId, ledgerId } } });
    if (binding) throw new ApiError(409, 'This expense is already linked to another attempt.');
    const row = await tx.financialRecord.findUnique({ where: { userId_id: { userId, id: ledgerId } } });
    const amountPaise = Number(attempt.amountPaise);
    let importedKey: string | undefined;
    if (data.statement) {
      const { statement } = data;
      if (statement.amountPaise !== amountPaise || !matchesDate(attempt.createdAt, statement.date)
        || statement.date > todayIndia() || (data.postingDate && data.postingDate !== statement.date)
        || (data.existingExpenseId && (!row || s(wire(row).data, 'date') !== statement.date))) {
        throw new ApiError(400, 'The statement debit does not match this attempt.');
      }
      importedKey = fingerprint(secret, statement);
      const used = await tx.upiPaymentEvidence.findUnique({ where: { statementOwnerId_statementKey: { statementOwnerId: userId, statementKey: importedKey } } });
      if (used) throw new ApiError(409, 'This statement debit has already been used.');
    }
    const occurrence = attempt.occurrenceId ? await scheduledExpense(tx, userId, attempt.occurrenceId, attempt.categoryId) : undefined;
    if (occurrence?.transactionId && occurrence.transactionId !== ledgerId) throw new ApiError(409, 'Link the existing scheduled expense.');
    if (data.postingDate && data.postingDate > todayIndia()) throw new ApiError(400, 'Choose a posting date on or before today.');
    let ledgerRevision = row?.revision;
    if (data.existingExpenseId) {
      const value = row && wire(row).data;
      if (!row || !value || row.deleted || row.kind !== 'transaction' || s(value, 'type') !== 'expense'
        || n(value, 'amount') !== amountPaise || s(value, 'categoryId') !== attempt.categoryId
        || s(value, 'paymentMethodId') !== data.paymentMethodId || s(value, 'date') > todayIndia()
        || (s(value, 'occurrenceId') && s(value, 'occurrenceId') !== occurrence?.id)) {
        throw new ApiError(400, 'Choose a matching expense with the same amount, category and payment method.');
      }
    } else if (row) {
      throw new ApiError(409, 'An expense with this identity already exists.');
    }
    if (!row || (occurrence && !s(wire(row).data, 'occurrenceId'))) {
      const changes: Change[] = [{
        id: ledgerId, kind: 'transaction', baseRevision: row?.revision ?? 0, deleted: false,
        data: {
          ...(row ? wire(row).data : { type: 'expense', amount: amountPaise, date: data.postingDate, categoryId: attempt.categoryId, paymentMethodId: data.paymentMethodId, description: attempt.purpose }),
          occurrenceId: occurrence?.id ?? null,
        },
      }];
      if (occurrence && !occurrence.revision) changes.push({ id: occurrence.id, kind: 'occurrence', baseRevision: 0, deleted: false, data: occurrence.data });
      const mutation = await applyLedgerMutation(tx, userId, { id: 'upi:' + attempt.id, changes });
      if (!mutation.accepted) throw new ApiError(409, 'The ledger changed. Refresh and try again.');
      ledgerRevision = mutation.records[0].revision;
    }
    const updated = await tx.upiPaymentAttempt.update({ where: { id: attemptId }, data: {
      status: 'recorded_manually', evidenceStatus: importedKey ? 'statement' : 'manual', ledgerId, recordedLedgerRevision: ledgerRevision,
      revision: { increment: 1 },
    } });
    await tx.upiPaymentEvidence.create({ data: { attemptId, source: 'manual', requestKey: idempotencyKey, requestHash, result: 'recorded', statementOwnerId: importedKey ? userId : undefined, statementKey: importedKey } });
    return view(updated, ledgerRevision);
  });
}

const attemptDay = (date: Date) => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(date);
function matchesDate(createdAt: Date, postedDate: string) {
  const date = attemptDay(createdAt);
  return postedDate >= addDays(date, -2) && postedDate <= addDays(date, 2);
}
function referenceKey(secret: Buffer, userId: string, reference: string) {
  return fingerprint(secret, { userId, reference: normalizeStatementReference(reference) });
}
export async function previewStatement(userId: string, input: unknown) {
  const secret = dataKey();
  const { content } = z.strictObject({ content: z.string().min(1).max(150_000) }).parse(input);
  let rows;
  try { rows = parseStatement(content); }
  catch (error) { throw new ApiError(400, error instanceof Error ? error.message : 'Invalid statement.'); }
  if (!rows.length) return { rows: [] };
  const dates = rows.map(row => row.date).sort();
  const keys = rows.map(row => fingerprint(secret, row));
  const [attempts, used] = await Promise.all([
    prisma.upiPaymentAttempt.findMany({
      where: { userId, status: 'awaiting_confirmation',
        createdAt: {
          gte: new Date(addDays(dates[0], -2) + 'T00:00:00+05:30'),
          lt: new Date(addDays(dates[dates.length - 1], 3) + 'T00:00:00+05:30'),
        },
        amountPaise: { in: [...new Set(rows.map(row => BigInt(row.amountPaise)))] } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: 1001,
    }),
    prisma.upiPaymentEvidence.findMany({ where: { statementOwnerId: userId, statementKey: { in: keys } }, select: { statementKey: true } }),
  ]);
  if (attempts.length > 1000) throw new ApiError(400, 'Import a smaller statement date range.');
  const seen = new Set(used.map(row => row.statementKey));
  return { rows: rows.map((row, index) => {
    const duplicate = seen.has(keys[index]);
    seen.add(keys[index]);
    const ref = referenceKey(secret, userId, row.reference);
    const candidates = duplicate ? [] : attempts.filter(attempt => Number(attempt.amountPaise) === row.amountPaise && matchesDate(attempt.createdAt, row.date))
      .map(attempt => ({ attemptId: attempt.id, revision: attempt.revision, purpose: attempt.purpose, referenceMatched: attempt.referenceMatchKey === ref }))
      .sort((a, b) => Number(b.referenceMatched) - Number(a.referenceMatched));
    return { row, duplicate, candidates };
  }) };
}
