import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { readAccount, updateAccount } from '@/lib/server/account';
export const runtime = 'nodejs';
export async function GET(req: Request) { return api(async () => readAccount(await requireUser(req))); }
export async function PATCH(req: Request) { return api(async () => updateAccount(await requireUser(req), await body(req))); }
