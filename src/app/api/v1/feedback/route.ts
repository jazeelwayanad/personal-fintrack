import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { submitFeedback } from '@/lib/server/feedback';
export const runtime = 'nodejs';
export async function POST(req: Request) {
  return api(async () => submitFeedback(await requireUser(req), await body(req)));
}
