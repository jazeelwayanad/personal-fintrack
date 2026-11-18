import { api, body } from '@/lib/server/http';
import { consumeAccountToken, requestPasswordReset } from '@/lib/server/account-tokens';

export async function POST(req: Request) {
  return api(async () => requestPasswordReset(await body(req, 2048)));
}
export async function PUT(req: Request) {
  return api(async () => consumeAccountToken(await body(req, 2048)));
}
