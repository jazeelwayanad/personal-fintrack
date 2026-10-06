import { api, body } from '@/lib/server/http';
import { login } from '@/lib/server/mobile-auth';
export const runtime = 'nodejs';
export async function POST(req: Request) { return api(async () => login(await body(req), false)); }
