import { api, body } from '@/lib/server/http';
import { logout } from '@/lib/server/mobile-auth';
export const runtime = 'nodejs';
export async function POST(req: Request) { return api(async () => logout(await body(req))); }
