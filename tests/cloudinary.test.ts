import { afterEach, describe, expect, it, vi } from 'vitest';
import { createHash } from 'node:crypto';
vi.mock('@/lib/server/sync', () => ({ ApiError: class extends Error { constructor(public status: number, message: string) { super(message); } } }));
import { cloudinarySignature, uploadCloudinaryPhoto, deleteCloudinaryPhoto } from '../src/lib/server/cloudinary';
const configure = () => { vi.stubEnv('CLOUDINARY_CLOUD_NAME', 'test'); vi.stubEnv('CLOUDINARY_API_KEY', 'key'); vi.stubEnv('CLOUDINARY_API_SECRET', 'secret'); };
afterEach(() => { vi.unstubAllEnvs(); vi.restoreAllMocks(); });
describe('Cloudinary signed storage', () => {
  it('signs alphabetically sorted parameters with SHA-256 without exposing the secret', () => {
    expect(cloudinarySignature({ type: 'authenticated', public_id: 'fintrack/profiles/test', timestamp: '123' }, 'secret')).toBe(createHash('sha256').update('public_id=fintrack/profiles/test&timestamp=123&type=authenticatedsecret').digest('hex'));
  });
  it('handles storage failures with a recovery message', async () => {
    configure(); vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 500 }));
    await expect(uploadCloudinaryPhoto(new Uint8Array([1]), 'image/jpeg')).rejects.toThrow('Please retry');
  });
  it('rejects public delivery results and unexpected storage identities', async () => {
    configure(); vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ public_id: 'unexpected', type: 'upload', format: 'jpg' }));
    await expect(uploadCloudinaryPhoto(new Uint8Array([1]), 'image/jpeg')).rejects.toThrow('invalid result');
  });
  it('only treats confirmed or already-missing deletion as successful', async () => {
    configure(); vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ result: 'error' }));
    await expect(deleteCloudinaryPhoto('fintrack/profiles/test')).rejects.toThrow('could not be removed');
  });
});
