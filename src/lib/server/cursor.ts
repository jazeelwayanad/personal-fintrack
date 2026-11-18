import { timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { ApiError } from './api-error';
import { fingerprint, secretKey } from './integration-secret';

export function signCursor(value: unknown, context: unknown) {
  const encoded = Buffer.from(JSON.stringify(value)).toString('base64url');
  return encoded + '.' + fingerprint(secretKey(process.env.MCP_STATE_KEY), { context, encoded });
}

export function readCursor<T extends z.ZodType>(token: string, schema: T, context: unknown): z.output<T> {
  const parts = token.split('.');
  const [encoded, signature] = parts;
  const expected = fingerprint(secretKey(process.env.MCP_STATE_KEY), { context, encoded });
  if (parts.length !== 2 || !/^[0-9a-f]{64}$/.test(signature ?? '')
    || !timingSafeEqual(Buffer.from(expected, 'hex'), Buffer.from(signature, 'hex'))) {
    throw new ApiError(400, 'Invalid cursor.');
  }
  try {
    return z.parse(schema, JSON.parse(Buffer.from(encoded, 'base64url').toString()));
  } catch {
    throw new ApiError(400, 'Invalid cursor.');
  }
}
