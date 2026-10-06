import { api, body } from '@/lib/server/http';
import { refresh } from '@/lib/server/mobile-auth';
export const runtime = 'nodejs';
export async function POST(req: Request) { return api(async () => refresh(await body(req))); }
