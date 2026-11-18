import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { signOutEverywhere } from '@/lib/server/account-tokens';

export async function POST(req: Request) {
  return api(async () => signOutEverywhere(await requireUser(req), await body(req, 2048), req));
}
