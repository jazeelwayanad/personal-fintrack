import { createCipheriv, createDecipheriv, createHmac, randomBytes } from 'node:crypto';

export function secretKey(value: string | undefined) {
  if (!value || !/^[0-9a-f]{64}$/i.test(value)) throw new Error('Invalid integration key');
  return Buffer.from(value, 'hex');
}

export function fingerprint(key: Buffer, value: unknown) {
  return createHmac('sha256', key).update(JSON.stringify(value)).digest('hex');
}

export function seal(key: Buffer, value: string, context: string) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(context));
  const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), encrypted]).toString('base64url');
}

export function openSealed(key: Buffer, value: string, context: string) {
  const encrypted = Buffer.from(value, 'base64url');
  const decipher = createDecipheriv('aes-256-gcm', key, encrypted.subarray(0, 12));
  decipher.setAAD(Buffer.from(context));
  decipher.setAuthTag(encrypted.subarray(12, 28));
  return Buffer.concat([decipher.update(encrypted.subarray(28)), decipher.final()]).toString('utf8');
}
