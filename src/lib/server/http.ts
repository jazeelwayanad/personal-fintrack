import { ZodError } from 'zod';
import { ApiError } from '@/lib/server/api-error';
export async function api(run: () => Promise<unknown>) {
  try { return Response.json(await run(), { headers: { 'Cache-Control': 'no-store' } }); }
  catch (e) {
    if (e instanceof ZodError) return Response.json({ error: 'Please check your entries.', details: e.issues.map(i => i.message) }, { status: 400 });
    if (e instanceof ApiError) return Response.json({ error: e.message }, { status: e.status });
    console.error('[API]', e instanceof Error ? e.name : 'Unknown error');
    return Response.json({ error: 'The request could not be completed. Please retry.' }, { status: 500 });
  }
}
export async function body(req: Request, limit = 1_000_000): Promise<unknown> {
  if (Number(req.headers.get('content-length')) > limit) throw new ApiError(413, 'Request too large.');
  const reader = req.body?.getReader();
  if (!reader) throw new ApiError(400, 'Invalid JSON.');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let bytes = 0;
  let text = '';
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > limit) throw new ApiError(413, 'Request too large.');
      text += decoder.decode(value, { stream: true });
    }
    return JSON.parse(text + decoder.decode());
  } catch (error) {
    await reader.cancel().catch(() => {});
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, 'Invalid JSON.');
  } finally {
    reader.releaseLock();
  }
}
