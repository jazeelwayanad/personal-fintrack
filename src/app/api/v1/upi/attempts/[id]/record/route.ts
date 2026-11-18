import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { recordUpiExpense } from '@/lib/server/upi';

export async function POST(req: Request, context: { params: Promise<{ id: string }> }) {
  return api(async () => recordUpiExpense(await requireUser(req), (await context.params).id, await body(req, 8192)));
}
