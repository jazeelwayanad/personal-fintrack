import { createHash, randomUUID } from 'node:crypto';
import { ApiError } from './sync';

export const cloudinaryEnabled = () => Boolean(process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET);
function config() {
  if (!cloudinaryEnabled()) throw new ApiError(503, 'Photo uploads are not configured yet. Please contact the app administrator.');
  const cloud = process.env.CLOUDINARY_CLOUD_NAME!;
  if (!/^[\w-]+$/.test(cloud)) throw new ApiError(503, 'Photo storage configuration is invalid.');
  return { cloud, key: process.env.CLOUDINARY_API_KEY!, secret: process.env.CLOUDINARY_API_SECRET! };
}
export function cloudinarySignature(parameters: Record<string, string>, secret: string) {
  const canonical = Object.keys(parameters).sort().map(key => `${key}=${parameters[key]}`).join('&');
  return createHash('sha256').update(canonical + secret).digest('hex');
}
function signed(parameters: Record<string, string>) {
  const { cloud, key, secret } = config();
  return { cloud, parameters: { ...parameters, api_key: key, signature: cloudinarySignature(parameters, secret) } };
}
async function action(name: 'upload' | 'destroy', parameters: Record<string, string>, file?: Blob) {
  const signedRequest = signed(parameters), form = new FormData();
  Object.entries(signedRequest.parameters).forEach(([key, value]) => form.set(key, value));
  if (file) form.set('file', file, 'profile-photo');
  let response: Response;
  try { response = await fetch(`https://api.cloudinary.com/v1_1/${signedRequest.cloud}/image/${name}`, { method: 'POST', body: form, signal: AbortSignal.timeout(20000) }); }
  catch { throw new ApiError(502, 'Photo storage could not be reached. Please retry.'); }
  if (!response.ok) throw new ApiError(502, 'Photo storage could not complete the request. Please retry.');
  return response.json();
}
export async function uploadCloudinaryPhoto(bytes: Uint8Array, type: string) {
  const publicId = `fintrack/profiles/${randomUUID()}`;
  const result = await action('upload', { public_id: publicId, type: 'authenticated', overwrite: 'false', timestamp: String(Math.floor(Date.now() / 1000)) }, new Blob([new Uint8Array(bytes)], { type }));
  if (result.public_id !== publicId || !['jpg', 'jpeg', 'png', 'webp'].includes(result.format) || result.type !== 'authenticated') throw new ApiError(502, 'Photo storage returned an invalid result. Please retry.');
  return { publicId, format: String(result.format), type: result.format === 'png' ? 'image/png' : result.format === 'webp' ? 'image/webp' : 'image/jpeg' };
}
export async function deleteCloudinaryPhoto(publicId: string) {
  const result = await action('destroy', { public_id: publicId, type: 'authenticated', invalidate: 'true', timestamp: String(Math.floor(Date.now() / 1000)) });
  if (!['ok', 'not found'].includes(result.result)) throw new ApiError(502, 'The photo could not be removed. Please retry.');
}
export async function downloadCloudinaryPhoto(publicId: string, format: string) {
  const { cloud, secret } = config();
  if (!/^fintrack\/profiles\/[a-f0-9-]+$/.test(publicId) || !['jpg', 'jpeg', 'png', 'webp'].includes(format)) throw new ApiError(502, 'Photo reference is invalid.');
  // Signed CDN delivery stays behind our authenticated proxy; the URL never reaches the browser.
  const path = `c_limit,h_384,w_384,q_auto:good/${publicId}.${format}`;
  const signature = createHash('sha256').update(path + secret).digest('base64url').slice(0, 8);
  let response: Response;
  try { response = await fetch(`https://res.cloudinary.com/${cloud}/image/authenticated/s--${signature}--/${path}`, { cache: 'no-store', signal: AbortSignal.timeout(20000) }); }
  catch { throw new ApiError(502, 'Your photo could not be loaded. Please retry.'); }
  if (!response.ok) throw new ApiError(502, 'Your photo could not be loaded. Please retry.');
  return response;
}
