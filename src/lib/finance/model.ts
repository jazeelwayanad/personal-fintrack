import { z } from 'zod';

export const kinds = ['transaction', 'category', 'paymentMethod', 'plan', 'occurrence', 'budget', 'preferences', 'adjustment'] as const;
export type Kind = typeof kinds[number];
export type Data = Record<string, unknown>;
export interface Document { id: string; kind: Kind; data: Data; revision: number; deleted: boolean }
export interface Change extends Omit<Document, 'revision'> { baseRevision: number }
export interface Mutation { id: string; changes: Change[] }
export const string = (d: Data, key: string, fallback = '') => typeof d[key] === 'string' ? d[key] as string : fallback;
export const number = (d: Data, key: string, fallback = 0) => typeof d[key] === 'number' ? d[key] as number : fallback;
export const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => v >= '2000-01-01' && v <= '2100-12-31' && Number.isFinite(new Date(v + 'T00:00:00Z').getTime()) && new Date(v + 'T00:00:00Z').toISOString().slice(0, 10) === v, 'Invalid date');
const id = z.string().min(1).max(200);
const money = z.number().int().min(0).max(1_000_000_000_000);
const name = z.string().trim().min(1).max(120);
const type = z.enum(['income', 'expense']);
const schemas: Record<Kind, z.ZodType> = {
  category: z.object({ name, type, color: z.string().regex(/^#[0-9a-fA-F]{6}$/).default('#8b5cf6'), icon: z.string().max(80).default('') }),
  paymentMethod: z.object({ name, icon: z.string().max(80).default('') }),
  transaction: z.object({ type, amount: money.positive(), categoryId: id, paymentMethodId: id, date: dateSchema, description: z.string().max(1000).default(''), occurrenceId: id.nullable().optional() }),
  plan: z.object({ name, type, planType: z.enum(['salary', 'income', 'emi', 'subscription', 'expense', 'recharge']), amount: money.positive(), categoryId: id, startDate: dateSchema, endDate: dateSchema.nullable().optional(), recurrence: z.enum(['once', 'weekly', 'monthly', 'yearly', 'custom']), intervalDays: z.number().int().min(1).max(3650).optional(), reminders: z.boolean().default(true), pausedAt: dateSchema.nullable().optional() }).refine(d => d.recurrence !== 'custom' || !!d.intervalDays, 'Enter a validity / interval in days').refine(d => d.planType !== 'recharge' || (d.type === 'expense' && d.recurrence === 'custom' && !!d.intervalDays), 'Recharge plans require expense type and validity in days').refine(d => !d.endDate || d.endDate >= d.startDate, 'End date precedes start date').refine(d => (d.planType === 'salary' || d.planType === 'income') === (d.type === 'income'), 'Plan type does not match income/expense'),
  occurrence: z.object({ planId: id, name, type, amount: money.positive(), categoryId: id, date: dateSchema, reminders: z.boolean(), status: z.enum(['pending', 'skipped']) }),
  budget: z.object({ categoryId: id, amount: money }),
  preferences: z.object({ payday: z.number().int().min(1).max(31), savings: money, limitMode: z.enum(['warn', 'block']), notifications: z.boolean().default(true) }),
  adjustment: z.object({ amount: z.number().int().min(-1_000_000_000_000).max(1_000_000_000_000), date: dateSchema, description: z.string().max(1000).default('Opening balance adjustment') }),
};
export function validateData(kind: Kind, data: unknown): Data { return schemas[kind].parse(data) as Data }
export const mutationSchema = z.object({ id, changes: z.array(z.object({ id, kind: z.enum(kinds), data: z.record(z.string(), z.unknown()), baseRevision: z.number().int().nonnegative(), deleted: z.boolean().default(false) })).min(1).max(500) });
export const defaults: Data = { payday: 1, savings: 0, limitMode: 'warn', notifications: true };
export function document(id: string, kind: Kind, data: Data): Document { return { id, kind, data, revision: 0, deleted: false } }
