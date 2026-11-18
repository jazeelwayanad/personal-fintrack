import { z } from 'zod';
import { dateSchema } from './model';

export const normalizeStatementReference = (value: string) => value.normalize('NFKC').toUpperCase().replace(/\s+/gu, '');
export const statementRow = z.strictObject({
  date: dateSchema,
  amountPaise: z.number().int().positive().max(1_000_000_000_000),
  direction: z.literal('debit'),
  reference: z.string().trim().min(1).max(120).transform(normalizeStatementReference),
});

export function parseStatement(content: string) {
  const lines = content.replace(/^\uFEFF/, '').trim().split(/\r?\n/);
  if (lines[0].toLowerCase().trim() !== 'date,amount,direction,reference' || lines.length < 2 || lines.length > 501) {
    throw new Error('Use a CSV with up to 500 rows and the header date,amount,direction,reference.');
  }
  const rows: z.output<typeof statementRow>[] = [];
  for (const [index, line] of lines.slice(1).entries()) {
    const match = /^(\d{4}-\d{2}-\d{2})\s*,\s*(\d{1,11})(?:\.(\d{1,2}))?\s*,\s*(debit|credit)\s*,\s*((?:"(?:[^"\r\n]|"")*")|[^",\r\n]+)$/i.exec(line);
    if (!match) throw new Error('Invalid statement row ' + (index + 2) + '.');
    const [, date, major, minor = '', direction, raw] = match;
    if (direction.toLowerCase() !== 'debit') continue;
    const reference = raw.startsWith('"') ? raw.slice(1, -1).replaceAll('""', '"') : raw.trim();
    const parsed = statementRow.safeParse({ date, amountPaise: Number(major) * 100 + Number(minor.padEnd(2, '0')), direction: 'debit', reference });
    if (!parsed.success) throw new Error('Invalid debit on statement row ' + (index + 2) + '.');
    rows.push(parsed.data);
  }
  return rows;
}
