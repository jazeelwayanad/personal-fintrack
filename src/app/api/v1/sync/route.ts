import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { pull, push } from '@/lib/server/sync';
export const runtime = 'nodejs';
export async function GET(req: Request) { return api(async () => pull(await requireUser(req), Number(new URL(req.url).searchParams.get('since') ?? '0'))); }
export async function POST(req: Request) { return api(async () => push(await requireUser(req), await body(req))); }
