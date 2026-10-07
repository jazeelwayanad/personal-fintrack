import { requireFinanceCapability } from '@/lib/server/finance-capability';
import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { pull, push } from '@/lib/server/sync';
export const runtime = 'nodejs';
export async function GET(req: Request) { return api(async () => { const userId = await requireUser(req); requireFinanceCapability(req); return pull(userId, Number(new URL(req.url).searchParams.get('since') ?? '0')); }); }
export async function POST(req: Request) { return api(async () => { const userId = await requireUser(req); requireFinanceCapability(req); return push(userId, await body(req)); }); }
