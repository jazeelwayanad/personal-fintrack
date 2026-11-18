import { api } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { readUpiAttempt } from '@/lib/server/upi';

export async function GET(req: Request, context: { params: Promise<{ id: string }> }) {
  return api(async () => readUpiAttempt(await requireUser(req), (await context.params).id));
}
