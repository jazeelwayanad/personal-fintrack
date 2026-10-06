import { ZodError } from 'zod';
import { ApiError } from './sync';
export async function api(run: () => Promise<unknown>) {
  try { return Response.json(await run(), { headers: { 'Cache-Control': 'no-store' } }); }
  catch (e) {
    if (e instanceof ZodError) return Response.json({ error: 'Please check your entries.', details: e.issues.map(i => i.message) }, { status: 400 });
    if (e instanceof ApiError) return Response.json({ error: e.message }, { status: e.status });
    console.error('[API]', e instanceof Error ? e.message : 'Unknown error');
    return Response.json({ error: 'The request could not be completed. Please retry.' }, { status: 500 });
  }
}
export async function body(req: Request) { const text = await req.text(); if (text.length > 1_000_000) throw new ApiError(413, 'Request too large.'); try { return JSON.parse(text); } catch { throw new ApiError(400, 'Invalid JSON.'); } }
