import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { previewStatement } from '@/lib/server/upi';

export async function POST(req: Request) {
  return api(async () => previewStatement(await requireUser(req), await body(req, 200_000)));
}
