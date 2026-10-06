import { api, body } from '@/lib/server/http';
import { login, logout } from '@/lib/server/mobile-auth';
export async function POST(req: Request) { return api(async () => { const result = await login(await body(req), true); await logout({ refreshToken: result.refreshToken }); return result.user; }); }
